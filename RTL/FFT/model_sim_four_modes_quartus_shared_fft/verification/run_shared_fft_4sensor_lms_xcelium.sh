#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
model_root=$(cd "$script_dir/.." && pwd)
project_root=${PROJECT_ROOT:-$(cd "$model_root/.." && pwd)}

# Aceita tanto os nomes novos quanto os usados nos scripts anteriores.
dataset_q915=${DATASET_ROOT:-${DATASET_Q915:-$project_root/dataset_q915}}
output_dir=${RESULTS_ROOT:-${OUTPUT_DIR:-$model_root/results_shared_fft_4sensor_lms_xcelium}}
case_pattern=${CASE_NAME:-${CASE_PATTERN:-*}}
max_cases=${MAX_CASES:-1}
max_frames=${MAX_FRAMES:-1}
hop_size=${HOP_SIZE:-64}
save_all_bins=${SAVE_ALL_BINS:-0}
lms_adapt_enable=${ADAPT_ENABLE:-1}
lms_mu_shift=${LMS_MU_SHIFT:-16}

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

command -v xrun >/dev/null 2>&1 || fail "xrun nao encontrado no PATH."
[[ -d "$dataset_q915" ]] || fail "dataset Q9.15 nao encontrado: $dataset_q915"
[[ "$hop_size" =~ ^[0-9]+$ ]] &&
    ((hop_size >= 1 && hop_size <= 64)) ||
    fail "HOP_SIZE deve estar entre 1 e 64."
[[ "$lms_adapt_enable" == 0 || "$lms_adapt_enable" == 1 ]] ||
    fail "ADAPT_ENABLE deve ser 0 ou 1."
[[ "$lms_mu_shift" =~ ^[0-9]+$ ]] && ((lms_mu_shift >= 1)) ||
    fail "LMS_MU_SHIFT deve ser inteiro positivo."

sources=(
    rtl/preprocessing/fir_coeff_rom_dualmode.v
    rtl/preprocessing/fir_decimator_stage_dualmode.v
    rtl/preprocessing/fir_decimator_32_dualmode.v
    rtl/lms/lms_filter_time_serial.v
    rtl/framing/sample_buffer_64_hop8_dualmode.v
    rtl/windowing/mean_remover_64_dualmode.v
    rtl/windowing/hann_window_64_dualmode.v
    rtl/fft/dual_port_ram.v
    rtl/fft/fft_coeff_rom_64.v
    rtl/fft/fft_64_dualmode.v
    rtl/fft/fft_shared_4sensor.sv
    rtl/pipeline/preprocess_window_channel_lms.sv
    rtl/pipeline/preprocess_fft_shared_4sensor_q915_lms.sv
    verification/tb_shared_fft_4sensor_lms_dataset.sv
)

cd "$model_root" || fail "nao foi possivel acessar $model_root"
for source in "${sources[@]}"; do
    [[ -f "$source" ]] || fail "fonte ausente: $source"
done

mkdir -p "$output_dir"
mapfile -t all_case_dirs < <(
    find "$dataset_q915" -type f -iname '*.mem' -printf '%h\n' | sort -u
)

selected_cases=()
for case_dir in "${all_case_dirs[@]}"; do
    relative_case=${case_dir#"$dataset_q915"/}
    case_name=$(basename "$case_dir")
    if [[ "$relative_case" == $case_pattern || "$case_name" == $case_pattern ]]; then
        selected_cases+=("$relative_case")
        if ((max_cases > 0 && ${#selected_cases[@]} >= max_cases)); then
            break
        fi
    fi
done

((${#selected_cases[@]} > 0)) ||
    fail "nenhum caso corresponde a CASE_NAME/CASE_PATTERN=$case_pattern"

find_sensor_file() {
    local case_dir=$1
    local sensor=$2
    local -a matches=()
    mapfile -t matches < <(
        find "$case_dir" -maxdepth 1 -type f \
            -iname "*_sensor${sensor}.mem" -print | sort
    )
    ((${#matches[@]} == 1)) && printf '%s\n' "${matches[0]}"
}

manifest=$output_dir/shared_fft_4sensor_lms_manifest.csv
printf '%s\n' \
    'case,hop_size,max_frames,adapt_enable,mu_shift,status,bins_csv,report' \
    > "$manifest"

failed=0
for relative_case in "${selected_cases[@]}"; do
    case_dir=$dataset_q915/$relative_case
    sensor1_file=$(find_sensor_file "$case_dir" 1)
    sensor2_file=$(find_sensor_file "$case_dir" 2)
    sensor3_file=$(find_sensor_file "$case_dir" 3)
    sensor4_file=$(find_sensor_file "$case_dir" 4)
    case_output=$output_dir/$relative_case
    bins_csv=$case_output/bins.csv
    report_file=$case_output/report.txt
    log_file=$case_output/xrun.log
    build_dir=$case_output/xcelium.d
    mkdir -p "$case_output"

    status=PASS
    if [[ -z "$sensor1_file" || -z "$sensor2_file" ||
          -z "$sensor3_file" || -z "$sensor4_file" ]]; then
        status=MISSING_SENSOR
    else
        printf '[XCELIUM][SHARED FFT LMS] caso=%s hop=%s adapt=%s mu_shift=%s\n' \
            "$relative_case" "$hop_size" "$lms_adapt_enable" "$lms_mu_shift"

        xrun -64bit -sv +define+RTL_SIM -timescale 1ns/1ps -access +rwc \
            -xmlibdirname "$build_dir" \
            -top tb_shared_fft_4sensor_lms_dataset \
            -defparam "tb_shared_fft_4sensor_lms_dataset.HOP_SIZE=$hop_size" \
            -defparam "tb_shared_fft_4sensor_lms_dataset.LMS_MU_SHIFT=$lms_mu_shift" \
            "${sources[@]}" \
            "+SENSOR1_FILE=$sensor1_file" \
            "+SENSOR2_FILE=$sensor2_file" \
            "+SENSOR3_FILE=$sensor3_file" \
            "+SENSOR4_FILE=$sensor4_file" \
            "+OUTPUT_BINS_CSV=$bins_csv" \
            "+OUTPUT_REPORT=$report_file" \
            "+MAX_FRAMES=$max_frames" \
            "+SAVE_ALL_BINS=$save_all_bins" \
            "+ADAPT_ENABLE=$lms_adapt_enable" \
            -l "$log_file" || status=RUN_ERROR

        if [[ "$status" == PASS ]] &&
           ! grep -q '^status=PASS$' "$report_file" 2>/dev/null; then
            status=FAIL
        fi
    fi

    if [[ "$status" != PASS ]]; then
        ((failed += 1))
        printf '[ERRO] %s: %s\n' "$relative_case" "$status" >&2
    fi

    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$relative_case" "$hop_size" "$max_frames" \
        "$lms_adapt_enable" "$lms_mu_shift" "$status" \
        "$bins_csv" "$report_file" >> "$manifest"
done

printf 'SHARED FFT LMS FINALIZADA: casos=%d falhas=%d manifesto=%s\n' \
    "${#selected_cases[@]}" "$failed" "$manifest"
((failed == 0))
