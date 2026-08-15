# =============================================================================
# Executa, para a mesma pasta e o mesmo sensor principal, quatro conjuntos:
#   q915_no_lms, q915_lms, q1116_no_lms, q1116_lms
# =============================================================================

transcript on
onerror {resume}

# Usa primeiro as variaveis de ambiente (PowerShell, CMD ou shell). Se uma
# variavel nao foi fornecida, preserva uma variavel Tcl existente; caso
# contrario, aplica o valor padrao.
proc apply_env_or_default {name default_value} {
    upvar #0 $name target

    if {[info exists ::env($name)] && $::env($name) ne ""} {
        set target $::env($name)
    } elseif {![info exists target]} {
        set target $default_value
    }
}

apply_env_or_default PROJECT_ROOT [file normalize [pwd]]
apply_env_or_default DATASET_Q915 [file join $PROJECT_ROOT dataset_q915]
apply_env_or_default DATASET_Q1116 [file join $PROJECT_ROOT dataset_q1116]
apply_env_or_default OUTPUT_DIR [file join $PROJECT_ROOT results_four_modes]
apply_env_or_default CASE_PATTERN "*"
apply_env_or_default MODE_PATTERN "*"
apply_env_or_default MAX_CASES 1
apply_env_or_default MAX_FRAMES 10
apply_env_or_default DESIRED_SENSOR 1
apply_env_or_default REFERENCE_SENSOR 2
apply_env_or_default ADAPT_SAMPLES 0
apply_env_or_default MU_SHIFT 16
apply_env_or_default HOP_SIZE 8
apply_env_or_default INPUT_SAMPLE_RATE_HZ 25600
apply_env_or_default SAVE_ALL_BINS 0
apply_env_or_default PROGRESS_FRAMES 10

set PROJECT_ROOT [file normalize $PROJECT_ROOT]
set DATASET_Q915 [file normalize $DATASET_Q915]
set DATASET_Q1116 [file normalize $DATASET_Q1116]
set OUTPUT_DIR [file normalize $OUTPUT_DIR]

proc plusarg_path {value} {
    return [string map {\\ /} [file normalize $value]]
}

proc relative_to {base_path target_path} {
    set base_parts [file split [file normalize $base_path]]
    set target_parts [file split [file normalize $target_path]]
    set index 0
    set common [expr {min([llength $base_parts], [llength $target_parts])}]
    while {$index < $common &&
           [string equal -nocase [lindex $base_parts $index] \
                                 [lindex $target_parts $index]]} {
        incr index
    }
    if {$index != [llength $base_parts]} {
        error "$target_path nao esta dentro de $base_path"
    }
    set remaining [lrange $target_parts $index end]
    if {[llength $remaining] == 0} {return "."}
    return [eval file join $remaining]
}

proc collect_case_dirs {directory} {
    set mem_found 0
    set subdirs {}
    foreach item [lsort [glob -nocomplain -directory $directory *]] {
        if {[file isdirectory $item]} {
            lappend subdirs $item
        } elseif {[file isfile $item] &&
                  [string equal -nocase [file extension $item] ".mem"]} {
            set mem_found 1
        }
    }
    if {$mem_found} {return [list [file normalize $directory]]}
    set result {}
    foreach subdir $subdirs {
        set result [concat $result [collect_case_dirs $subdir]]
    }
    return $result
}

proc find_sensor_file {case_dir sensor} {
    set matches {}
    set pattern [format {_sensor%d$} $sensor]
    foreach item [lsort [glob -nocomplain -directory $case_dir *.mem]] {
        if {[regexp -nocase -- $pattern [file rootname [file tail $item]]]} {
            lappend matches [file normalize $item]
        }
    }
    if {[llength $matches] != 1} {return ""}
    return [lindex $matches 0]
}

if {![file isdirectory $DATASET_Q915]} {
    puts stderr "ERRO: dataset Q9.15 nao encontrado: $DATASET_Q915"
    quit -code 1 -f
}
if {![file isdirectory $DATASET_Q1116]} {
    puts stderr "ERRO: dataset Q11.16 nao encontrado: $DATASET_Q1116"
    quit -code 1 -f
}
if {$DESIRED_SENSOR < 1 || $DESIRED_SENSOR > 4 ||
    $REFERENCE_SENSOR < 1 || $REFERENCE_SENSOR > 4} {
    puts stderr "ERRO: DESIRED_SENSOR e REFERENCE_SENSOR devem estar entre 1 e 4."
    quit -code 1 -f
}
if {$DESIRED_SENSOR == $REFERENCE_SENSOR} {
    puts stderr "ERRO: sensor principal e referencia devem ser diferentes."
    quit -code 1 -f
}

