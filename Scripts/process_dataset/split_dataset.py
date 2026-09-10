#!/usr/bin/env python3
"""
Automatically extracts and separates sensors from .mat and .tdms files.
Domains supported:
  - Vibration (.mat) : Extracts 4 channels.
  - Temperature & Motor Current (.tdms) : Reads a single file and bifurcates 
    the output into two distinct datasets (2 sensors for Temp, 3 for Current).
"""

import sys
from pathlib import Path
import scipy.io
import pandas as pd

try:
    from nptdms import TdmsFile
except ImportError:
    print("ERROR: Missing required library 'nptdms'.")
    print("Please install it using: pip install nptdms")
    sys.exit(1)

#
# CONFIGURATION
#

BASE_INPUT_DIR = Path("data")
BASE_OUTPUT_DIR = Path("dataset_split")

VIBRATION_DIR = BASE_INPUT_DIR / "vibration"
TDMS_DIR = BASE_INPUT_DIR / "temp_current"

OUT_VIBRATION = BASE_OUTPUT_DIR / "vibration"
OUT_TEMPERATURE = BASE_OUTPUT_DIR / "temperature"
OUT_CURRENT = BASE_OUTPUT_DIR / "current"


def process_vibration_file(file_path: Path) -> None:
    """Extracts 4 vibration sensors from the nested MATLAB structure."""
    mat = scipy.io.loadmat(file_path)
    
    signal = mat["Signal"]["y_values"][0, 0]["values"][0, 0]

    if signal.ndim != 2:
        raise ValueError(f"Signal matrix does not have 2 dimensions (shape: {signal.shape}).")

    n_samples, n_channels = signal.shape

    if n_channels != 4:
        raise ValueError(f"Expected 4 vibration sensors, found {n_channels}.")

    df_sensors = pd.DataFrame(signal)
    
    case_folder = OUT_VIBRATION / file_path.stem
    case_folder.mkdir(parents=True, exist_ok=True)

    print(f"Samples : {n_samples:,} | Channels : {n_channels}")

    for sensor_idx in range(n_channels):
        output_csv = case_folder / f"{file_path.stem}_sensor{sensor_idx + 1}.csv"
        df_sensors.iloc[:, sensor_idx].to_csv(output_csv, index=False, header=False)
        print(f"   ✓ [Vibration] {output_csv.name}")


def process_tdms_file(file_path: Path) -> None:
    """
    Extracts sensor data from TDMS. Handles internal formatting where 
    Time Stamp might not be an explicit column in nptdms extraction.
    """
    tdms_file = TdmsFile.read(file_path)
    df = tdms_file.as_dataframe()

    # If nptdms extracts the time stamp explicitly, it will have 6 columns.
    # If it extracts only the raw data channels, it will have 5 columns.
    if df.shape[1] == 6:
        df_sensors = df.iloc[:, 1:]
    elif df.shape[1] == 5:
        df_sensors = df
    else:
        raise ValueError(f"Unexpected number of TDMS columns: {df.shape[1]}")
    
    n_channels = df_sensors.shape[1]
    if n_channels != 5:
        raise ValueError(f"Expected 5 TDMS sensors, found {n_channels}.")

    # Bifurcate the matrix: 
    # Indices 0, 1 -> Temperature
    # Indices 2, 3, 4 -> Motor Current
    df_temp = df_sensors.iloc[:, 0:2]
    df_curr = df_sensors.iloc[:, 2:5]

    case_name = file_path.stem
    
    temp_folder = OUT_TEMPERATURE / case_name
    curr_folder = OUT_CURRENT / case_name
    temp_folder.mkdir(parents=True, exist_ok=True)
    curr_folder.mkdir(parents=True, exist_ok=True)

    n_samples = df_sensors.shape[0]
    print(f"Samples : {n_samples:,} | Temp Channels : 2 | Current Channels : 3")

    # Save Temperature channels
    for idx in range(df_temp.shape[1]):
        output_csv = temp_folder / f"{case_name}_sensor{idx + 1}.csv"
        df_temp.iloc[:, idx].to_csv(output_csv, index=False, header=False)
        print(f"   ✓ [Temperature] {output_csv.name}")

    # Save Motor Current channels
    for idx in range(df_curr.shape[1]):
        output_csv = curr_folder / f"{case_name}_sensor{idx + 1}.csv"
        df_curr.iloc[:, idx].to_csv(output_csv, index=False, header=False)
        print(f"   ✓ [Current] {output_csv.name}")


def main():
    BASE_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if VIBRATION_DIR.exists():
        mat_files = sorted(VIBRATION_DIR.glob("*.mat"))
        print(f"\n[VIBRATION] Found {len(mat_files)} files to process.")
        
        for file_path in mat_files:
            print("-" * 70)
            print(f"Processing: {file_path.name}")
            try:
                process_vibration_file(file_path)
            except Exception as e:
                print(f"ERROR processing {file_path.name}: {e}")
    else:
        print(f"Skipping VIBRATION: Directory '{VIBRATION_DIR}' not found.")

    if TDMS_DIR.exists():
        tdms_files = sorted(TDMS_DIR.glob("*.tdms"))
        print(f"\n[TEMP & CURRENT] Found {len(tdms_files)} files to process.")
        
        for file_path in tdms_files:
            print("-" * 70)
            print(f"Processing: {file_path.name}")
            try:
                process_tdms_file(file_path)
            except Exception as e:
                print(f"ERROR processing {file_path.name}: {e}")
    else:
        print(f"Skipping TEMP & CURRENT: Directory '{TDMS_DIR}' not found.")

    print("\nDataset separation and bifurcation completed successfully.")


if __name__ == "__main__":
    main()