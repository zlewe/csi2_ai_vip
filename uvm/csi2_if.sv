`ifndef CSI2_IF_SV
`define CSI2_IF_SV

// MIPI CSI-2 C-PHY Interface
// This interface models the raw C-PHY signals for a given number of lanes.
// C-PHY uses 3 wires per lane (e.g., A, B, C), each capable of tristate (0, 1, Z).
// The combination of these 3 wires forms a 'trit' (ternary digit).
// For simplification at the architectural level, we represent the 3 wires as a `logic [2:0]`.
interface csi2_if #(int NUM_LANES = 1);

  // SystemVerilog clock for UVM components.
  // C-PHY has its own internal clocking and data recovery mechanisms.
  // This `tb_clk` is a reference clock for the testbench logic.
  logic tb_clk;

  // Global asynchronous reset
  logic reset_n;

  // C-PHY lane signals:
  // cphy_lane_signals[LANE_IDX][WIRE_IDX]
  // LANE_IDX: 0 to NUM_LANES-1
  // WIRE_IDX: 0 (wire A), 1 (wire B), 2 (wire C)
  // Each wire is tri-state (logic data type supports 0, 1, X, Z).
  tri logic [NUM_LANES-1:0][2:0] cphy_lane_signals;

  // Define modports for different roles
  // Driver: Drives the C-PHY signals and reset
  modport driver_mp (
    output cphy_lane_signals,
    output reset_n,
    input  tb_clk
  );

  // Monitor: Observes the C-PHY signals and reset
  modport monitor_mp (
    input  cphy_lane_signals,
    input  reset_n,
    input  tb_clk
  );

  // DUT: Connected to the C-PHY signals
  // The direction of signals from DUT perspective depends on whether DUT is source or sink.
  // Assuming DUT is a CSI-2 sink for this VIP (VIP is source/driver).
  modport dut_mp (
    input  cphy_lane_signals,
    input  reset_n,
    input  tb_clk // DUT consumes tb_clk for internal logic
  );

  // Initial block for clock generation
  initial begin
    tb_clk = 0;
    forever #(`CLOCK_PERIOD / 2) tb_clk = ~tb_clk;
  end

  // Initial block for reset generation
  initial begin
    reset_n = 0;
    #(`RESET_DELAY);
    reset_n = 1;
  end

endinterface

`endif // CSI2_IF_SV
