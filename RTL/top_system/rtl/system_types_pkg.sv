`timescale 1ns / 1ps

// ============================================================================
// system_types_pkg -- global constants and bus types for top_system
// ============================================================================
// Single definition point for every constant that used to live as a localparam
// inside top_system.sv, plus the bus types the subsystems exchange.
//
// Deliberately does NOT define Q_FRAC, ACC_WIDTH, N_IN, N_BINS or N_OUT: those
// belong to mlp_weights_pkg, and a module wildcard-importing both packages
// would hit an ambiguous reference. The consistency checks between the two
// live in top_system.sv, where both are already in scope -- keeping them out
// of here also means this package has no compile-order dependency.
//
// Buses are PACKED. Packed arrays cross module ports identically in every
// tool, unlike unpacked arrays, which Quartus Standard handles inconsistently.
// They are declared UNSIGNED on purpose: in `logic signed [N-1:0][W-1:0]` the
// `signed` binds to the whole array and element slices lose it in some tools.
// Read elements through vib_get()/aux_get()/sensor_get(), which restore it.
// ============================================================================
package system_types_pkg;

    // ---- datapath ----------------------------------------------------------
    localparam int DATA_WIDTH = 24;          // Q9.15 sample, == mlp ACC_WIDTH

    // ---- sensor map: word order inside one UART frame ----------------------
    localparam int N_VIB     = 4;            // vibration   -> FFT
    localparam int N_CUR     = 1;            // current     -> MLP aggregate
    localparam int N_TMP     = 2;            // temperature -> MLP aggregates
    localparam int N_SENSORS = N_VIB + N_CUR + N_TMP;   // 7
    localparam int N_AUX     = N_CUR + N_TMP;           // 3

    // Index of the first aux word inside a sensor frame.
    localparam int AUX_BASE  = N_VIB;

    // ---- spectrogram / CNN image ------------------------------------------
    localparam int SPEC_BINS   = 32;         // CNN image width
    localparam int SPEC_FRAMES = 32;         // CNN image height
    localparam int SPEC_WORDS  = SPEC_BINS * SPEC_FRAMES;   // 1024

    // ---- shared FFT --------------------------------------------------------
    localparam int FFT_N     = 64;
    localparam int FFT_BIN_W = 6;            // $clog2(FFT_N)
    localparam int SID_W     = 2;            // $clog2(N_VIB)

    // ---- vibration front-end build options ---------------------------------
    // >>> FRONT_END_NOTE <<<
    // Single definition point for the three choices that set the vibration
    // front end's shape. top_system passes them down to
    // dsp_preprocessing_subsystem, and tb_top_system derives its frame budget
    // from FRAMES_PER_ROUND, so changing them here changes both together.
    //
    // USE_LMS      1 -> preprocess_fft_shared_4sensor_q915_lms (8-tap time-
    //                   domain LMS per channel, the prediction residual is
    //                   what reaches the framer)
    //              0 -> preprocess_fft_shared_4sensor_q915_no_lms
    //
    // DECIM_RATE  32 -> fir_decimator_32_dualmode, 25.6 kHz -> 800 Hz, so a
    //                   64-point FFT resolves 12.5 Hz per bin
    //              1 -> the decimator is bypassed and the FFT sees the raw
    //                   25.6 kHz stream, which is 400 Hz per bin
    //
    // >>> BIN_SPACING_NOTE <<<
    // Bin spacing is fs/(DECIM_RATE*FFT_N). At the live DECIM_RATE = 32 that is
    // 12.5 Hz and the 32 CNN bins cover 0..400 Hz, which is where the
    // diagnostic content lives. Measured end to end, that build classifies at
    // 87.9% against 75.0% for the bypass -- ten of eleven held-out captures
    // exactly right. At DECIM_RATE = 1 the spacing is 400 Hz,
    // so the whole sub-200 Hz diagnostic band -- shaft rotation, its
    // harmonics, the bearing fault frequencies -- lands inside bin 0. The
    // bypass is a build option, not a free one.
    //
    // Everything downstream that thinks in HERTZ now derives its bin indices
    // from DECIM_RATE rather than hardcoding them (see MDC_K_MAX below), and
    // the MLP weights are trained against this exact spacing by
    // Scripts/train_mlp.py. Change DECIM_RATE and you must retrain: the bins
    // move, so the weights no longer mean what they meant.
    localparam bit USE_LMS    = 1'b1;
    localparam int DECIM_RATE = 32;
    localparam int FFT_HOP    = 64;          // sample_buffer hop, 64 = no overlap

    // ---- MDC search band ---------------------------------------------------
    // >>> MDC_BAND_NOTE <<<
    // The peak search that feeds the GCD module is limited to a FREQUENCY
    // band, not a bin count: ~162.5 Hz, which clears the shaft 3x (150 Hz) by
    // one bin and stops below the 168.8 Hz machine line that is not a rotation
    // harmonic and destroys the GCD. Hardcoding the bin index is what let this
    // drift when DECIM_RATE went 64 -> 32; deriving it keeps the two locked.
    // Tenths of a hertz keep the division exact at both rates:
    //   DECIM_RATE 32 -> 12.5 Hz/bin -> 13     DECIM_RATE 64 -> 6.25 -> 26
    // See K_MAX_NOTE in fft_peak_mdc.sv for the measurements behind 162.5 Hz.
    localparam int SAMPLE_RATE_DHZ = 256_000;   // 25.6 kHz in tenths of a hertz
    localparam int MDC_BAND_DHZ    = 1_625;     // 162.5 Hz
    localparam int MDC_K_MAX = (MDC_BAND_DHZ * DECIM_RATE * FFT_N) / SAMPLE_RATE_DHZ;
    localparam int MDC_K_MIN = 2;               // k0 < 2 => no harmonic series
    localparam int MDC_PEAKS = 3;               // the top-3 tracker is unrolled

    // Sensor frames consumed per FFT frame, per channel.
    localparam int FRAMES_PER_ROUND = DECIM_RATE * FFT_HOP;

    // ---- UART link ---------------------------------------------------------
    localparam int BYTES_PER_WORD = DATA_WIDTH / 8;                    // 3
    localparam int FRAME_BYTES    = 2 + N_SENSORS*BYTES_PER_WORD + 1;  // 24

    // ---- element and bus types --------------------------------------------
    typedef logic signed [DATA_WIDTH-1:0] sample_t;

    typedef logic [N_VIB    *DATA_WIDTH-1:0] vib_bus_t;      //  96 bits
    typedef logic [N_AUX    *DATA_WIDTH-1:0] aux_bus_t;      //  72 bits
    typedef logic [N_SENSORS*DATA_WIDTH-1:0] sensor_bus_t;   // 168 bits

    function automatic sample_t vib_get (input vib_bus_t b, input int i);
        return sample_t'(b[i*DATA_WIDTH +: DATA_WIDTH]);
    endfunction

    function automatic sample_t aux_get (input aux_bus_t b, input int i);
        return sample_t'(b[i*DATA_WIDTH +: DATA_WIDTH]);
    endfunction

    function automatic sample_t sensor_get (input sensor_bus_t b, input int i);
        return sample_t'(b[i*DATA_WIDTH +: DATA_WIDTH]);
    endfunction

    // ---- one shared-FFT output beat ---------------------------------------
    // >>> FFT_DONE_NOTE <<<
    // `last` marks bin FFT_N-1 of a sensor and is the ONLY frame-boundary
    // marker allowed to cross a buffer. The FFT core raises its own `done`
    // in S_DONE, two cycles AFTER the final bin transfers and with fft_valid
    // already low (fft_64_dualmode.v:492-506), so `done` rides no beat. Route
    // it around a buffer that is still holding bins and it overtakes them --
    // the MLP collector and the MDC would both close a round whose last bins
    // have not arrived. Consumers regenerate their frame-complete event from
    // an accepted beat carrying `last`.
    localparam int FFT_BEAT_W = SID_W + FFT_BIN_W + 2*DATA_WIDTH + 1;   // 57

    typedef struct packed {
        logic [SID_W-1:0]             sensor_id;
        logic [FFT_BIN_W-1:0]         bin;
        logic signed [DATA_WIDTH-1:0] im;
        logic signed [DATA_WIDTH-1:0] re;    // `real` is a keyword
        logic                         last;  // bin == FFT_N-1
    } fft_beat_t;

    // ---- error status bus --------------------------------------------------
    // One bit per fault source, all sticky, latched at the top level. Replaces
    // the single sticky OR that made SignalTap useless.
    //
    // >>> ERROR_WIDTH_NOTE <<<
    // Specified as [4:0] for the five legacy sources. It is SIX bits here: the
    // CNN frame ping-pong added in cnn_inference_path reports an independent
    // condition of its own, and folding it onto another bit would defeat the
    // point of splitting the flags in the first place. Nothing was removed --
    // bits 0..4 are the original five, bit 5 is the new one.
    //
    // Bits 0..2 mean DATA WAS LOST. Bits 3..5 mean the pipeline misbehaved but
    // kept its data: a desync, an MDC round arriving early, a CNN stall.
    localparam int N_ERR = 6;
    localparam int ERR_UART_FRAME  = 0;   // sync loss / checksum / idle timeout
    localparam int ERR_VIB_OVERRUN = 1;   // ingestion FIFO dropped a sample
    localparam int ERR_MLP_DROP    = 2;   // feature round discarded
    localparam int ERR_SPEC_DESYNC = 3;   // the four spectrograms lost lockstep
    localparam int ERR_MDC_OVERRUN = 4;   // new FFT round before the MDC finished
    localparam int ERR_CNN_STALL   = 5;   // CNN fell 2 frames behind, stalled the FFT

    typedef logic [N_ERR-1:0] error_status_t;

endpackage