cd $PROJECT_ROOT
file mkdir $OUTPUT_DIR

set library work_four_modes
if {![file isdirectory $library]} {vlib $library}
vmap $library $library

puts "\n============================================================"
puts "COMPILACAO DOS QUATRO MODOS"
puts "Raiz       : $PROJECT_ROOT"
puts "Q9.15      : $DATASET_Q915"
puts "Q11.16     : $DATASET_Q1116"
puts "Saida      : $OUTPUT_DIR"
puts "Modo       : $MODE_PATTERN"
puts "Caso       : $CASE_PATTERN"
puts "Sensor     : $DESIRED_SENSOR"
puts "Referencia : $REFERENCE_SENSOR"
puts "Hop        : $HOP_SIZE"
puts "Max frames : $MAX_FRAMES"
puts "============================================================"

if {[catch {
    vlog -sv -timescale 1ns/1ps -work $library \
        model_sim_four_modes/rtl/preprocessing/fir_coeff_rom_dualmode.v \
        model_sim_four_modes/rtl/preprocessing/fir_decimator_stage_dualmode.v \
        model_sim_four_modes/rtl/preprocessing/fir_decimator_32_dualmode.v \
        model_sim_four_modes/rtl/framing/sample_buffer_64_hop8_dualmode.v \
        model_sim_four_modes/rtl/windowing/mean_remover_64_dualmode.v \
        model_sim_four_modes/rtl/windowing/hann_window_64_dualmode.v \
        model_sim_four_modes/rtl/lms/lms_filter_8tap_dualmode.v \
        model_sim_four_modes/rtl/fft/dual_port_ram.v \
        model_sim_four_modes/rtl/fft/fft_coeff_rom_64.v \
        model_sim_four_modes/rtl/fft/fft_64_dualmode.v \
        model_sim_four_modes/rtl/pipeline/preprocess_lms_fft_four_modes.sv \
        model_sim_four_modes/verification/tb_fft_lms_dataset.sv
} compile_error]} {
    puts stderr "ERRO DE COMPILACAO: $compile_error"
    quit -code 1 -f
}

set selected_cases {}
foreach case_dir [collect_case_dirs $DATASET_Q915] {
    set relative_case [relative_to $DATASET_Q915 $case_dir]
    if {[string match -nocase $CASE_PATTERN $relative_case] ||
        [string match -nocase $CASE_PATTERN [file tail $case_dir]]} {
        lappend selected_cases $relative_case
    }
}

if {[llength $selected_cases] == 0} {
    puts stderr "ERRO: nenhuma pasta corresponde a CASE_PATTERN=$CASE_PATTERN"
    quit -code 1 -f
}
if {$MAX_CASES > 0 && $MAX_CASES < [llength $selected_cases]} {
    set selected_cases [lrange $selected_cases 0 [expr {$MAX_CASES - 1}]]
}

# nome, largura, fracionarios, normaliza, usa_lms, dataset
set mode_table [list \
    [list q915_no_lms  24 15 1 0 $DATASET_Q915] \
    [list q915_lms     24 15 1 1 $DATASET_Q915] \
    [list q1116_no_lms 27 16 0 0 $DATASET_Q1116] \
    [list q1116_lms    27 16 0 1 $DATASET_Q1116]]

set manifest_path [file join \
    $OUTPUT_DIR four_modes_manifest_sensor${DESIRED_SENSOR}.csv]
set manifest_fd [open $manifest_path w]
puts $manifest_fd "case,mode,data_width,fractional_bits,normalize,use_lms,desired_sensor,reference_sensor,decimation_factor,hop_size,max_frames,status,bins_csv,frames_csv,report"

