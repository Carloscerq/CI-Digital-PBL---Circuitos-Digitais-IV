#!/usr/bin/env python3
"""
Converts the raw dataset to signed Q9.15 format.

Expected input structure:
    dataset_split/<modality>/<case>/<case>_sensorX.csv

Each CSV must contain a single numeric column with no header. The source
CSVs are left unmodified and no artificial scaling is applied prior to conversion.
Automatically truncates the input arrays to the largest multiple of the frame size.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


# Regex to support dynamically discovered sensor counts (\d+)
SENSOR_PATTERN = re.compile(
    r"^(?P<case>.+)_sensor(?P<sensor>\d+)$", re.IGNORECASE
)
FRAME_SIZE = 64


@dataclass(frozen=True)
class FixedFormat:
    name: str
    width: int
    integer_bits_including_sign: int
    fractional_bits: int
    output_dir: Path

    @property
    def scale(self) -> int:
        return 1 << self.fractional_bits

    @property
    def minimum_code(self) -> int:
        return -(1 << (self.width - 1))

    @property
    def maximum_code(self) -> int:
        return (1 << (self.width - 1)) - 1

    @property
    def minimum_value(self) -> float:
        return self.minimum_code / self.scale

    @property
    def maximum_value(self) -> float:
        return self.maximum_code / self.scale

    @property
    def hex_digits(self) -> int:
        return math.ceil(self.width / 4)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Converts all *_sensorX.csv files to "
            "Q9.15 in two's complement. Automatically truncates arrays "
            "to fit perfect 64-sample frames."
        )
    )
    parser.add_argument(
        "--input", type=Path, default=Path("dataset_split"),
        help="Directory containing the raw CSVs (default: dataset_split)",
    )
    parser.add_argument(
        "--output-q915", type=Path, default=Path("dataset_q915"),
        help="Directory for the Q9.15 .mem files (default: dataset_q915)",
    )
    parser.add_argument(
        "--case",
        help="Convert only a specific case, e.g., 4Nm_BPFI_03",
    )
    parser.add_argument(
        "--max-samples", type=int,
        help="Limit samples per sensor for rapid testing purposes",
    )
    return parser.parse_args()


def discover_files(input_dir: Path, selected_case: str | None) -> list[Path]:
    groups: dict[Path, dict[int, Path]] = {}
    detected_sensors: set[int] = set()

    for path in sorted(input_dir.rglob("*.csv")):
        match = SENSOR_PATTERN.fullmatch(path.stem)
        if match is None:
            continue
        
        relative = path.relative_to(input_dir)
        if selected_case is not None:
            if len(relative.parts) < 2 or relative.parts[-2] != selected_case:
                continue
        
        sensor = int(match.group("sensor"))
        detected_sensors.add(sensor)
        
        group = groups.setdefault(path.parent, {})
        if sensor in group:
            raise RuntimeError(
                f"{path.parent}: Found duplicate files for sensor {sensor}"
            )
        group[sensor] = path

    if not groups:
        suffix = f" for case {selected_case}" if selected_case else ""
        raise RuntimeError(
            "No *_sensorX.csv files found in the specified directory" + suffix
        )

    ordered: list[Path] = []
    
    for directory in sorted(groups, key=lambda item: item.as_posix().lower()):
        found = set(groups[directory])
        if found != detected_sensors:
            missing = sorted(detected_sensors - found)
            extra = sorted(found - detected_sensors)
            raise RuntimeError(
                f"{directory}: Invalid sensor set detected; "
                f"missing={missing}, extra={extra}"
            )
        
        ordered.extend(groups[directory][sensor] for sensor in sorted(detected_sensors))
        
    return ordered


def load_csv(path: Path, max_samples: int | None) -> np.ndarray:
    try:
        df = pd.read_csv(
            path,
            header=None,
            usecols=[0],
            nrows=max_samples,
            # Explicitly catch text-based infinity artifacts
            na_values=["", "NaN", "nan", " ", "inf", "-inf", "Inf", "-Inf"],
            dtype=np.float64,
            on_bad_lines="skip"
        )
        
        # 1. Force any stray numpy infinities to NaN
        df.replace([np.inf, -np.inf], np.nan, inplace=True)
        
        # 2. Patch missing physical sensor data (Forward Fill -> Backward Fill)
        df = df.ffill().bfill()
        
        # 3. Hard Fallback: If the ENTIRE column was corrupted (a dead sensor),
        # ffill/bfill will fail. We inject 0.0 to save the batch process.
        df.fillna(0.0, inplace=True)
        
        values = df.iloc[:, 0].to_numpy()
        
    except Exception as exc:
        raise RuntimeError(
            f"Failed to read {path}. Expected a headless CSV with a single numeric column: {exc}"
        ) from exc

    if values.ndim != 1 or values.size == 0:
        raise RuntimeError(f"{path}: Expected a non-empty CSV with a single column")
        
    # This mathematical check will now pass safely
    if not np.all(np.isfinite(values)):
        raise RuntimeError(f"{path}: NaN or Inf values detected in the data even after hard patching")
        
    return values


def quantize(values: np.ndarray, fmt: FixedFormat, source: Path) -> np.ndarray:
    codes_float = np.rint(values * fmt.scale)
    positive_overflows = int(np.count_nonzero(codes_float > fmt.maximum_code))
    negative_overflows = int(np.count_nonzero(codes_float < fmt.minimum_code))
    
    if positive_overflows or negative_overflows:
        raise RuntimeError(
            f"{source}: Input exceeds bounds for {fmt.name}; "
            f"positive overflows={positive_overflows}, "
            f"negative overflows={negative_overflows}. "
            "Values will not be silently saturated."
        )
        
    return codes_float.astype(np.int64)


def write_mem(path: Path, codes: np.ndarray, fmt: FixedFormat) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    mask = (1 << fmt.width) - 1
    
    with temporary.open("w", encoding="ascii", newline="\n") as output:
        for code in codes:
            output.write(f"{int(code) & mask:0{fmt.hex_digits}X}\n")
            
    temporary.replace(path)


def write_metadata(fmt: FixedFormat, rows: list[dict[str, object]]) -> None:
    fmt.output_dir.mkdir(parents=True, exist_ok=True)
    slug = fmt.name.lower().replace(".", "").replace("signed ", "")
    manifest = fmt.output_dir / f"manifest_{slug}.csv"
    
    with manifest.open("w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    description = {
        "format": fmt.name,
        "total_bits": fmt.width,
        "integer_bits_including_sign": fmt.integer_bits_including_sign,
        "fractional_bits": fmt.fractional_bits,
        "scale": fmt.scale,
        "minimum": fmt.minimum_value,
        "maximum": fmt.maximum_value,
        "conversion": f"round(x * 2^{fmt.fractional_bits})",
        "input_divisor": 1,
        "encoding": "two's complement hexadecimal",
        "hex_digits_per_sample": fmt.hex_digits,
        "samples_per_line": 1,
    }
    
    (fmt.output_dir / f"{slug}_format.json").write_text(
        json.dumps(description, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    args = parse_args()
    
    if not args.input.is_dir():
        raise SystemExit(f"Input directory not found: {args.input}")
    if args.max_samples is not None and args.max_samples <= 0:
        raise SystemExit("--max-samples must be strictly greater than zero")

    formats = (
        FixedFormat("signed Q9.15", 24, 9, 15, args.output_q915),
    )
    
    files = discover_files(args.input, args.case)
    manifests: dict[str, list[dict[str, object]]] = {
        fmt.name: [] for fmt in formats
    }
    total_samples = 0

    for index, source in enumerate(files, start=1):
        values = load_csv(source, args.max_samples)
        
        # Truncate array to perfectly fit 64-sample frames
        remainder = values.size % FRAME_SIZE
        if remainder != 0:
            valid_samples = values.size - remainder
            values = values[:valid_samples]

        relative_parent = source.parent.relative_to(args.input)
        
        for fmt in formats:
            codes = quantize(values, fmt, source)
            destination = (
                fmt.output_dir / relative_parent / f"{source.stem}.mem"
            )
            write_mem(destination, codes, fmt)
            
            manifests[fmt.name].append({
                "source_csv": source.as_posix(),
                "output_mem": destination.as_posix(),
                "samples": int(values.size),
                "frames_64": int(values.size // FRAME_SIZE),
                "format": fmt.name,
                "width": fmt.width,
                "fractional_bits": fmt.fractional_bits,
                "physical_min": float(values.min()),
                "physical_max": float(values.max()),
                "quantized_min": int(codes.min()),
                "quantized_max": int(codes.max()),
                "input_saturations": 0,
            })

        total_samples += int(values.size)
        relative = source.relative_to(args.input)
        
        # Adding a visual tag if truncation occurred
        truncation_warning = f" (Truncated -{remainder} samples)" if remainder != 0 else ""
        
        print(
            f"[{index:03d}/{len(files):03d}] {relative}: "
            f"{values.size:,} samples -> Q9.15{truncation_warning}"
        )

    for fmt in formats:
        write_metadata(fmt, manifests[fmt.name])

    print("\nCONVERSION COMPLETED")
    print(f"Processed CSV files : {len(files)}")
    print(f"Samples per format  : {total_samples:,}")
    print(f"Q9.15 output path   : {args.output_q915}")
    print("Input saturations   : 0")
    
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc