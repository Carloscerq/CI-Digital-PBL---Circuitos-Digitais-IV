#!/usr/bin/env bash
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=${PROJECT_ROOT:-$(cd "$script_dir/../.." && pwd)}
dataset_q915=${DATASET_Q915:-$project_root/dataset_q915}
dataset_q1116=${DATASET_Q1116:-$project_root/dataset_q1116}
output_dir=${OUTPUT_DIR:-$project_root/results_four_modes}
case_pattern=${CASE_PATTERN:-*}
max_cases=${MAX_CASES:-1}
max_frames=${MAX_FRAMES:-10}
desired_sensor=${DESIRED_SENSOR:-1}
reference_sensor=${REFERENCE_SENSOR:-2}
adapt_samples=${ADAPT_SAMPLES:-0}
mu_shift=${MU_SHIFT:-16}
hop_size=${HOP_SIZE:-8}
input_sample_rate_hz=${INPUT_SAMPLE_RATE_HZ:-25600}
save_all_bins=${SAVE_ALL_BINS:-0}
progress_frames=${PROGRESS_FRAMES:-10}

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

command -v xrun >/dev/null 2>&1 || fail "xrun nao encontrado no PATH."
[[ -d "$dataset_q915" ]] || fail "dataset Q9.15 nao encontrado: $dataset_q915"
[[ -d "$dataset_q1116" ]] || fail "dataset Q11.16 nao encontrado: $dataset_q1116"
[[ "$desired_sensor" =~ ^[1-4]$ ]] || fail "DESIRED_SENSOR deve estar entre 1 e 4."
[[ "$reference_sensor" =~ ^[1-4]$ ]] || fail "REFERENCE_SENSOR deve estar entre 1 e 4."
[[ "$desired_sensor" != "$reference_sensor" ]] || fail "Os sensores devem ser diferentes."
[[ "$hop_size" =~ ^[0-9]+$ ]] && ((hop_size >= 1 && hop_size <= 64)) || \
    fail "HOP_SIZE deve estar entre 1 e 64."

mkdir -p "$output_dir"
cd "$project_root" || fail "nao foi possivel acessar PROJECT_ROOT."

sources=(
    model_sim_four_modes/rtl/preprocessing/fir_coeff_rom_dualmode.v
    model_sim_four_modes/rtl/preprocessing/fir_decimator_stage_dualmode.v
    model_sim_four_modes/rtl/preprocessing/fir_decimator_32_dualmode.v
    model_sim_four_modes/rtl/framing/sample_buffer_64_hop8_dualmode.v
    model_sim_four_modes/rtl/windowing/mean_remover_64_dualmode.v
    model_sim_four_modes/rtl/windowing/hann_window_64_dualmode.v
    model_sim_four_modes/rtl/lms/lms_filter_8tap_dualmode.v
    model_sim_four_modes/rtl/fft/dual_port_ram.v
    model_sim_four_modes/rtl/fft/fft_coeff_rom_64.v
    model_sim_four_modes/rtl/fft/fft_64_dualmode.v
    model_sim_four_modes/rtl/pipeline/preprocess_lms_fft_four_modes.sv
    model_sim_four_modes/verification/tb_fft_lms_dataset.sv
)

for source in "${sources[@]}"; do
    [[ -f "$source" ]] || fail "fonte ausente: $source"
done

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
((${#selected_cases[@]} > 0)) || fail "nenhuma pasta corresponde a CASE_PATTERN=$case_pattern"

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

manifest=$output_dir/four_modes_manifest.csv
printf '%s\n' 'case,mode,data_width,fractional_bits,normalize,use_lms,desired_sensor,reference_sensor,decimation_factor,hop_size,max_frames,status,bins_csv,frames_csv,report' > "$manifest"

modes=(
    'q915_no_lms|24|15|1|0|q915'
    'q915_lms|24|15|1|1|q915'
    'q1116_no_lms|27|16|0|0|q1116'
    'q1116_lms|27|16|0|1|q1116'
)

failed=0
completed=0
for relative_case in "${selected_cases[@]}"; do
    for mode_def in "${modes[@]}"; do
        IFS='|' read -r mode width frac normalize use_lms dataset_kind <<< "$mode_def"
        if [[ "$dataset_kind" == q915 ]]; then
            dataset_root=$dataset_q915
        else
            dataset_root=$dataset_q1116
        fi

        case_dir=$dataset_root/$relative_case
        desired_file=$(find_sensor_file "$case_dir" "$desired_sensor")
        reference_file=$(find_sensor_file "$case_dir" "$reference_sensor")
        mode_output=$output_dir/$relative_case/$mode
        bins_csv=$mode_output/bins.csv
        frames_csv=$mode_output/frames.csv
        report_file=$mode_output/report.txt
        log_file=$mode_output/xrun.log
        build_dir=$mode_output/xcelium.d
        mkdir -p "$mode_output"

        status=PASS
        if [[ -z "$desired_file" || ("$use_lms" == 1 && -z "$reference_file") ]]; then
            status=MISSING_SENSOR
        else
            printf '[XCELIUM] %s -> %s\n' "$relative_case" "$mode"
            xrun -64bit -sv -timescale 1ns/1ps -access +rwc \
                -xmlibdirname "$build_dir" -top tb_fft_lms_dataset \
                -defparam "tb_fft_lms_dataset.DATA_WIDTH=$width" \
                -defparam "tb_fft_lms_dataset.FRAC_BITS=$frac" \
                -defparam "tb_fft_lms_dataset.NORMALIZE=$normalize" \
                -defparam "tb_fft_lms_dataset.USE_LMS=$use_lms" \
                -defparam "tb_fft_lms_dataset.MU_SHIFT=$mu_shift" \
                -defparam "tb_fft_lms_dataset.HOP_SIZE=$hop_size" \
                -defparam "tb_fft_lms_dataset.INPUT_SAMPLE_RATE_HZ=$input_sample_rate_hz" \
                "${sources[@]}" \
                "+MODE_NAME=$mode" \
                "+DESIRED_FILE=$desired_file" \
                "+REFERENCE_FILE=$reference_file" \
                "+OUTPUT_BINS_CSV=$bins_csv" \
                "+OUTPUT_FRAMES_CSV=$frames_csv" \
                "+OUTPUT_REPORT=$report_file" \
                "+MAX_FRAMES=$max_frames" \
                "+ADAPT_SAMPLES=$adapt_samples" \
                "+SAVE_ALL_BINS=$save_all_bins" \
                "+PROGRESS_FRAMES=$progress_frames" \
                -l "$log_file" || status=RUN_ERROR

            if [[ "$status" == PASS ]] &&
               ! grep -q '^status=PASS$' "$report_file" 2>/dev/null; then
                status=FAIL
            fi
        fi

        if [[ "$status" == PASS ]]; then
            ((completed += 1))
        else
            ((failed += 1))
            printf '[ERRO] %s/%s: %s\n' "$relative_case" "$mode" "$status" >&2
        fi
        printf '%s,%s,%s,%s,%s,%s,%s,%s,32,%s,%s,%s,%s,%s,%s\n' \
            "$relative_case" "$mode" "$width" "$frac" "$normalize" \
            "$use_lms" "$desired_sensor" "$reference_sensor" "$hop_size" \
            "$max_frames" "$status" "$bins_csv" "$frames_csv" "$report_file" \
            >> "$manifest"
    done
done

printf 'XCELIUM FINALIZADO: modos=%d, falhas=%d, manifesto=%s\n' \
    "$completed" "$failed" "$manifest"
((failed == 0))
