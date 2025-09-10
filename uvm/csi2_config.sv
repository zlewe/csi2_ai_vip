import uvm_pkg::*;
`include "uvm_macros.svh"
import csi2_pkg::*;

// csi2_config: Configuration object for the CSI-2 VIP environment
// This object holds parameters that define the behavior of various components,
// such as the selected PHY type, number of lanes, and error injection settings.
class csi2_config extends uvm_object;
    `uvm_object_utils(csi2_config)

    // Configuration parameters
    csi2_phy_type_e phy_type = CSI2_DPHY; // Default PHY type is D-PHY
    int             num_lanes = 4;        // Number of active data lanes (1 to 4 for D-PHY)
    bit             error_injection_enabled = 0; // Enable/disable error injection
    int             error_rate = 10;      // Error rate percentage (e.g., 10 for 10%)

    // Constructor
    function new(string name = "csi2_config");
        super.new(name);
    endfunction

    // Function to print current configuration settings for debugging
    function void print_config();
        `uvm_info(get_full_name(), $sformatf("CSI-2 Configuration: PHY Type=%s, Num Lanes=%0d, Error Injection Enabled=%0b, Error Rate=%0d%%",
                                             phy_type.name(), num_lanes, error_injection_enabled, error_rate), UVM_LOW)
    endfunction

endclass
