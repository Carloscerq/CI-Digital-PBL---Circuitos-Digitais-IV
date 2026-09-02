#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${DATASET_ROOT:?Defina DATASET_ROOT com o caminho da pasta dataset_q915}"
: "${CASE_NAME:?Defina CASE_NAME com o nome da pasta a testar}"

MAX_SAMPLES="${MAX_SAMPLES:-4096}"
SAVE_SAMPLES="${SAVE_SAMPLES:-1024}"
RESULTS_ROOT="${RESULTS_ROOT:-${PROJECT_ROOT}/results_lms_time_xcelium}"
CASE_DIR="${DATASET_ROOT}/${CASE_NAME}"
CASE_RESULTS="${RESULTS_ROOT}/${CASE_NAME}"

mkdir -p "${CASE_RESULTS}"

SENSOR1_FILE="${CASE_DIR}/${CASE_NAME}_sensor1.mem"
SENSOR2_FILE="${CASE_DIR}/${CASE_NAME}_sensor2.mem"
SENSOR3_FILE="${CASE_DIR}/${CASE_NAME}_sensor3.mem"
SENSOR4_FILE="${CASE_DIR}/${CASE_NAME}_sensor4.mem"

for input_file in \
    "${SENSOR1_FILE}" \
    "${SENSOR2_FILE}" \
    "${SENSOR3_FILE}" \
    "${SENSOR4_FILE}"; do
    if [[ ! -f "${input_file}" ]]; then
        echo "ERRO: arquivo nao encontrado: ${input_file}" >&2
        exit 2
    fi
done

cd "${PROJECT_ROOT}"

xrun -64bit -sv \
    -timescale 1ns/1ps \
    -access +rwc \
    -xmlibdirname "${CASE_RESULTS}/xcelium.d" \
    rtl/lms/lms_filter_time_serial.v \
    verification/tb_lms_time_4sensor_dataset.sv \
    -top tb_lms_time_4sensor_dataset \
    "+SENSOR1_FILE=${SENSOR1_FILE}" \
    "+SENSOR2_FILE=${SENSOR2_FILE}" \
    "+SENSOR3_FILE=${SENSOR3_FILE}" \
    "+SENSOR4_FILE=${SENSOR4_FILE}" \
    "+MAX_SAMPLES=${MAX_SAMPLES}" \
    "+SAVE_SAMPLES=${SAVE_SAMPLES}" \
    "+OUTPUT_CSV=${CASE_RESULTS}/lms_outputs.csv" \
    "+REPORT_FILE=${CASE_RESULTS}/report.txt" \
    -l "${CASE_RESULTS}/xrun.log"

echo "LMS FINALIZADO: ${CASE_RESULTS}"
