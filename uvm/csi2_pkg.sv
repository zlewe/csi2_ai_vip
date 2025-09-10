package csi2_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Enumeration for PHY types
  typedef enum {
    CSI2_DPHY, // D-PHY (typically used for MIPI DSI/CSI-2)
    CSI2_CPHY  // C-PHY (newer PHY for MIPI DSI/CSI-2)
  } csi2_phy_type_e;

endpackage
