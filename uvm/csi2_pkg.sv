`ifndef CSI2_PKG_SV
`define CSI2_PKG_SV

package csi2_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "uvm/csi2_if.sv" // Include the interface definition

  // Define clock period for interface
  `define CLOCK_PERIOD 10ns
  `define RESET_DELAY  100ns

  // Forward declarations (if needed for circular dependencies)
  class csi2_packet;
  class csi2_driver;
  class csi2_monitor;
  class csi2_sequencer;
  class csi2_agent;
  class csi2_scoreboard;
  class csi2_reference_model;
  class csi2_env;
  class csi2_base_test;

  //----------------------------------------------------------------------------
  // csi2_packet (uvm_sequence_item)
  // Represents a high-level MIPI CSI-2 Low-Level Protocol (LLP) packet.
  // This is the transaction level item exchanged between sequencer and driver/monitor.
  //----------------------------------------------------------------------------
  class csi2_packet extends uvm_sequence_item;
    // CSI-2 Packet Header Fields
    rand bit [5:0]  data_type;     // Data Type Identifier (DT)
    rand bit [15:0] word_count;    // Word Count (WC) - for long packets
    rand bit [7:0]  ecc;           // Error Correction Code (ECC) - for header

    // CSI-2 Packet Payload
    rand byte       payload[];     // Raw payload bytes (e.g., pixel data)

    // CSI-2 Packet Footer (only for long packets)
    rand bit [15:0] checksum;      // Checksum (CRC-16)

    // Meta-data / Control fields (not part of the actual CSI-2 protocol, but for testbench control)
    bit             is_long_packet; // Flag: true for long packets, false for short packets
    bit             is_valid;       // Flag: true if packet is well-formed, false for error injection
    bit             insert_error;   // Flag: instruct driver to inject a specific error
    string          error_type;     // Type of error to inject

    `uvm_object_utils_begin(csi2_packet)
      `uvm_field_int(data_type,      UVM_ALL_ON)
      `uvm_field_int(word_count,     UVM_ALL_ON)
      `uvm_field_int(ecc,            UVM_ALL_ON)
      `uvm_field_array_int(payload,  UVM_ALL_ON)
      `uvm_field_int(checksum,       UVM_ALL_ON)
      `uvm_field_int(is_long_packet, UVM_ALL_ON)
      `uvm_field_int(is_valid,       UVM_ALL_ON)
      `uvm_field_int(insert_error,   UVM_ALL_ON)
      `uvm_field_string(error_type,  UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "csi2_packet");
      super.new(name);
    endfunction

    // Constraint examples
    constraint c_payload_size { payload.size() == word_count; }
    constraint c_packet_type {
      if (is_long_packet) {
        word_count >= 1; // Long packets must have payload
      } else {
        word_count == 0; // Short packets have no payload or checksum field
        payload.size() == 0;
      }
    }
    // Add more constraints based on CSI-2 spec (e.g., valid data_type ranges)

    virtual function void do_copy(uvm_object rhs);
      csi2_packet rhs_pkt;
      if (!$cast(rhs_pkt, rhs)) begin
        `uvm_fatal(get_full_name(), "do_copy: bad cast")
      end
      super.do_copy(rhs);
      this.data_type      = rhs_pkt.data_type;
      this.word_count     = rhs_pkt.word_count;
      this.ecc            = rhs_pkt.ecc;
      this.payload        = new[rhs_pkt.payload.size()];
      foreach (rhs_pkt.payload[i]) this.payload[i] = rhs_pkt.payload[i];
      this.checksum       = rhs_pkt.checksum;
      this.is_long_packet = rhs_pkt.is_long_packet;
      this.is_valid       = rhs_pkt.is_valid;
      this.insert_error   = rhs_pkt.insert_error;
      this.error_type     = rhs_pkt.error_type;
    endfunction

    // TODO: Implement do_compare, do_print, do_pack/do_unpack based on CSI-2 requirements
    // For do_compare, compare fields.
    // For do_print, format the packet content nicely.
    // For do_pack/do_unpack, define how to serialize/deserialize the packet for TLM communication if needed.
  endclass


  //----------------------------------------------------------------------------
  // csi2_driver
  // Translates csi2_packet transactions into C-PHY signal level activity.
  //----------------------------------------------------------------------------
  class csi2_driver extends uvm_driver#(csi2_packet);

    // Virtual interface handle to connect to the physical interface
    virtual csi2_if.driver_mp vif;
    int num_lanes = 1;

    `uvm_component_utils_begin(csi2_driver)
      `uvm_field_int(num_lanes, UVM_ALL_ON)
    `uvm_component_utils_end

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual csi2_if.driver_mp)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_full_name(), "Virtual interface 'vif' not set for driver")
      end
      if (!uvm_config_db#(int)::get(this, "", "num_lanes", num_lanes)) begin
        `uvm_warning(get_full_name(), "num_lanes not set, defaulting to 1.")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      super.run_phase(phase);
      forever begin
        csi2_packet pkt;
        // Get the next sequence item from the sequencer
        seq_item_port.get_next_item(pkt);

        `uvm_info(get_full_name(), $sformatf("Driving packet: %s", pkt.sprint()), UVM_HIGH)

        // Drive the packet onto the C-PHY interface
        drive_cphy_packet(pkt);

        // Indicate completion of transaction
        seq_item_port.item_done();
      end
    endtask

    // Virtual task to drive a CSI-2 packet using C-PHY signaling
    virtual task drive_cphy_packet(csi2_packet pkt);
      // Ensure reset is de-asserted
      @(posedge vif.tb_clk iff vif.reset_n);
      `uvm_info(get_full_name(), $sformatf("Starting to drive C-PHY packet with %0d lanes", num_lanes), UVM_LOW)

      // Pseudo-code for C-PHY driving logic:
      // 1. Convert the high-level csi2_packet into a stream of bytes/symbols.
      //    This involves:
      //    - Serializing header, payload, and footer (if long packet)
      //    - Calculating ECC for header, CRC for payload.
      //    - Handling short packet vs. long packet format.
      //
      // 2. Map the byte stream onto C-PHY trits.
      //    - CSI-2 uses 8b/10b encoding for data, which maps to C-PHY trits.
      //    - Data is striped across available lanes.
      //    - Need to manage Lane Management Layer (LML) aspects:
      //      - Start of Transmission (SoT) / End of Transmission (EoT) sequences.
      //      - Data scrambling (if enabled).
      //
      // 3. Drive the C-PHY trit sequences onto the virtual interface pins (vif.cphy_lane_signals).
      //    - Apply correct timing based on C-PHY specifications (e.g., bit periods, lane sync).
      //    - Handle tristate logic for C-PHY wires.
      //    - Insert protocol-specific events (e.g., LP-mode entry/exit, Ultra-Low Power State).
      //    - Incorporate error injection if pkt.insert_error is true.

      // Example: Simplified driving (replace with actual C-PHY signaling)
      for (int i = 0; i < num_lanes; i++) begin
        vif.cphy_lane_signals[i] = 3'b000; // Drive all wires to 0 (example for idle)
      end
      @(posedge vif.tb_clk); // Wait for clock edge

      // Simplified example of driving a "Start of Transmission" (SoT) sequence
      `uvm_info(get_full_name(), "Driving SoT sequence", UVM_DEBUG)
      for (int i = 0; i < num_lanes; i++) begin
         // This is highly simplified. A real SoT involves specific trit sequences.
         vif.cphy_lane_signals[i] = 3'b010; // Example trit for lane i
      end
      repeat(2) @(posedge vif.tb_clk); // SoT typically takes multiple clock cycles

      // Simplified example of driving packet data (header + payload + footer)
      `uvm_info(get_full_name(), "Driving packet data", UVM_DEBUG)
      // In a real scenario, convert pkt.data_type, pkt.word_count, pkt.payload, pkt.checksum
      // into a stream of trits and drive them lane by lane.
      int data_size_bytes = 1; // Placeholder for actual packet size
      if (pkt.is_long_packet) data_size_bytes = 4 + pkt.payload.size() + 2; // Header (4) + Payload + CRC (2)
      else data_size_bytes = 2; // Short packet (Data ID + Word Count, if used as WC)

      for (int byte_idx = 0; byte_idx < data_size_bytes; byte_idx++) begin
        // Example: Map a byte to trits and distribute across lanes
        for (int lane_idx = 0; lane_idx < num_lanes; lane_idx++) begin
          // Placeholder: actual trit encoding and lane striping logic here
          // This would typically involve 8b/10b encoding then C-PHY trit mapping.
          vif.cphy_lane_signals[lane_idx] = $urandom_range(0, 7); // Random trits for demonstration
        end
        repeat(5) @(posedge vif.tb_clk); // Example: each byte takes N trits, N clock cycles
      end

      // Simplified example of driving an "End of Transmission" (EoT) sequence
      `uvm_info(get_full_name(), "Driving EoT sequence", UVM_DEBUG)
      for (int i = 0; i < num_lanes; i++) begin
         vif.cphy_lane_signals[i] = 3'b001; // Example trit for EoT
      end
      repeat(2) @(posedge vif.tb_clk); // EoT typically takes multiple clock cycles

      // Return to idle state
      for (int i = 0; i < num_lanes; i++) begin
        vif.cphy_lane_signals[i] = 3'bZZZ; // C-PHY idle state (High-Z)
      end
      `uvm_info(get_full_name(), "Finished driving C-PHY packet", UVM_LOW)
    endtask

  endclass


  //----------------------------------------------------------------------------
  // csi2_monitor
  // Samples C-PHY signals and reconstructs csi2_packet transactions.
  //----------------------------------------------------------------------------
  class csi2_monitor extends uvm_monitor;

    // Virtual interface handle
    virtual csi2_if.monitor_mp vif;
    int num_lanes = 1;

    // Analysis port to send observed transactions to the scoreboard/reference model
    uvm_analysis_port#(csi2_packet) mon_ap;

    `uvm_component_utils_begin(csi2_monitor)
      `uvm_field_int(num_lanes, UVM_ALL_ON)
    `uvm_component_utils_end

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon_ap = new("mon_ap", this);
      if (!uvm_config_db#(virtual csi2_if.monitor_mp)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_full_name(), "Virtual interface 'vif' not set for monitor")
      end
      if (!uvm_config_db#(int)::get(this, "", "num_lanes", num_lanes)) begin
        `uvm_warning(get_full_name(), "num_lanes not set, defaulting to 1.")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      super.run_phase(phase);
      forever begin
        csi2_packet pkt;
        // Monitor for C-PHY activity and reconstruct packets
        monitor_cphy_packet(pkt);

        if (pkt != null) begin
          `uvm_info(get_full_name(), $sformatf("Monitored packet: %s", pkt.sprint()), UVM_HIGH)
          mon_ap.write(pkt); // Send the observed packet
        end
      end
    endtask

    // Virtual task to monitor C-PHY signals and reconstruct a CSI-2 packet
    virtual task monitor_cphy_packet(output csi2_packet pkt);
      pkt = null; // Initialize to null

      // Ensure reset is de-asserted
      @(posedge vif.tb_clk iff vif.reset_n);
      `uvm_info(get_full_name(), $sformatf("Monitoring C-PHY for packet with %0d lanes", num_lanes), UVM_LOW)

      // Pseudo-code for C-PHY monitoring logic:
      // 1. Detect C-PHY activity (e.g., transition from LP to HS mode, SoT sequence).
      //    This requires state machine logic to track C-PHY protocol states.
      //
      // 2. Sample C-PHY trit sequences from the virtual interface pins (vif.cphy_lane_signals).
      //    - Synchronize to C-PHY clocking (which is embedded in data).
      //    - Recover data from trits.
      //
      // 3. De-map trits into a byte stream.
      //    - Reverse Lane Management Layer (LML) aspects:
      //      - De-scrambling.
      //      - Reconstruct data from across lanes.
      //      - Detect SoT/EoT.
      //
      // 4. Reconstruct the csi2_packet from the byte stream.
      //    - Parse header (DT, WC, ECC).
      //    - Extract payload.
      //    - Verify ECC for header, CRC for payload (basic protocol checking).
      //    - Populate csi2_packet fields.
      //    - Set pkt.is_valid based on CRC/ECC checks.

      // Example: Simplified monitoring (replace with actual C-PHY signaling detection)
      // Wait for C-PHY activity (e.g., transition from idle to SoT)
      fork
        // Timeout in case no activity
        begin
          #(1000 * `CLOCK_PERIOD);
          `uvm_warning(get_full_name(), "Monitor timed out waiting for C-PHY activity.")
          disable fork;
        end
        // Wait for an active signal on any lane (simplified)
        begin
          wait( (vif.cphy_lane_signals[0] != 3'bZZZ) && vif.reset_n );
          `uvm_info(get_full_name(), "Detected C-PHY activity.", UVM_DEBUG)
        end
      join_any
      if (!vif.reset_n) return; // Reset occurred during wait

      pkt = csi2_packet::type_id::create("pkt_mon", this);
      // Dummy values for now
      pkt.data_type = $urandom_range(0, 63);
      pkt.is_long_packet = $urandom_range(0, 1);
      if (pkt.is_long_packet) begin
        pkt.word_count = $urandom_range(1, 100);
        pkt.payload = new[pkt.word_count];
        foreach (pkt.payload[i]) pkt.payload[i] = $urandom();
        pkt.checksum = $urandom_range(0, 16'hFFFF);
      end else begin
        pkt.word_count = 0;
        pkt.payload = new[0];
        pkt.checksum = 0;
      end
      pkt.ecc = $urandom_range(0, 255);
      pkt.is_valid = 1; // Assume valid for now

      // More robust checks could be added here
      // if (calculated_crc != pkt.checksum) pkt.is_valid = 0;
      // if (calculated_ecc != pkt.ecc) pkt.is_valid = 0;

      // Simulate a duration for packet reception
      repeat($urandom_range(50, 200)) @(posedge vif.tb_clk);

      `uvm_info(get_full_name(), "Finished monitoring C-PHY packet", UVM_LOW)
    endtask

  endclass


  //----------------------------------------------------------------------------
  // csi2_sequencer
  // Generates and sends csi2_packet transactions to the driver.
  //----------------------------------------------------------------------------
  class csi2_sequencer extends uvm_sequencer#(csi2_packet);
    `uvm_component_utils(csi2_sequencer)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass


  //----------------------------------------------------------------------------
  // csi2_agent
  // Encapsulates the driver, monitor, and sequencer for a CSI-2 interface.
  // Can be configured as active (driver, sequencer, monitor) or passive (monitor only).
  //----------------------------------------------------------------------------
  class csi2_agent extends uvm_agent;

    csi2_driver    drv;
    csi2_sequencer seq;
    csi2_monitor   mon;

    uvm_analysis_port#(csi2_packet) mon_ap; // Expose monitor's analysis port

    // Configuration field: UVM_ACTIVE or UVM_PASSIVE
    uvm_active m_is_active = UVM_ACTIVE;

    `uvm_component_utils_begin(csi2_agent)
      `uvm_field_enum(uvm_active, m_is_active, UVM_ALL_ON)
    `uvm_component_utils_end

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      mon = csi2_monitor::type_id::create("mon", this);
      mon_ap = mon.mon_ap; // Connect agent's analysis port to monitor's

      if (m_is_active == UVM_ACTIVE) begin
        drv = csi2_driver::type_id::create("drv", this);
        seq = csi2_sequencer::type_id::create("seq", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (m_is_active == UVM_ACTIVE) begin
        drv.seq_item_port.connect(seq.rsp_export);
      end
    endfunction
  endclass


  //----------------------------------------------------------------------------
  // csi2_reference_model
  // Provides expected results for comparison with DUT output.
  // Models the functional behavior of a CSI-2 receiver/transmitter.
  //----------------------------------------------------------------------------
  class csi2_reference_model extends uvm_component;

    // Input analysis export to receive packets from the generator (e.g., sequencer output or agent monitor)
    uvm_analysis_export#(csi2_packet) exp_in_ap_export;

    // Output analysis port to send expected packets to the scoreboard
    uvm_analysis_port#(csi2_packet) exp_out_ap;

    `uvm_component_utils(csi2_reference_model)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      exp_in_ap_export = new("exp_in_ap_export", this);
      exp_out_ap = new("exp_out_ap", this);
    endfunction

    // Implement the write method to process input transactions
    virtual function void write(csi2_packet pkt_in);
      csi2_packet pkt_expected;
      `uvm_info(get_full_name(), $sformatf("Ref Model received input packet: %s", pkt_in.sprint()), UVM_HIGH)

      // Functional modeling logic:
      // - Process the input CSI-2 packet (pkt_in).
      // - If the reference model is for a CSI-2 receiver, it might simply pass the packet through
      //   after checking its internal consistency or performing data processing (e.g., pixel unpacking).
      // - If the reference model is for a CSI-2 transmitter (e.g., for a reverse VIP),
      //   it would generate output packets based on some command/input.
      // - For a passive monitoring scenario, it might just validate the input packet's contents.

      // Example: Simple passthrough and validation
      pkt_expected = csi2_packet::type_id::create("pkt_expected");
      pkt_expected.copy(pkt_in);
      // Perform any expected transformations or validations here
      // Example: calculate expected CRC, decode pixel data, etc.
      pkt_expected.is_valid = check_packet_integrity(pkt_expected);

      `uvm_info(get_full_name(), $sformatf("Ref Model generated expected packet: %s", pkt_expected.sprint()), UVM_HIGH)
      exp_out_ap.write(pkt_expected); // Send the expected packet to the scoreboard
    endfunction

    // Placeholder for actual protocol logic
    protected function bit check_packet_integrity(csi2_packet pkt);
      // Implement CSI-2 protocol checks (e.g., verify ECC, CRC, data type validity)
      `uvm_info(get_full_name(), "Performing reference model packet integrity checks.", UVM_DEBUG)
      // For now, always return true
      return 1;
    endfunction

  endclass


  //----------------------------------------------------------------------------
  // csi2_scoreboard
  // Compares observed transactions from the DUT with expected transactions
  // from the reference model.
  //----------------------------------------------------------------------------
  class csi2_scoreboard extends uvm_scoreboard;

    // Export to receive observed packets from the agent's monitor
    uvm_analysis_export#(csi2_packet) dut_exp_ap;
    // Export to receive expected packets from the reference model
    uvm_analysis_export#(csi2_packet) ref_exp_ap;

    // FIFOs to store transactions for comparison
    uvm_tlm_fifo#(csi2_packet) dut_fifo;
    uvm_tlm_fifo#(csi2_packet) ref_fifo;

    `uvm_component_utils(csi2_scoreboard)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dut_fifo = new("dut_fifo", this);
      ref_fifo = new("ref_fifo", this);
      dut_exp_ap = new("dut_exp_ap", this);
      ref_exp_ap = new("ref_exp_ap", this);

      // Connect exports to FIFOs
      dut_exp_ap.connect(dut_fifo.analysis_export);
      ref_exp_ap.connect(ref_fifo.analysis_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
      csi2_packet dut_pkt, ref_pkt;
      super.run_phase(phase);
      forever begin
        // Wait for a transaction from both the DUT and the Reference Model
        dut_fifo.get(dut_pkt);
        ref_fifo.get(ref_pkt);

        `uvm_info(get_full_name(), "Comparing DUT and Reference Model packets...", UVM_LOW)

        // Perform comparison
        if (dut_pkt.compare(ref_pkt)) begin
          `uvm_info(get_full_name(), $sformatf("PACKET MATCH!\nDUT:\n%s\nREF:\n%s",
                                                dut_pkt.sprint(), ref_pkt.sprint()), UVM_HIGH)
        end else begin
          `uvm_error(get_full_name(), $sformatf("PACKET MISMATCH!\nDUT:\n%s\nREF:\n%s",
                                                 dut_pkt.sprint(), ref_pkt.sprint()))
        end
      end
    endtask

  endclass


  //----------------------------------------------------------------------------
  // csi2_env
  // Top-level UVM environment that instantiates and connects all components.
  //----------------------------------------------------------------------------
  class csi2_env extends uvm_env;

    csi2_agent           csi2_ag;
    csi2_scoreboard      scb;
    csi2_reference_model ref_model;

    // Configuration for the environment (e.g., number of lanes)
    int num_lanes = 1;
    uvm_active csi2_agent_active = UVM_ACTIVE;

    `uvm_component_utils_begin(csi2_env)
      `uvm_field_int(num_lanes, UVM_ALL_ON)
      `uvm_field_enum(uvm_active, csi2_agent_active, UVM_ALL_ON)
    `uvm_component_utils_end

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      csi2_ag   = csi2_agent::type_id::create("csi2_ag", this);
      scb       = csi2_scoreboard::type_id::create("scb", this);
      ref_model = csi2_reference_model::type_id::create("ref_model", this);

      // Set configuration for agent (e.g., active/passive, number of lanes)
      uvm_config_db#(uvm_active)::set(this, "csi2_ag", "m_is_active", csi2_agent_active);
      uvm_config_db#(int)::set(this, "csi2_ag.mon", "num_lanes", num_lanes);
      uvm_config_db#(int)::set(this, "csi2_ag.drv", "num_lanes", num_lanes);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      // Connect agent's monitor to scoreboard and reference model
      csi2_ag.mon_ap.connect(scb.dut_exp_ap);
      csi2_ag.mon_ap.connect(ref_model.exp_in_ap_export); // Monitor output to Ref Model input

      // Connect reference model's output to scoreboard
      ref_model.exp_out_ap.connect(scb.ref_exp_ap);
    endfunction
  endclass


  //----------------------------------------------------------------------------
  // csi2_base_test
  // Base UVM test class.
  //----------------------------------------------------------------------------
  class csi2_base_test extends uvm_test;

    csi2_env csi2_env_h;
    // Virtual interface handle for top-level connection
    virtual csi2_if vif;

    `uvm_component_utils(csi2_base_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      csi2_env_h = csi2_env::type_id::create("csi2_env_h", this);

      // Get virtual interface from config_db and set for agent's driver/monitor
      if (!uvm_config_db#(virtual csi2_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_full_name(), "Virtual interface 'vif' not set for test")
      end
      uvm_config_db#(virtual csi2_if.driver_mp)::set(this, "csi2_env_h.csi2_ag.drv", "vif", vif.driver_mp);
      uvm_config_db#(virtual csi2_if.monitor_mp)::set(this, "csi2_env_h.csi2_ag.mon", "vif", vif.monitor_mp);

      // Example: Set number of lanes via config_db
      uvm_config_db#(int)::set(this, "csi2_env_h", "num_lanes", 1); // Or get from test params
      uvm_config_db#(uvm_active)::set(this, "csi2_env_h.csi2_ag", "m_is_active", UVM_ACTIVE);
    endfunction

    virtual task run_phase(uvm_phase phase);
      // Default: do nothing, derived tests will start sequences
      phase.raise_objection(this, "Base Test executing");
      #100ns; // Simulate some time
      phase.drop_objection(this, "Base Test finished");
    endtask
  endclass

  //----------------------------------------------------------------------------
  // Simple Sequence for demonstration
  //----------------------------------------------------------------------------
  class csi2_simple_sequence extends uvm_sequence#(csi2_packet);

    `uvm_object_utils(csi2_simple_sequence)

    function new(string name = "csi2_simple_sequence");
      super.new(name);
    endfunction

    virtual task body();
      csi2_packet pkt;
      repeat (5) begin // Generate 5 packets
        `uvm_do_on_with(pkt, p_sequencer, {
          pkt.is_long_packet == $urandom_range(0,1);
          if (pkt.is_long_packet) {
            pkt.word_count inside {[1:10]};
            pkt.payload.size() == pkt.word_count;
          } else {
            pkt.word_count == 0;
            pkt.payload.size() == 0;
          }
          pkt.data_type inside {[10:20]}; // Example data types
        })
      end
    endtask
  endclass

  //----------------------------------------------------------------------------
  // Derived Test with a simple sequence
  //----------------------------------------------------------------------------
  class csi2_test_simple_sequence extends csi2_base_test;

    `uvm_component_utils(csi2_test_simple_sequence)

    function new(string name = "csi2_test_simple_sequence", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
      csi2_simple_sequence seq_h;
      phase.raise_objection(this, "Starting simple sequence");
      seq_h = csi2_simple_sequence::type_id::create("seq_h");
      seq_h.start(csi2_env_h.csi2_ag.seq);
      // Wait for all packets to be processed (e.g., using a global event or checking FIFOs)
      // For simplicity, just wait for a fixed time after sequence finishes.
      #(`CLOCK_PERIOD * 500);
      phase.drop_objection(this, "Simple sequence finished");
    endtask
  endclass

endpackage

`endif // CSI2_PKG_SV
