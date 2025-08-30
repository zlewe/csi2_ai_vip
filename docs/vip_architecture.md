# Generate UVM architecture for MIPI-CSI2 VIP

This pull request introduces the foundational UVM (Universal Verification Methodology) architecture for a MIPI-CSI2 VIP. The architecture aims for modularity, reusability, and adherence to UVM best practices, enabling efficient verification of MIPI-CSI2 compliant designs.

The design focuses on a source-side VIP for driving a CSI-2 sink DUT, built with configurable physical layer support (C-PHY or D-PHY), as indicated by the `drive_cphy_packet` (now `drive_phy_packet`) requirement, which will be adapted for the chosen PHY.

## High-Level Architecture Overview

The VIP is structured into standard UVM components (sequence items, driver, monitor, sequencer, agent, scoreboard, environment, test) and complementary non-UVM components (SystemVerilog interface, reference model, and checkers).

```
+-------------------+
|      UVM Test     |
| (csi2_base_test)  |
+---------+---------+
          |
          | Starts Sequences
          V
+-------------------+
|      UVM Env      |
|  (csi2_env)       |
+---------+---------+
          |    +-------------------+
          |    | Reference Model   |
          |    | (csi2_reference_model) |
          |    +---------+---------+
          |              |
          V              | Expected Packets
+-------------------+    |
|    CSI-2 Agent    |<---+
|   (csi2_agent)    |    |
+---------+---------+    |
          |              |
+---------+---------+    |
|   Sequencer       |    |
| (csi2_sequencer)  |    |
+---------+---------+    |
          |              |
          V              |
+---------+---------+    |
|   Driver          |    |
| (csi2_driver)     |    |
+---------+---------+    |
          |              |
          | Drive PHY Signals (uvm/csi2_if.sv)
          V              |
+-------------------+    |
|     DUT           |<---+
| (Design Under Test)|    |
+-------------------+    |
          ^              |
          | Monitor PHY Signals
          |              | Observed Packets
+---------+---------+    |
|   Monitor         |    |
| (csi2_monitor)    |----+
+---------+---------+    |
          |              |
          | Observed Packets (TLM)
          V              |
+-------------------+    |
|    Scoreboard     |<---+
|  (csi2_scoreboard)|
+-------------------+
```

## Detailed Component Descriptions

### UVM Components

#### 1. `csi2_packet` (uvm_sequence_item)
*   **Purpose:** Represents a transaction-level packet, encapsulating CSI-2 Low Level Protocol (LLP) packet information. This is the primary data unit transferred between sequencers, drivers, monitors, and the reference model.
*   **Fields:** Includes fields for Data Type (DT), Word Count (WC), Error Correction Code (ECC - for header), payload (variable length byte array), and Checksum (CRC-16 - for footer).
*   **Attributes:** `is_long_packet`, `is_valid`, `insert_error`, `error_type` for testbench control and error injection.
*   **Methods:** Standard UVM `uvm_object_utils`, `new`, `do_copy`, with placeholders for `do_compare`, `do_print`, `do_pack`/`do_unpack`.
*   **Constraints:** Includes basic constraints for `payload.size()` based on `word_count` and `is_long_packet`.

#### 2. `csi2_driver`
*   **Purpose:** Translates `csi2_packet` transactions received from the sequencer into physical signal sequences specific to the configured PHY (C-PHY or D-PHY) on the `csi2_if` interface.
*   **Key Task:** `drive_phy_packet(csi2_packet pkt)`:
    *   This task will internally select the appropriate PHY-specific driving mechanism based on the configured `phy_type`.
    *   Converts the high-level `csi2_packet` into a stream of bytes/symbols, including serialization of header, payload, and footer, and calculation of ECC/CRC.
    *   Maps the byte stream onto PHY-specific symbols/bits (e.g., C-PHY trits or D-PHY bits), considering the respective PHY's encoding (e.g., CSI-2 8b/10b for C-PHY, or byte/word clock for D-PHY), data striping across lanes, and Lane Management Layer (LML) elements like Start of Transmission (SoT) and End of Transmission (EoT) sequences for the selected PHY.
    *   Drives the PHY-specific signal sequences onto the virtual interface pins with correct timing and tristate logic, supporting error injection.
