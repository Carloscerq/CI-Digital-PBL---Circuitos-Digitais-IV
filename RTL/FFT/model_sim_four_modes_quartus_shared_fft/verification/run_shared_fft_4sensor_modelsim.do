# ModelSim/Questa: quatro sensores Q9.15, HOP_SIZE=64 e uma FFT compartilhada.

transcript on
onerror {resume}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set MODEL_ROOT [file normalize [file join $SCRIPT_DIR ..]]
if {![info exists PROJECT_ROOT]} {
    set PROJECT_ROOT [file normalize [file join $MODEL_ROOT ..]]
}
if {![info exists DATASET_Q915]} {
    set DATASET_Q915 [file join $PROJECT_ROOT dataset_q915]
}
if {![info exists OUTPUT_DIR]} {
    set OUTPUT_DIR [file join $MODEL_ROOT results_shared_fft_4sensor]
}
if {![info exists CASE_PATTERN]} {set CASE_PATTERN "*"}
if {![info exists MAX_CASES]} {set MAX_CASES 1}
if {![info exists MAX_FRAMES]} {set MAX_FRAMES 1}
if {![info exists HOP_SIZE]} {set HOP_SIZE 64}
if {![info exists SAVE_ALL_BINS]} {set SAVE_ALL_BINS 0}

set DATASET_Q915 [file normalize $DATASET_Q915]
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

cd $MODEL_ROOT
file mkdir $OUTPUT_DIR

set library work_shared_fft_4sensor
set library_dir [file join $MODEL_ROOT $library]
if {![file isdirectory $library_dir]} {vlib $library_dir}
vmap $library $library_dir

if {[catch {
    vlog -sv +define+RTL_SIM -timescale 1ns/1ps -work $library \
        rtl/preprocessing/fir_coeff_rom_dualmode.v \
        rtl/preprocessing/fir_decimator_stage_dualmode.v \
        rtl/preprocessing/fir_decimator_32_dualmode.v \
        rtl/framing/sample_buffer_64_hop8_dualmode.v \
        rtl/windowing/mean_remover_64_dualmode.v \
        rtl/windowing/hann_window_64_dualmode.v \
        rtl/fft/dual_port_ram.v \
        rtl/fft/fft_coeff_rom_64.v \
        rtl/fft/fft_64_dualmode.v \
        rtl/fft/fft_shared_4sensor.sv \
        rtl/pipeline/preprocess_window_channel_no_lms.sv \
        rtl/pipeline/preprocess_fft_shared_4sensor_q915_no_lms.sv \
        verification/tb_shared_fft_4sensor_dataset.sv
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
    puts stderr "ERRO: nenhum caso corresponde a CASE_PATTERN=$CASE_PATTERN"
    quit -code 1 -f
}
if {$MAX_CASES > 0 && $MAX_CASES < [llength $selected_cases]} {
    set selected_cases [lrange $selected_cases 0 [expr {$MAX_CASES - 1}]]
}

set manifest_path [file join $OUTPUT_DIR shared_fft_4sensor_manifest.csv]
set manifest_fd [open $manifest_path w]
puts $manifest_fd "case,hop_size,max_frames,status,bins_csv,report"

set failed 0
foreach relative_case $selected_cases {
    set case_dir [file join $DATASET_Q915 $relative_case]
    set sensor1_file [find_sensor_file $case_dir 1]
    set sensor2_file [find_sensor_file $case_dir 2]
    set sensor3_file [find_sensor_file $case_dir 3]
    set sensor4_file [find_sensor_file $case_dir 4]
    set case_output [file join $OUTPUT_DIR $relative_case]
    file mkdir $case_output
    set bins_csv [file join $case_output bins.csv]
    set report_file [file join $case_output report.txt]

    if {$sensor1_file eq "" || $sensor2_file eq "" ||
        $sensor3_file eq "" || $sensor4_file eq ""} {
        puts stderr "ERRO: $relative_case nao possui exatamente quatro sensores."
        puts $manifest_fd "$relative_case,$HOP_SIZE,$MAX_FRAMES,MISSING_SENSOR,$bins_csv,$report_file"
        incr failed
        continue
    }

    puts "\n[MODELSIM][SHARED FFT] caso=$relative_case hop=$HOP_SIZE"
    set command [list vsim -quiet -t 1ps \
        -gHOP_SIZE=$HOP_SIZE \
        ${library}.tb_shared_fft_4sensor_dataset \
        +SENSOR1_FILE=[plusarg_path $sensor1_file] \
        +SENSOR2_FILE=[plusarg_path $sensor2_file] \
        +SENSOR3_FILE=[plusarg_path $sensor3_file] \
        +SENSOR4_FILE=[plusarg_path $sensor4_file] \
        +OUTPUT_BINS_CSV=[plusarg_path $bins_csv] \
        +OUTPUT_REPORT=[plusarg_path $report_file] \
        +MAX_FRAMES=$MAX_FRAMES \
        +SAVE_ALL_BINS=$SAVE_ALL_BINS]

    set status PASS
    if {[catch {eval $command} load_error]} {
        puts stderr "ERRO DE ELABORACAO: $load_error"
        set status LOAD_ERROR
    } else {
        onfinish stop
        if {[catch {run -all} run_error]} {
            puts stderr "ERRO DE SIMULACAO: $run_error"
            set status RUN_ERROR
        } elseif {![file exists $report_file]} {
            set status FAIL
        } else {
            set check_fd [open $report_file r]
            set report_text [read $check_fd]
            close $check_fd
            if {[string first "status=PASS" $report_text] < 0}
                set status FAIL
        }
        catch {quit -sim}
    }

    if {$status ne "PASS"} {incr failed}
    puts $manifest_fd "$relative_case,$HOP_SIZE,$MAX_FRAMES,$status,$bins_csv,$report_file"
    flush $manifest_fd
}

close $manifest_fd
puts "\nSHARED FFT FINALIZADA: casos=[llength $selected_cases] falhas=$failed"
puts "Manifest: $manifest_path"
if {$failed != 0} {quit -code 1 -f}
quit -code 0 -f