set failed 0
set completed 0
foreach relative_case $selected_cases {
    puts "\n############################################################"
    puts "CASO: $relative_case"
    puts "Sensor principal: $DESIRED_SENSOR | referencia LMS: $REFERENCE_SENSOR"
    puts "############################################################"

    foreach mode_def $mode_table {
        lassign $mode_def mode width frac normalize use_lms dataset_root

        if {![string match -nocase $MODE_PATTERN $mode]} {
            continue
        }

        set case_dir [file join $dataset_root $relative_case]
        set desired_file [find_sensor_file $case_dir $DESIRED_SENSOR]
        set reference_file [find_sensor_file $case_dir $REFERENCE_SENSOR]
        set mode_output [file join \
            $OUTPUT_DIR $relative_case sensor${DESIRED_SENSOR} $mode]
        file mkdir $mode_output
        set bins_csv [file join $mode_output bins.csv]
        set frames_csv [file join $mode_output frames.csv]
        set report_file [file join $mode_output report.txt]

        if {$desired_file eq "" || ($use_lms && $reference_file eq "")} {
            puts stderr "\[ERRO\] $relative_case/$mode: sensor ausente ou duplicado."
            puts $manifest_fd "$relative_case,$mode,$width,$frac,$normalize,$use_lms,$DESIRED_SENSOR,$REFERENCE_SENSOR,32,$HOP_SIZE,$MAX_FRAMES,MISSING_SENSOR,$bins_csv,$frames_csv,$report_file"
            flush $manifest_fd
            incr failed
            continue
        }

        puts "\n\[MODELSIM\] $relative_case -> $mode"
        set command [list vsim -quiet -t 1ps \
            -gDATA_WIDTH=$width \
            -gFRAC_BITS=$frac \
            -gNORMALIZE=$normalize \
            -gUSE_LMS=$use_lms \
            -gMU_SHIFT=$MU_SHIFT \
            -gHOP_SIZE=$HOP_SIZE \
            -gINPUT_SAMPLE_RATE_HZ=$INPUT_SAMPLE_RATE_HZ \
            ${library}.tb_fft_lms_dataset \
            +MODE_NAME=$mode \
            +DESIRED_FILE=[plusarg_path $desired_file] \
            +REFERENCE_FILE=[plusarg_path $reference_file] \
            +OUTPUT_BINS_CSV=[plusarg_path $bins_csv] \
            +OUTPUT_FRAMES_CSV=[plusarg_path $frames_csv] \
            +OUTPUT_REPORT=[plusarg_path $report_file] \
            +MAX_FRAMES=$MAX_FRAMES \
            +ADAPT_SAMPLES=$ADAPT_SAMPLES \
            +SAVE_ALL_BINS=$SAVE_ALL_BINS \
            +PROGRESS_FRAMES=$PROGRESS_FRAMES]

        set status PASS
        if {[catch {eval $command} load_error]} {
            puts stderr "\[ERRO\] Falha de elaboracao em $mode: $load_error"
            set status LOAD_ERROR
        } else {
            onfinish stop
            if {[catch {run -all} run_error]} {
                puts stderr "\[ERRO\] Falha de simulacao em $mode: $run_error"
                set status RUN_ERROR
           } elseif {![file exists $report_file]} {
            puts stderr "\[ERRO\] $mode nao gerou report.txt."
            set status FAIL
        } else {
            set check_fd [open $report_file r]
            set report_text [read $check_fd]
            close $check_fd

            if {[string first "status=PASS" $report_text] < 0} {
                puts stderr "\[ERRO\] $mode nao registrou status=PASS."
                set status FAIL
            }
        }
            catch {quit -sim}
        }

        if {$status eq "PASS"} {
            incr completed
            puts "\[OK\] $mode concluido: $report_file"
        } else {
            incr failed
        }
        puts $manifest_fd "$relative_case,$mode,$width,$frac,$normalize,$use_lms,$DESIRED_SENSOR,$REFERENCE_SENSOR,32,$HOP_SIZE,$MAX_FRAMES,$status,$bins_csv,$frames_csv,$report_file"
        flush $manifest_fd
    }
}

close $manifest_fd
puts "\n============================================================"
puts "QUATRO MODOS FINALIZADOS"
puts "Casos selecionados : [llength $selected_cases]"
puts "Modos concluidos   : $completed"
puts "Falhas             : $failed"
puts "Manifesto          : $manifest_path"
puts "============================================================"

if {$failed != 0} {quit -code 1 -f}
quit -code 0 -f