*   **Connection:** Connects to `virtual csi2_if.driver_mp vif`.

#### 3. `csi2_monitor`
*   **Purpose:** Observes the physical signals on the `csi2_if` interface, specific to the configured PHY, and reconstructs `csi2_packet` transactions.
*   **Key Task:** `monitor_phy_packet(output csi2_packet pkt)`:
    *   This task will internally select the appropriate PHY-specific monitoring mechanism.
    *   Detects PHY-specific activity (e.g., SoT, transition from LP to HS mode) for the configured PHY.
    *   Samples PHY-specific signal sequences, recovers data (e.g., from C-PHY trits or D-PHY bits), and de-maps them into a byte stream (reversing LML aspects like de-scrambling and lane de-striping, according to the selected PHY).
    *   Reconstructs the `csi2_packet` by parsing header, extracting payload, and verifying ECC/CRC for basic protocol checking.
*   **Output:** Sends observed packets via a `uvm_analysis_port#(csi2_packet)` to the scoreboard and reference model.
*   **Connection:** Connects to `virtual csi2_if.monitor_mp vif`.

#### 4. `csi2_sequencer`
*   **Purpose:** Manages the flow of `csi2_packet` transactions from UVM sequences to the `csi2_driver`.
*   **Type:** Standard `uvm_sequencer#(csi2_packet)`.

#### 5. `csi2_agent`
*   **Purpose:** Encapsulates the `csi2_driver`, `csi2_monitor`, and `csi2_sequencer` for a single CSI-2 interface instance.
*   **Configuration:** Configurable via `m_is_active` (`UVM_ACTIVE` or `UVM_PASSIVE`). In `UVM_ACTIVE` mode, it instantiates and connects the driver and sequencer. In `UVM_PASSIVE` mode, only the monitor is instantiated. The agent is also configured with the `phy_type` (C-PHY or D-PHY), which dictates the specific physical layer behavior of its driver and monitor.
*   **Output:** Exposes the monitor's `uvm_analysis_port` for connection to the environment's analysis components.

