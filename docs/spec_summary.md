# MIPI CSI-2 v4.0 Specification Summary: Overview and Core Concepts

## 1. Introduction to MIPI CSI-2

The MIPI Camera Serial Interface 2 (CSI-2) is a high-speed, low-power, serial interface primarily designed for connecting image sensors and cameras to host processors in mobile, automotive, and other embedded systems. Developed by the MIPI Alliance, CSI-2 offers a robust and flexible solution for various imaging applications, supporting a wide range of resolutions, frame rates, and color depths. Its packet-based communication protocol ensures efficient and reliable data transfer.

## 2. Key Features and Advantages

*   **High Bandwidth:** Supports high-resolution and high-frame-rate video streams by utilizing MIPI D-PHY or C-PHY for high-speed differential signaling, configurable with multiple data lanes/trios.
*   **Low Power Consumption:** Optimized for battery-powered devices through efficient PHY designs (e.g., D-PHY's Low-Power (LP) mode) and streamlined protocol.
*   **Packet-Based Communication:** Data is transmitted in distinct packets (Short and Long), enabling efficient handling of different data types including image pixel data, embedded metadata, and control information.
*   **Flexible Data Types:** Supports a broad spectrum of image data formats, including various YUV, RGB, RAW, and user-defined formats, allowing for diverse camera sensor outputs.
*   **Embedded Data Support:** Facilitates the transmission of ancillary data (e.g., sensor settings, timestamps, gain information) alongside or within image frames.
*   **Error Detection and Correction:** Incorporates mechanisms such as Error Correction Code (ECC) for Short Packets and Cyclic Redundancy Check (CRC) for Long Packets to ensure data integrity.
*   **Scalability:** The interface is scalable, supporting 1 to 4 data lanes for D-PHY or up to 3 trios for C-PHY, to match bandwidth requirements.
*   **Compatibility:** Designed to work seamlessly with MIPI D-PHY v1.2 and C-PHY v1.1 or later.

## 3. CSI-2 Protocol Layers

CSI-2 defines a layered architecture to manage data transfer, abstracting the physical transmission from the application processing:

*   **Physical Layer (PHY):** This is the lowest layer, defining the electrical characteristics and timing for data transmission. MIPI CSI-2 can operate over two distinct PHYs:
    *   **MIPI D-PHY:** A source-synchronous, point-to-point interface. It employs differential signaling for high-speed (HS) data transfer and single-ended signaling for low-power (LP) mode. It includes dedicated data lanes and a clock lane.
    *   **MIPI C-PHY:** A three-phase, 3-wire system that encodes 3 bits per symbol. It achieves high bandwidth efficiency without requiring a dedicated clock lane and is particularly suited for high-resolution cameras.
*   **Low-Level Protocol (LLP):** This layer handles the packetization of data. It defines the structure of Short Packets and Long Packets, including packet headers, data payloads, and footers (e.g., CRC). It also manages synchronization events such as Start-of-Frame (SoF), End-of-Frame (EoF), Start-of-Line (SoL), and End-of-Line (EoL).
*   **Pixel/Byte to Lane Mapper (BLL):** This layer (also sometimes referred to as the Byte/Line Link) is responsible for distributing the incoming byte stream from the application layer across the available D-PHY/C-PHY data lanes. At the receiver, it reconstructs the original byte stream from the multiple lanes, ensuring proper data ordering.
*   **Application Layer:** The highest layer, responsible for interpreting the received data packets and converting them into image frames or other application-specific data. This layer typically handles image reconstruction, format conversion, and provides the interface to the host processor or image signal processor (ISP).

## 4. Data Types and Packet Structure

CSI-2 utilizes two fundamental packet types to convey information:

*   **Short Packets:** These are compact packets used for various control signals, embedded data, and synchronization events.
    *   **Structure:** They consist of a 2-byte Data Type (DT), 2-byte Data (DA), and a 2-byte Error Correction Code (ECC).
    *   **Usage:** Examples include Frame Start/End, Line Start/End, various Generic Short Packet data, and control commands.
*   **Long Packets:** Primarily used for transmitting image pixel data and other longer data streams.
    *   **Structure:** They consist of a 2-byte Data Type (DT), a 2-byte Word Count (WC) indicating the number of bytes in the payload, a 2-byte ECC, the actual Data Payload, and a 2-byte Checksum (CRC) for the payload.
    *   **Usage:** Carries pixel data for various image formats (RAW, YUV, RGB), or other large blocks of data.

CSI-2 defines a wide range of **Data Types** (specified by the DT field) to indicate the content of the packet. These include:
*   **Generic 8-bit Data Types:** For general-purpose 8-bit data.
*   **YUV Formats:** YUV420 8-bit/10-bit, YUV422 8-bit/10-bit/12-bit.
*   **RGB Formats:** RGB888, RGB666, RGB565, RGB555, RGB444.
*   **RAW Formats:** RAW8, RAW10, RAW12, RAW14, RAW16.
*   **User-Defined Formats:** Reserved for vendor-specific or custom data.

This layered approach and diverse packet structure enable CSI-2 to efficiently transport complex imaging data while maintaining flexibility and reliability across different hardware implementations.

