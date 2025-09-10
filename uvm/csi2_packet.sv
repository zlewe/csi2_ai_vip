import uvm_pkg::*;
`include "uvm_macros.svh"

// csi2_packet: UVM sequence item representing a high-level CSI-2 packet transaction.
// This class encapsulates the data that needs to be transmitted over the CSI-2 interface,
// including header, payload, and footer information.
class csi2_packet extends uvm_sequence_item;
    `uvm_object_utils_begin(csi2_packet)
        `uvm_field_int(data_id, UVM_ALL_ATTRIBUTES)
        `uvm_field_int(word_count, UVM_ALL_ATTRIBUTES)
        `uvm_field_array_int(payload_bytes, UVM_ALL_ATTRIBUTES)
        `uvm_field_int(ecc, UVM_ALL_ATTRIBUTES) // Error Correction Code
        `uvm_field_int(crc, UVM_ALL_ATTRIBUTES) // Cyclic Redundancy Check
    `uvm_object_utils_end

    // Packet fields as defined by the CSI-2 specification
    rand byte unsigned data_id;       // Data Type and Virtual Channel ID
    rand int unsigned  word_count;    // Number of bytes in the packet payload
    rand byte unsigned payload_bytes[]; // Array of bytes for the packet payload
    rand byte unsigned ecc;           // Error Correction Code (Header protection)
    rand bit [15:0]    crc;           // Cyclic Redundancy Check (Payload protection)

    // Constraint to ensure payload size matches word_count
    constraint c_word_count {
        word_count inside {[1:65535]}; // Word Count can be up to 65535
        payload_bytes.size() == word_count;
    }

    // Constructor
    function new(string name = "csi2_packet");
        super.new(name);
    endfunction

    // Placeholder function for ECC calculation.
    // In a real VIP, this would implement the specific CSI-2 ECC polynomial.
    function byte unsigned calculate_ecc();
        // For demonstration, a simple XOR sum or a fixed value.
        // A real implementation would involve CRC-8 polynomial calculations on DI and WC.
        byte unsigned temp_ecc = 0;
        temp_ecc ^= data_id;
        temp_ecc ^= word_count[7:0];
        temp_ecc ^= word_count[15:8];
        return temp_ecc; // Simplified placeholder
    endfunction

    // Placeholder function for CRC calculation.
    // In a real VIP, this would implement the specific CSI-2 CRC-16 polynomial.
    function bit [15:0] calculate_crc();
        // For demonstration, a simple XOR sum or a fixed value.
        // A real implementation would involve CRC-16 polynomial calculations on the payload.
        bit [15:0] temp_crc = 0;
        foreach (payload_bytes[i]) begin
            temp_crc ^= payload_bytes[i];
        end
        return temp_crc; // Simplified placeholder
    endfunction

    // Post-randomization hook to calculate ECC and CRC based on other randomized fields.
    function void post_randomize();
        this.ecc = calculate_ecc();
        this.crc = calculate_crc();
    endfunction

endclass