#### 6. `csi2_scoreboard`
*   **Purpose:** Compares the actual `csi2_packet` transactions observed from the DUT (via the agent's monitor) with the expected `csi2_packet` transactions generated by the reference model.
*   **Mechanism:** Uses two `uvm_tlm_fifo` instances (`dut_fifo`, `ref_fifo`) to buffer packets from the DUT monitor and reference model, respectively. It then retrieves packets from both FIFOs and performs a `compare()` operation.
*   **Reporting:** Logs `UVM_INFO` for matches and `UVM_ERROR` for mismatches.

#### 7. `csi2_reference_model`
*   **Purpose:** Provides a golden functional model of the expected CSI-2 behavior. It takes input packets (e.g., from the monitor, or directly from the test sequence), processes them, and generates expected output packets.
*   **Inputs:** `uvm_analysis_export#(csi2_packet) exp_in_ap_export` to receive input packets.
*   **Outputs:** `uvm_analysis_port#(csi2_packet) exp_out_ap` to send expected packets to the scoreboard.
*   **Functionality:** Includes a `check_packet_integrity` function (placeholder) to perform internal protocol consistency checks on packets. For a CSI-2 VIP driving a sink, this model would likely validate the input packet's structure and content, and potentially "predict" how a compliant sink would process it.

#### 8. `csi2_env`
*   **Purpose:** The top-level UVM environment that orchestrates all major verification components.
*   **Instantiation:** Instantiates the `csi2_agent`, `csi2_scoreboard`, and `csi2_reference_model`.
*   **Connections:** Connects the `csi2_agent.mon_ap` to both `csi2_scoreboard.dut_exp_ap` and `csi2_reference_model.exp_in_ap_export`. It also connects `csi2_reference_model.exp_out_ap` to `csi2_scoreboard.ref_exp_ap`.
*   **Configuration:** Manages configuration settings such as `num_lanes`, `csi2_agent_active`, and crucially, the `phy_type` (e.g., `C_PHY` or `D_PHY` via an enum or string) via `uvm_config_db`.

#### 9. `csi2_base_test`
*   **Purpose:** The base class for all test scenarios. It sets up the `csi2_env` and configures the virtual interface.
*   **Instantiation:** Instantiates `csi2_env_h`.
*   **Configuration:** Retrieves and sets the virtual interface (`vif`) and the `phy_type` for the environment, which then propagates to the agent's driver and monitor using `uvm_config_db`.
*   **Derived Tests:** Specific test cases (e.g., `csi2_test_simple_sequence`) will extend this class and define specific sequences to run during the `run_phase`.

#### 10. `csi2_simple_sequence`
*   **Purpose:** A basic UVM sequence demonstrating how to generate `csi2_packet` items with random data and constraints.
*   **Method:** The `body()` task generates a predefined number of packets (`repeat (5)`), randomizing their fields (`is_long_packet`, `word_count`, `payload.size()`, `data_type`) using `uvm_do_on_with`.

### Non-UVM Components

#### 1. `csi2_if` (SystemVerilog Interface)
*   **Purpose:** Defines the physical connectivity between the VIP and the DUT, supporting both C-PHY and D-PHY layers.
*   **Signals:** Includes `tb_clk` (testbench clock), `reset_n` (asynchronous reset), and PHY-specific lane signals. The exact signals exposed will depend on the `PHY_TYPE` parameter. For C-PHY, this includes `cphy_lane_signals` (a 3-wire signal group for each lane, supporting tristate logic). For D-PHY, this would include `dphy_clk_p/n` and `dphy_data_p/n` pairs for clock and data lanes, respectively, along with other control signals like `lp_mode` and `hs_mode`.
*   **Parameters:** Parameterized by `NUM_LANES` to support different CSI-2 configurations and `PHY_TYPE` (e.g., an enum `typedef enum {C_PHY, D_PHY} csi2_phy_type_e;`) to select between C-PHY and D-PHY specific signal sets and internal logic.
*   **Modports:** Defines `driver_mp`, `monitor_mp`, and `dut_mp` to specify signal directions for different roles, with their internal signal definitions adapting based on `PHY_TYPE`, ensuring clear connectivity rules for the chosen PHY.

#### 2. Reference Model (part of `csi2_reference_model` UVM component)
*   **Purpose:** As described above, it's a behavioral model that provides expected functional results. It's crucial for thorough verification by comparing expected behavior against the DUT's actual behavior. It is a UVM component, but its role extends beyond typical UVM transaction management to functional prediction.

#### 3. Checkers
*   **Purpose:** Verify protocol compliance and data integrity at various points in the VIP.
*   **Location:**
    *   **Monitor:** `csi2_monitor` includes basic checkers during `monitor_phy_packet` to verify ECC and CRC of observed packets and set `pkt.is_valid` accordingly, based on the rules for the configured `phy_type`.
    *   **Reference Model:** `csi2_reference_model` contains `check_packet_integrity` to validate incoming packets and ensure they conform to CSI-2 rules before processing or generating expected outputs.
    *   **Scoreboard:** The `csi2_scoreboard` acts as a primary checker by comparing the entire `csi2_packet` from the DUT against the golden `csi2_packet` from the reference model. Additional custom checkers could be implemented within the scoreboard to perform more in-depth data integrity or functional verification beyond simple packet comparison.

This architecture provides a robust framework for building a comprehensive MIPI-CSI2 VIP, allowing for scalable test development and efficient debugging across both C-PHY and D-PHY implementations.
