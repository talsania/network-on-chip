# Scalable 4-Core Mesh Network-on-Chip (NoC)

![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen)
![FPGA](https://img.shields.io/badge/FPGA-Artix--7-blue)
![HDL](https://img.shields.io/badge/HDL-SystemVerilog-orange)

## 1. Overview
This project is a hardware-oriented, FPGA-ready implementation of a scalable Network-on-Chip (NoC) architecture. It is designed as a reusable interconnect fabric for multi-core systems, with a focus on synthesis friendliness, modularity, and measurable hardware behavior.

The primary objective is to provide a scalable interconnect fabric suitable for multi-core compute platforms, addressing the need for high-throughput, low-latency communication between custom accelerators or RISC-V cores.

- **4-core mesh NoC:** Fully parameterized 2x2 mesh topology.
- **Router design:** Dimension-Order Routing (XY routing) ensuring deadlock-free traversal.
- **Basic packetization and arbitration:** 3-flit packetization (Head, Body, Tail) with 5-way Round-Robin arbitration featuring packet-locking.
- **Latency measurement:** Hardware-level end-to-end latency timestamping and calculation.
- **Hardware Demonstration:** Integrated UART Bridge for real-time PC-to-FPGA testing and latency visualization.

---

## 2. Architecture Specification

### Top-Level Mesh Topology
The fabric utilizes a standard 2D mesh consisting of 4 nodes. Each node contains a **Network Interface (NI)** for core-level packetization and a **5-Port Router** (Local, North, South, East, West).

```mermaid
graph TD
    %% Node 0
    subgraph Node0 ["Node 0 (0,0)"]
        C0[Core 0 + NI] <==>|Local| R0{Router 0}
    end

    %% Node 1
    subgraph Node1 ["Node 1 (1,0)"]
        C1[Core 1 + NI] <==>|Local| R1{Router 1}
    end

    %% Node 2
    subgraph Node2 ["Node 2 (0,1)"]
        C2[Core 2 + NI] <==>|Local| R2{Router 2}
    end

    %% Node 3
    subgraph Node3 ["Node 3 (1,1)"]
        C3[Core 3 + NI] <==>|Local| R3{Router 3}
    end

    %% Fabric Connections
    R0 <==>|East/West| R1
    R0 <==>|South/North| R2
    R1 <==>|South/North| R3
    R2 <==>|East/West| R3

    classDef router fill:#005288,stroke:#000,stroke-width:2px,color:#fff,rx:5px,ry:5px;
    classDef core fill:#e26d5c,stroke:#000,stroke-width:2px,color:#fff;
    class R0,R1,R2,R3 router;
    class C0,C1,C2,C3 core;
```

### Router Micro-architecture
Each router is highly modular and synthesis-ready, consisting of:
1. **Input Buffers:** 8-depth FIFOs with strict Valid/Ready flow control.
2. **XY Routing Logic:** Combinational dimension-order logic.
3. **Switch Allocator:** A 5-port matrix utilizing Round-Robin arbiters with strict packet-locking.
4. **Crossbar Switch:** A purely combinational AND-OR multiplexer matrix for latch-free data routing.

```mermaid
graph LR
    %% External Inputs
    subgraph Inputs ["5 Input Ports"]
        I_L[Local In]
        I_N[North In]
        I_S[South In]
        I_E[East In]
        I_W[West In]
    end

    %% Input Buffers
    subgraph Buffers ["Input Buffers"]
        F_L[FIFO 8-Deep]
        F_N[FIFO 8-Deep]
        F_S[FIFO 8-Deep]
        F_E[FIFO 8-Deep]
        F_W[FIFO 8-Deep]
    end

    %% XY Routing
    subgraph Routing ["Route Calculation"]
        XY_L[XY Router]
        XY_N[XY Router]
        XY_S[XY Router]
        XY_E[XY Router]
        XY_W[XY Router]
    end

    %% Switch Allocator
    SA{{"Switch Allocator<br/>(5x5 Round-Robin<br/>Arbitration Matrix)"}}

    %% Crossbar
    CB[["5x5 Combinational<br/>Crossbar Switch"]]

    %% External Outputs
    subgraph Outputs ["5 Output Ports"]
        O_L[Local Out]
        O_N[North Out]
        O_S[South Out]
        O_E[East Out]
        O_W[West Out]
    end

    %% Data Path (Inputs to FIFOs)
    I_L ==> F_L
    I_N ==> F_N
    I_S ==> F_S
    I_E ==> F_E
    I_W ==> F_W

    %% Data Path to Routing
    F_L --> XY_L
    F_N --> XY_N
    F_S --> XY_S
    F_E --> XY_E
    F_W --> XY_W

    %% Request Path to Allocator
    XY_L -. Request .-> SA
    XY_N -. Request .-> SA
    XY_S -. Request .-> SA
    XY_E -. Request .-> SA
    XY_W -. Request .-> SA

    %% Grant Path to Crossbar
    SA -. Grants .-> CB

    %% Data Path (FIFOs to Crossbar)
    F_L ==> CB
    F_N ==> CB
    F_S ==> CB
    F_E ==> CB
    F_W ==> CB

    %% Data Path (Crossbar to Outputs)
    CB ==> O_L
    CB ==> O_N
    CB ==> O_S
    CB ==> O_E
    CB ==> O_W

    classDef main fill:#2a9d8f,stroke:#000,stroke-width:2px,color:#fff;
    classDef logic fill:#e9c46a,stroke:#000,stroke-width:2px,color:#000;
    classDef arbiter fill:#f4a261,stroke:#000,stroke-width:2px,color:#000;
    
    class I_L,I_N,I_S,I_E,I_W,O_L,O_N,O_S,O_E,O_W main;
    class F_L,F_N,F_S,F_E,F_W,XY_L,XY_N,XY_S,XY_E,XY_W logic;
    class SA,CB arbiter;
```

### Data Path & Packet Structure
To meet the technical expectations, the data path is strictly defined:
- **Physical Link Width:** 34 bits (1-bit X coordinate, 1-bit Y coordinate, 2-bit Flit Type, 30-bit Payload).
- **Packet Size:** 3 Flits (Head, Body, Tail).
- **Core Interface Width:** 60 bits (30-bit Body + 30-bit Tail).
- **Arithmetic Justification:** The system utilizes fixed-point bitwise operations for routing, allocation, and timestamping. Floating-point is unnecessary for NoC interconnect logic and would needlessly waste LUTs and power.

---

## 3. Functional Verification Results

The design utilizes a comprehensive SystemVerilog verification suite. Verification was performed using Xilinx Vivado.

### Test Coverage
- **Unit Tests:** FIFO wrap-around, XY path resolution, Crossbar bijection.
- **Fabric Tests:** 1-hop, multi-hop, simultaneous bijection, and severe 5-way port contention.
- **Flow Control:** Upstream backpressure (FIFO full) and downstream stalls (Core busy).

**Simulation Output:**
1. _NoC Top Module Test_

   <img width="630" height="785" alt="top_noc" src="https://github.com/user-attachments/assets/30f07bd8-e71c-44a5-9952-5c1e9f44e7f1" />

2. _UART Standalone Loopback Test_
  
   <img width="542" height="548" alt="phase 1" src="https://github.com/user-attachments/assets/07c4d6e9-fb8d-4050-a5eb-b5ef802ef627" />

3. _UART Protocol Bridge Test_
  
   <img width="661" height="508" alt="phase 2" src="https://github.com/user-attachments/assets/69b50dc5-1811-4fc8-a5b1-dd9f3211e821" />

**Data Transfer Waveform:**

   <img width="1546" height="400" alt="waveform" src="https://github.com/user-attachments/assets/8892c21f-53e4-43fb-8c00-cc8d79cb6542" />

**Note:** Each design module for NoC is tested individually, covering all edge cases for the respective module. NoC testbenches are in [rtl/sim](rtl/sim). FPGA/UART wrapper-oriented testbenches are in [fpga/sim](fpga/sim).

### Repository Layout
- [rtl](rtl): synthesizable NoC RTL
- [rtl/uart](rtl/uart): shared UART/protocol blocks (`uart_tx`, `uart_rx`, `uart_cmd_parser`, `uart_resp_formatter`)
- [rtl/sim](rtl/sim): NoC and UART integration simulation testbenches
- [fpga](fpga): FPGA top wrapper and board integration files
- [fpga/constraints](fpga/constraints): XDC constraints
- [fpga/sim](fpga/sim): wrapper-level simulation benches

---

## 4. Hardware Implementation & Real-Time Capability

The design is deployed on a **Xilinx Artix-7 (xc7a100tcsg324-1)** FPGA.
To demonstrate real-time capability, a custom **UART Protocol Bridge** was integrated into Node 0.
1. The PC sends a binary payload via UART (`0xA1` to target Node 1).
2. Node 0 packetizes it and routes it across the physical FPGA fabric.
3. Node 1 extracts it, embeds its Node ID, and bounces it back.
4. Node 0 ejects the packet, calculates latency, and transmits the payload + latency back to the PC via UART.

**Hardware Test Output (HTerm)**

   <img width="1919" height="961" alt="Screenshot 2026-04-06 054844" src="https://github.com/user-attachments/assets/8b35e220-2807-44b7-8bfd-21d797360171" />

_The hex output `B1 48 4F 57 00 03` confirms successful traversal from Node 0 to Node 1 and back._ 

Here is what it represents:
- `B1`: Response from Node 1
- `48 4F 57`: Payload
- `00 03`: Latency (in clock cycles)

**Note:** As the custom UART module only parses hexadecimal or binary characters, _HTerm terminal software_ is used to demonstrate communication between the 4 nodes of the Network-on-Chip.

---

## 5. Performance Metrics & Resource Utilization

### FPGA Resource Utilization

The architecture is designed for hardware efficiency, utilizing minimal logic to allow maximum area for AI/ML compute cores.
| Resource | Utilization | Available | % Used |
| -------- | ----------- | --------- | ------ |
| **LUTs** | 1,731 | 63,400 | 2.73 |
| **FFs** | 3,656 | 126,800 | 2.88 |
| **BRAM** | 0 | 135 | 0 |

   <img width="1507" height="91" alt="util" src="https://github.com/user-attachments/assets/eb6c9b94-a5bc-4b48-93c9-bf83b5afda3c" />

### Power-Performance Trade-offs

**Total Power:** 0.127 W

   <img width="792" height="437" alt="power" src="https://github.com/user-attachments/assets/a14d758a-a0e9-46ae-9809-bb9259bd4706" />

**Discussion:** The purely combinational crossbar and XY routing units ensure minimal dynamic power draw by avoiding unnecessary register stages. The use of Dimension-Order Routing sacrifices some peak throughput under heavy congestion compared to adaptive routing, but significantly reduces LUT utilization and static power consumption.
**Discussion:** The purely combinational crossbar and XY routing units ensure minimal dynamic power draw by avoiding unnecessary register stages. The use of Dimension-Order Routing sacrifices some peak throughput under heavy congestion compared to adaptive routing, but significantly reduces LUT utilization and static power consumption.

### Throughput & Latency
   
   <img width="1017" height="198" alt="time" src="https://github.com/user-attachments/assets/98a6923f-f648-4a42-930a-189ed40384cd" />

- **Clock Frequency:** 100 MHz (Timing constraints fully met).
- **Latency:** Base 1-hop latency is 3 clock cycles (30ns).
- **Peak Throughput:** 100 million flits/sec per link (3.4 Gbps per directional port).

#### Peak Throughput Calculation

The peak throughput of the Network-on-Chip is calculated based on the physical data path width and the global clock frequency. 

**Hardware Parameters:**
* **Global Clock ($f_{clk}$):** 100 MHz ($10^8$ cycles/second)
* **Physical Link Width:** 34 bits per flit
* **Transfer Rate:** 1 flit per clock cycle per port

**Base Flit Rate (Per Port):**
Each router port can transmit one flit per clock cycle.
> $100,000,000 \text{ cycles/sec} \times 1 \text{ flit/cycle} = \mathbf{100 \text{ Million flits/sec}}$

**Raw Data Throughput (Per Port):**
To find the raw bandwidth, we multiply the flit rate by the physical width of the flit.
> $100,000,000 \text{ flits/sec} \times 34 \text{ bits/flit} = 3,400,000,000 \text{ bits/sec}$
> **= 3.4 Gbps per directional port**

**Total Fabric Bandwidth:**
In a 2x2 Mesh topology, there are 4 internal bi-directional links (8 directional wires) and 4 local injection/ejection ports connecting the processing cores. The theoretical maximum data moving through the entire fabric simultaneously is:
> $(8 \text{ Internal Links} + 4 \text{ Local Links}) \times 3.4 \text{ Gbps}$ 
> **= 40.8 Gbps Total Peak Fabric Bandwidth**

---

## 6. Scalability Roadmap 

To evolve this design into a larger production-grade interconnect, the following architectural enhancements are planned:
1. **Scalability to 8+ Cores**: Parameterize the `COORD_WIDTH` and `genvar` loops to automatically synthesize 4x4 (16 cores) or 8x8 (64 cores) topologies without modifying the underlying router micro-architecture.
2. **Quality of Service (QoS)**: Implement Virtual Channels (VCs) within the input FIFOs to prioritize critical control packets (e.g., RISC-V interrupts) over bulk data transfers (e.g., Neural Network weight streaming).
3. **Dynamic/Adaptive Routing**: Replace the static XY router with a minimal adaptive router (e.g., Turn Model or Odd-Even routing) to navigate around congested hotspots during heavy machine learning workloads.
4. **Congestion Control & Power-Aware Routing**: Implement clock-gating on unused router ports and introduce source-throttling mechanisms when downstream latency timestamps exceed a critical threshold.

---

## 7. Instructions to Run
1. Clone the repository and open it in Vivado Tcl Shell (or open Vivado GUI and use the Tcl Console).
2. Recreate the project directly from the repository script:

    ```tcl
    cd <path-to-network-on-chip>
    source create_project.tcl
    ```

3. Optional: override project name while sourcing the script:

    ```tcl
    source create_project.tcl -tclargs --project_name noc_build
    ```

4. Open the created project, then run synthesis/implementation and generate the bitstream.
5. Program the Artix-7 board from _Hardware Manager_.
6. Open HTerm Serial Terminal at `115200` Baud, configure HEX send/receive, and transmit `A1 48 4F 57` to initiate a visual ping to Node 1.
7. Observe the returned response on the receiver window and continue testing with additional packets.

**Note:** If your local folder structure differs from the original export environment used to generate [create_project.tcl](create_project.tcl), regenerate the script from your local Vivado project (or update the source paths inside the script) before sourcing.

---

Click to watch the video

[<img width="600" height="300" alt="Screenshot 2026-04-06 073100" src="https://github.com/user-attachments/assets/db88dd0d-d22b-4e75-91a4-974e73622c92" />](https://drive.google.com/file/d/1MGtnVGMnL-R3wZSs0krQGpGEKp4HxZ-9/view?usp=sharing)
