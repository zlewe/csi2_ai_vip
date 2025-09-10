import uvm_pkg::*;
`include "uvm_macros.svh"
import csi2_pkg::*;

// Include necessary component definitions (assuming they are in the 'uvm' directory)
`include "csi2_packet.sv"
`include "csi2_config.sv"
`include "csi2_if.sv"

// csi2_driver: UVM driver component for the CSI-2 protocol.
// This driver translates high-level csi2_packet transactions into physical signal
// sequences specific to the configured PHY (D-PHY or C-PHY) on the csi2_if interface.
class csi2_driver extends uvm_driver#(csi2_packet);

    // UVM component utilities macro
    `uvm_component_utils(csi2_driver)

    // Virtual interface handle to connect to the physical interface
    virtual csi2_if.driver_mp vif;

    // Configuration object handle to access environment settings
    csi2_config cfg;

    // Constructor: UVM standard constructor
    function new(string name = "csi2_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // build_phase: Called during the build phase of the UVM testbench.
    // Retrieves the configuration object and the virtual interface from the UVM config_db.
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Get the configuration object
        if (!uvm_config_db#(csi2_config)::get(this, "", "csi2_config", cfg)) begin
            `uvm_fatal(get_full_name(), "Failed to get csi2_config from uvm_config_db. Is it set?")
        end
        // Get the virtual interface
        if (!uvm_config_db#(virtual csi2_if.driver_mp)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_full_name(), "Failed to get virtual interface 'vif' from uvm_config_db. Is it set?")
        end
        `uvm_info(get_full_name(), $sformatf("CSI-2 Driver configured for %s PHY with %0d lanes.", cfg.phy_type.name(), cfg.num_lanes), UVM_HIGH)
    endfunction

    // run_phase: The main task of the driver, responsible for getting transactions
    // from the sequencer and driving them onto the interface.
    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        forever begin
            csi2_packet pkt;
            seq_item_port.get_next_item(pkt); // Get a new transaction from the sequencer
            drive_phy_packet(pkt);           // Drive the transaction onto the physical interface
            seq_item_port.item_done();       // Notify the sequencer that the item is done
        end
    endtask

    // drive_phy_packet: Key task that selects the appropriate PHY-specific driving mechanism.
    // It orchestrates the conversion of the high-level csi2_packet into PHY-specific signals.
    protected task drive_phy_packet(csi2_packet pkt);
        `uvm_info(get_full_name(), $sformatf("Starting to drive CSI-2 packet with PHY type: %s", cfg.phy_type.name()), UVM_LOW)

        // Select the appropriate driving task based on the configured PHY type.
        case (cfg.phy_type)
            CSI2_DPHY: begin
                drive_dphy_packet(pkt);
            end
            CSI2_CPHY: begin
                drive_cphy_packet(pkt);
            end
            default: begin
                `uvm_fatal(get_full_name(), $sformatf("Unsupported PHY type configured: %s", cfg.phy_type.name()))
            end
        endcase

        `uvm_info(get_full_name(), "Finished driving CSI-2 packet.", UVM_LOW)
    endtask

    // drive_dphy_packet: Implements the driving logic for MIPI D-PHY.
    // This task converts the csi2_packet into a D-PHY compliant byte stream,
    // applies lane management elements, and drives it across the data lanes.
    protected task drive_dphy_packet(csi2_packet pkt);
        byte unsigned serialized_data[]; // Array to hold the full serialized byte stream
        int current_byte_idx = 0;
        int num_lanes = cfg.num_lanes;   // Number of active data lanes from configuration

        `uvm_info(get_full_name(), $sformatf("Driving D-PHY packet (Data ID: 0x%0h, Word Count: %0d) with %0d lanes",
                                             pkt.data_id, pkt.word_count, num_lanes), UVM_HIGH)

        // 1. Serialize csi2_packet into a D-PHY byte stream.
        //    Header: Data ID (1 byte), Word Count (2 bytes), ECC (1 byte)
        serialized_data = new[4];
        serialized_data[0] = pkt.data_id;
        serialized_data[1] = pkt.word_count[7:0];  // LSB of Word Count
        serialized_data[2] = pkt.word_count[15:8]; // MSB of Word Count
        serialized_data[3] = pkt.ecc;

        // Append Payload:
        serialized_data = {serialized_data, pkt.payload_bytes};

        // Append Footer: CRC (2 bytes)
        serialized_data = {serialized_data, pkt.crc[7:0], pkt.crc[15:8]};

        `uvm_info(get_full_name(), $sformatf("Serialized %0d bytes for D-PHY transmission.", serialized_data.size()), UVM_DEBUG)

        // Initialize all lanes and clock to Low-Power (LP) mode and disable HS outputs (tristate)
        for (int i=0; i<num_lanes; i++) begin
            vif.hs_data_oe[i]  = 0; // Disable HS data output
            vif.lp_mode_en[i]  = 1; // Assert LP mode for data lane
            vif.lp_data_oe[i]  = 0; // Disable LP data output
            vif.lp_data_out[i] = '0;
        end
        vif.hs_clk_oe      = 0; // Disable HS clock output
        vif.lp_mode_clk_en = 1; // Assert LP mode for clock lane
        vif.lp_clk_oe      = 0; // Disable LP clock output
        vif.lp_clk_out     = '0;
        vif.reset_n_oe     = 0; // Assuming reset is handled externally or through different modport
        vif.reset_n_out    = 1; // Assert reset_n high if driver has control
        @(posedge vif.hs_lane_clk_i); // Synchronize to a clock edge

        // 2. Lane Management Layer (LML): Start of Transmission (SoT) sequence
        //    This involves a specific sequence of LP-mode signalling followed by
        //    transition to HS mode and a HS-mode SoT sequence (e.g., 0x1C, 0xEB).
        //    The actual D-PHY SoT is complex involving LP-11, LP-00, LP-01, LP-10
        //    before transitioning to HS. For this example, we'll simplify.

        `uvm_info(get_full_name(), "Initiating D-PHY HS mode and SoT sequence...", UVM_HIGH)

        // Transition Clock Lane to HS
        vif.lp_mode_clk_en = 0; // Exit LP mode
        vif.hs_clk_oe      = 1; // Enable HS clock output
        vif.hs_clk_out     = 0; // Start with clock low for stabilization
        repeat(2) @(posedge vif.hs_lane_clk_i);
        vif.hs_clk_out     = 1; // Clock goes high
        repeat(2) @(posedge vif.hs_lane_clk_i);
        // Clock is now assumed to be free-running, or generated by the interface.
        // The driver only needs to enable its output.

        // Transition Data Lanes to HS
        for (int i=0; i<num_lanes; i++) begin
            vif.lp_mode_en[i]  = 0; // Exit LP mode for data lanes
            vif.hs_data_oe[i]  = 1; // Enable HS data outputs
            vif.hs_data_out[i] = '0; // Initialize data outputs
        end
        repeat(5) @(posedge vif.hs_lane_clk_i); // Allow time for HS transition

        // Drive a simplified SoT sequence (typically 0x1C, 0xEB on each lane)
        for (int i=0; i<num_lanes; i++) begin
            vif.hs_data_out[i] = 'h1C; // SoT Byte 1
        end
        @(posedge vif.hs_lane_clk_i);
        for (int i=0; i<num_lanes; i++) begin
            vif.hs_data_out[i] = 'hEB; // SoT Byte 2
        end
        @(posedge vif.hs_lane_clk_i);

        // 3. Drive Header, Payload, Footer with Data Striping
        `uvm_info(get_full_name(), "Driving D-PHY data stream...", UVM_HIGH)
        while (current_byte_idx < serialized_data.size()) begin
            for (int lane_idx = 0; lane_idx < num_lanes; lane_idx++) begin
                if (current_byte_idx < serialized_data.size()) begin
                    byte unsigned data_byte = serialized_data[current_byte_idx];
                    // Optional: Error injection based on config
                    if (cfg.error_injection_enabled && $urandom_range(0, 99) < cfg.error_rate) begin
                        data_byte = data_byte ^ 'hFF; // Invert byte to inject a bit error
                        `uvm_warning(get_full_name(), $sformatf("Injected D-PHY data error on lane %0d at byte %0d (original: 0x%0h, sent: 0x%0h)",
                                                                 lane_idx, current_byte_idx, serialized_data[current_byte_idx], data_byte))
                    end
                    vif.hs_data_out[lane_idx] = data_byte;
                    current_byte_idx++;
                end else begin
                    // If not enough data to fill all lanes for the last word,
                    // drive idle value (e.g., 0x00 or leave previous value for a cycle).
                    // This behavior is protocol-dependent; for simplicity, we drive 'h00.
                    vif.hs_data_out[lane_idx] = 'h00;
                end
            end
            // Drive on the rising edge of the high-speed lane clock
            @(posedge vif.hs_lane_clk_i);
        end

        // 4. Lane Management Layer (LML): End of Transmission (EoT) sequence
        `uvm_info(get_full_name(), "Initiating D-PHY EoT sequence...", UVM_HIGH)
        // Simulate EoT sequence (e.g., specific bytes followed by HS to LP transition)
        // A typical D-PHY EoT involves two specific bytes (e.g., 0x01, 0xB8) then LP transition.
        for (int i=0; i<num_lanes; i++) begin
            vif.hs_data_out[i] = 'h01; // EoT Byte 1
        end
        @(posedge vif.hs_lane_clk_i);
        for (int i=0; i<num_lanes; i++) begin
            vif.hs_data_out[i] = 'hB8; // EoT Byte 2
        end
        @(posedge vif.hs_lane_clk_i);

        // 5. Return to LP mode for all lanes
        for (int i=0; i<num_lanes; i++) begin
            vif.hs_data_oe[i] = 0; // Disable HS data outputs
            vif.lp_mode_en[i] = 1; // Enter LP mode for data lanes
            vif.hs_data_out[i] = '0; // Clear HS outputs
        end
        vif.hs_clk_oe      = 0; // Disable HS clock output
        vif.lp_mode_clk_en = 1; // Enter LP mode for clock lane
        vif.hs_clk_out     = '0; // Clear HS clock output
        @(posedge vif.hs_lane_clk_i); // Synchronize
        `uvm_info(get_full_name(), "D-PHY packet driven, returned to LP mode.", UVM_HIGH)
    endtask

    // drive_cphy_packet: Placeholder for MIPI C-PHY specific driving logic.
    // C-PHY involves significantly more complex encoding (e.g., 8b/10b on 3-phase trits)
    // and physical layer interactions compared to D-PHY.
    protected task drive_cphy_packet(csi2_packet pkt);
        `uvm_info(get_full_name(), $sformatf("Driving C-PHY packet (placeholder, as C-PHY is highly complex): %s", pkt.sprint()), UVM_HIGH)
        // C-PHY requires:
        // - Conversion of bytes into trits (3-valued symbols, e.g., A, B, C wires).
        // - Application of 8b/10b encoding (or similar C-PHY specific encoding).
        // - Data striping and lane bonding across the 3-wire physical lanes.
        // - Specific Start of Transmission (SoT) and End of Transmission (EoT) sequences.
        // - Driving these trit sequences onto the virtual interface pins with precise timing.
        // - Support for error injection at the trit or symbol level.

        // A real C-PHY driver would require dedicated C-PHY encoder and detailed
        // physical layer signaling logic. For this generation task, it's a placeholder.
        `uvm_info(get_full_name(), "C-PHY packet driven (functional placeholder only, requires detailed implementation).", UVM_HIGH)
        #100; // Simulate some time for C-PHY transmission (e.g., 100ns)
    endtask

endclass
