//----------------------------------------------------------------------------
//  uvm_dpi_verilator.cc  --  UVM 1.2 DPI layer, minus the HDL backdoor.
//
//  UVM ships src/dpi/uvm_dpi.cc, which pulls in uvm_hdl.c. That file only has
//  vendor backends for VCS, Questa (mti.h) and Xcelium, and #errors out with
//  "hdl vendor backend is missing" on anything else -- Verilator included.
//
//  uvm_hdl is only used by uvm_reg's backdoor access (peek/poke straight into
//  the DUT hierarchy). None of the benches in this repo use uvm_reg, so we
//  compile the other three DPI files and drop uvm_hdl.c. uvm_verilator.sh
//  pairs this with +define+UVM_HDL_NO_DPI, which makes the SystemVerilog side
//  (uvm_hdl.svh) stop importing those functions and instead report an error if
//  anything ever calls them -- so the omission can never fail silently.
//
//  Compile with -I<uvm>/src/dpi. Everything else (uvm_regex, the command line
//  processor's uvm_svcmd_dpi, uvm_common) is stock UVM source.
//----------------------------------------------------------------------------

#ifdef __cplusplus
extern "C" {
#endif

#include <stdlib.h>
#include "uvm_dpi.h"
#include "uvm_common.c"
#include "uvm_regex.cc"
#include "uvm_svcmd_dpi.c"

#ifdef __cplusplus
}
#endif
