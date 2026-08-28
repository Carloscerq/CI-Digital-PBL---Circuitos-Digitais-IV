// ---------------------------------------------------------------------
//  spi_agent  --  sequencer + driver + monitor bundle. Always active (no
//  passive mode), same as perceptron_agent. Both driver.ap (the intent
//  stream) and monitor.ap (the observed stream) are wired to the
//  scoreboard's two independent analysis imps in spi_env.
// ---------------------------------------------------------------------
class spi_agent #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_agent;

    `uvm_component_param_utils(spi_agent #(SIZE, N_SLAVES))

    uvm_sequencer #(spi_seq_item #(SIZE, N_SLAVES)) sequencer;
    spi_driver #(SIZE, N_SLAVES)                    driver;
    spi_monitor #(SIZE, N_SLAVES)                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(spi_seq_item #(SIZE, N_SLAVES))::type_id::create("sequencer", this);
        driver    = spi_driver #(SIZE, N_SLAVES)::type_id::create("driver", this);
        monitor   = spi_monitor #(SIZE, N_SLAVES)::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
