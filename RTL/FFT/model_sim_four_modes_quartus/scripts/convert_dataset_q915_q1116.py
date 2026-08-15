#!/usr/bin/env python3
"""Converte o dataset bruto para signed Q9.15 e signed Q11.16.

Entrada esperada:
    dataset_split/<caso>/<caso>_sensor1.csv
    ...
    dataset_split/<caso>/<caso>_sensor4.csv

Cada CSV deve possuir uma coluna numerica, sem cabecalho. Os CSVs de origem
nao sao modificados e nenhum fator /256 e aplicado.
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


SENSOR_PATTERN = re.compile(
    r"^(?P<case>.+)_sensor(?P<sensor>[1-4])$", re.IGNORECASE
)
EXPECTED_SENSORS = {1, 2, 3, 4}
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
            "Converte todos os *_sensor1.csv ... *_sensor4.csv para "
            "Q9.15 e Q11.16 em complemento de dois."
        )
    )
    parser.add_argument(
        "--input", type=Path, default=Path("dataset_split"),
        help="pasta dos CSVs brutos (padrao: dataset_split)",
    )
    parser.add_argument(
        "--output-q915", type=Path, default=Path("dataset_q915"),
        help="pasta dos .mem Q9.15 (padrao: dataset_q915)",
    )
    parser.add_argument(
        "--output-q1116", type=Path, default=Path("dataset_q1116"),
        help="pasta dos .mem Q11.16 (padrao: dataset_q1116)",
    )
    parser.add_argument(
        "--case",
        help="converte somente um caso, por exemplo 4Nm_BPFI_03",
    )
    parser.add_argument(
        "--max-samples", type=int,
        help="limita amostras por sensor somente para um teste rapido",
    )
    parser.add_argument(
        "--allow-incomplete-frame", action="store_true",
        help="permite numero de amostras nao multiplo de 64",
    )
    return parser.parse_args()


def discover_files(input_dir: Path, selected_case: str | None) -> list[Path]:
    groups: dict[Path, dict[int, Path]] = {}

    for path in sorted(input_dir.rglob("*.csv")):
        match = SENSOR_PATTERN.fullmatch(path.stem)
        if match is None:
            continue
        relative = path.relative_to(input_dir)
        if selected_case is not None:
            if len(relative.parts) < 2 or relative.parts[0] != selected_case:
                continue
        sensor = int(match.group("sensor"))
        group = groups.setdefault(path.parent, {})
        if sensor in group:
            raise RuntimeError(
                f"{path.parent}: mais de um arquivo para o sensor {sensor}"
            )
        group[sensor] = path

    if not groups:
        suffix = f" para o caso {selected_case}" if selected_case else ""
        raise RuntimeError(
            "Nenhum *_sensor1.csv ... *_sensor4.csv encontrado" + suffix
        )

    ordered: list[Path] = []
    for directory in sorted(groups, key=lambda item: item.as_posix().lower()):
        found = set(groups[directory])
        if found != EXPECTED_SENSORS:
            missing = sorted(EXPECTED_SENSORS - found)
            extra = sorted(found - EXPECTED_SENSORS)
            raise RuntimeError(
                f"{directory}: conjunto de sensores invalido; "
                f"faltando={missing}, extras={extra}"
            )
        ordered.extend(groups[directory][sensor] for sensor in sorted(EXPECTED_SENSORS))
    return ordered


def load_csv(path: Path, max_samples: int | None) -> np.ndarray:
    try:
        values = np.loadtxt(
            path,
            delimiter=",",
            dtype=np.float64,
            ndmin=1,
            encoding="utf-8-sig",
            max_rows=max_samples,
        )
    except (OSError, ValueError) as exc:
        raise RuntimeError(
            f"Falha ao ler {path}. Esperado CSV com uma coluna numerica "
            f"e sem cabecalho: {exc}"
        ) from exc

    if values.ndim != 1 or values.size == 0:
        raise RuntimeError(f"{path}: esperado CSV nao vazio com uma coluna")
    if not np.all(np.isfinite(values)):
        raise RuntimeError(f"{path}: foram encontrados NaN ou Inf")
    return values


def quantize(values: np.ndarray, fmt: FixedFormat, source: Path) -> np.ndarray:
    codes_float = np.rint(values * fmt.scale)
    positive_overflows = int(np.count_nonzero(codes_float > fmt.maximum_code))
    negative_overflows = int(np.count_nonzero(codes_float < fmt.minimum_code))
    if positive_overflows or negative_overflows:
        raise RuntimeError(
            f"{source}: {fmt.name} nao comporta a entrada; "
            f"overflows positivos={positive_overflows}, "
            f"negativos={negative_overflows}. Nenhum valor sera saturado "
            "silenciosamente."
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
        raise SystemExit(f"Pasta de entrada nao encontrada: {args.input}")
    if args.max_samples is not None and args.max_samples <= 0:
        raise SystemExit("--max-samples deve ser maior que zero")

    formats = (
        FixedFormat("signed Q9.15", 24, 9, 15, args.output_q915),
        FixedFormat("signed Q11.16", 27, 11, 16, args.output_q1116),
    )
    files = discover_files(args.input, args.case)
    manifests: dict[str, list[dict[str, object]]] = {
        fmt.name: [] for fmt in formats
    }
    total_samples = 0

    for index, source in enumerate(files, start=1):
        values = load_csv(source, args.max_samples)
        if values.size % FRAME_SIZE and not args.allow_incomplete_frame:
            raise RuntimeError(
                f"{source}: {values.size} amostras nao formam frames "
                f"completos de {FRAME_SIZE}"
            )

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
        print(
            f"[{index:03d}/{len(files):03d}] {relative}: "
            f"{values.size:,} amostras -> Q9.15 + Q11.16"
        )

    for fmt in formats:
        write_metadata(fmt, manifests[fmt.name])

    print()
    print("CONVERSAO CONCLUIDA")
    print(f"Arquivos CSV convertidos : {len(files)}")
    print(f"Amostras por formato     : {total_samples:,}")
    print(f"Saida Q9.15              : {args.output_q915}")
    print(f"Saida Q11.16             : {args.output_q1116}")
    print("Saturacoes na entrada    : 0")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        raise SystemExit(f"ERRO: {exc}") from exc
