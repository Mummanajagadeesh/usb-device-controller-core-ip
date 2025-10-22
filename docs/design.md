# USB Device Controller — Design Specification

## 1. Overview

This document describes the **design and architecture** of the USB Device Controller project.  
The project implements a simplified **USB 1.1 full-speed device controller** with:

- Control Endpoint 0 for enumeration and standard control transfers (`GET_DESCRIPTOR`, `SET_ADDRESS`)
- Bulk-like Endpoint 1 for IN/OUT transfers with loopback
- Packet-level interface logic for token decoding and response generation
- Device address register and data toggle management
- Stall response for unsupported requests
- Synthesizable modules compatible with Verilog-2001/SystemVerilog

Simulation and verification are performed at the **packet level**, i.e., token/data packets are directly driven to the DUT. Physical USB signaling is abstracted for simplicity.

---

## 2. Design Goals

- **Functional correctness:** All USB 1.1 logical behaviors (control transfers, data toggling, endpoint response)
- **Synthesizability:** Fully synthesizable modules with no use of `$fopen`, `$fread`, or `$fwrite` inside DUT
- **Self-checking verification:** Testbenches capable of automatic PASS/FAIL reporting
- **Automation-ready:** Able to run in batch via Tcl script and collect log outputs
- **Modularity:** Top-level design (`usb_top.v`) composed of clearly separated modules:
  - Endpoint modules (`usb_ctrl_ep0.v`, `usb_data_ep1.v`)
  - Packet interface (`usb_pktif.v`)
  - Address/config register (`usb_addr_reg.v`)
  - Constant definitions (`usb_defs.v`)

---

## 3. Top-Level Architecture

### 3.1 Module Hierarchy

```

usb_top.v
├─ usb_pktif.v         // Packet parsing & routing FSM
├─ usb_ctrl_ep0.v      // Endpoint 0 FSM (control transfers)
├─ usb_data_ep1.v      // Endpoint 1 FIFO + loopback + data toggle
├─ usb_addr_reg.v      // Device address register
└─ usb_defs.v          // Shared constants & PID codes

```

### 3.2 Block Description

#### 3.2.1 usb_defs.v
- Centralizes packet IDs (PIDs), endpoint numbers, standard USB constants
- Examples: `PID_SETUP = 4'h2`, `PID_IN = 4'h9`, `EP0 = 0`, `EP1 = 1`

#### 3.2.2 usb_top.v
- Top-level DUT connecting all modules
- Inputs:
  - `clk` / `rst_n`
  - Host packet interface: `in_pkt_valid`, `in_pkt_pid`, `in_pkt_ep`, `in_pkt_addr`, `in_pkt_data`, `in_pkt_len`
- Outputs:
  - Device packet interface: `out_pkt_valid`, `out_pkt_pid`, `out_pkt_data`, `out_pkt_len`
  - Debug signals: `dev_addr`, `ep1_fifo_level` (optional)
- Responsibilities:
  - Route incoming packets to endpoints via `usb_pktif.v`
  - Collect endpoint responses and generate outgoing packets

#### 3.2.3 usb_pktif.v
- **FSM-based packet interface module**
- Responsibilities:
  - Parse incoming tokens and dispatch to the correct endpoint
  - Build outgoing packets from endpoint responses
  - Perform simple CRC pass/fail checking (optional)
  - Maintain handshake coordination (ACK/NAK)

#### 3.2.4 usb_ctrl_ep0.v
- Implements **control endpoint FSM**
- Handles:
  - SETUP → DATA → STATUS stages for standard requests
  - `GET_DESCRIPTOR` response with pre-programmed ROM values
  - `SET_ADDRESS` request to update `usb_addr_reg`
- Internal ROM:
  - Device descriptor stored as `reg [7:0] desc[0:17]; initial begin ... end`
- FSM States:
  - `IDLE`, `SETUP_WAIT`, `DATA_STAGE`, `STATUS_STAGE`, `STALL`
- Outputs:
  - `ep0_out_valid`, `ep0_out_pid`, `ep0_out_data`, `ep0_out_len`

#### 3.2.5 usb_data_ep1.v
- Implements **bulk-like endpoint 1**
- FIFO-based data storage (loopback)
- Supports IN and OUT transfers:
  - OUT → store in FIFO
  - IN → read from FIFO and transmit
- Manages **DATA0/DATA1 toggling** per USB rules
- FIFO implemented as circular buffer with write/read pointers
- FSM States:
  - `IDLE`, `WAIT_OUT`, `WAIT_IN`, `ACK_GENERATE`

#### 3.2.6 usb_addr_reg.v
- 7-bit register storing the device address
- Writeable only by control endpoint (SET_ADDRESS)
- Readable by other modules for packet token comparison

---

## 4. Interfaces

### 4.1 Host → Device Packet Signals
| Signal | Width | Description |
|--------|-------|-------------|
| `in_pkt_valid` | 1 | High when host is sending a packet |
| `in_pkt_pid` | 4 | PID code (SETUP/IN/OUT) |
| `in_pkt_ep` | 4 | Endpoint number |
| `in_pkt_addr` | 7 | Device address field |
| `in_pkt_data` | 8 | Data byte from host |
| `in_pkt_len` | 16 | Number of data bytes in packet |

### 4.2 Device → Host Packet Signals
| Signal | Width | Description |
|--------|-------|-------------|
| `out_pkt_valid` | 1 | High when DUT output is valid |
| `out_pkt_pid` | 4 | PID code (DATA0/DATA1/ACK/NAK/STALL) |
| `out_pkt_data` | 8 | Data byte from DUT |
| `out_pkt_len` | 16 | Packet length in bytes |

### 4.3 Debug Signals
| Signal | Width | Description |
|--------|-------|-------------|
| `dev_addr` | 7 | Current device address |
| `ep1_fifo_level` | ? | Current FIFO fill level (optional) |

---

## 5. FSM Descriptions

### 5.1 Control Endpoint FSM (`usb_ctrl_ep0`)
```

IDLE --> SETUP_WAIT --> DATA_STAGE --> STATUS_STAGE --> IDLE
\                                /
---------> STALL ---------------

```
- **IDLE:** Wait for SETUP token
- **SETUP_WAIT:** Capture and decode SETUP packet
- **DATA_STAGE:** Send or receive data bytes (GET_DESCRIPTOR or host data)
- **STATUS_STAGE:** Send handshake (ACK)
- **STALL:** For unsupported requests

### 5.2 Data Endpoint FSM (`usb_data_ep1`)
```

IDLE --> WAIT_OUT --> ACK_GENERATE --> IDLE

--> WAIT_IN --> ACK_GENERATE --> IDLE

```
- **WAIT_OUT:** Await OUT packet, store data
- **WAIT_IN:** Await IN request, transmit FIFO data
- **ACK_GENERATE:** Issue handshake

### 5.3 Packet Interface FSM (`usb_pktif`)
- **TOKEN_DECODE:** Identify incoming PID & endpoint
- **ROUTE_TO_EP:** Dispatch to proper endpoint
- **COLLECT_RESP:** Gather responses and output to host
- **IDLE:** Wait for next token

---

## 6. Timing and Data Flow

1. Host drives `in_pkt_valid` and provides packet bytes
2. `usb_pktif` decodes PID & endpoint
3. Endpoint FSM processes packet:
   - Control FSM may generate descriptor/status
   - Data FSM may store or transmit FIFO
4. Endpoint signals `*_out_valid` to `usb_pktif`
5. `usb_pktif` assembles outgoing packet and drives `out_pkt_valid`, `out_pkt_pid`, `out_pkt_data`
6. Data toggles updated on successful handshake
7. DUT ready for next packet

Timing is synchronous to `clk`; all packet and handshake logic modeled in FSM cycles.

---

## 7. FIFO Design (`usb_data_ep1`)

- Depth: configurable (e.g., 16 bytes)
- Circular buffer with `write_ptr` and `read_ptr`
- FIFO full: NAK on additional OUT
- FIFO empty: NAK on IN
- DATA0/DATA1 toggle controlled independently of FIFO pointers

---

## 8. Reset and Initialization

- Active-low `rst_n` resets:
  - `usb_addr_reg` → 0
  - Endpoint FSMs → IDLE
  - FIFO pointers → 0
  - Data toggles → DATA0

- Short glitches and back-to-back resets are tolerated
- All outputs default to invalid/idle states

---

## 9. Packet Handling Rules

| Packet Type | Response |
|------------|----------|
| SETUP (EP0) | Pass to control FSM, possibly STALL if unsupported |
| IN (EP0/EP1) | Endpoint returns DATA0/DATA1 or NAK if empty |
| OUT (EP0/EP1) | Endpoint stores payload, ACK handshake if successful |
| Unsupported | STALL generated by endpoint FSM |
| Repeated packet | DATA toggle preserved unless ACKed |

---

## 10. Design Considerations

- **Synthesizable constructs only:** No `$fread/$fwrite` in DUT
- **Parameterization:** FIFO depth, endpoint count, descriptor length via `localparam`
- **SystemVerilog allowed:** for `logic`, `enum`, `always_comb`, `always_ff` in simulation or synthesis
- **Modularity:** All endpoints, packet interface, and registers separated
- **Observability:** Debug outputs (`dev_addr`, `ep1_fifo_level`) included for verification

---

## 11. Deliverables

- `hw/usb_top.v` — top-level device
- `hw/usb_pktif.v` — packet routing & FSM
- `hw/usb_ctrl_ep0.v` — control endpoint FSM
- `hw/usb_data_ep1.v` — bulk endpoint FSM + FIFO + toggle
- `hw/usb_addr_reg.v` — device address register
- `hw/usb_defs.v` — constants / PIDs

Each module is synthesizable, supports self-checking TBs, and fully compatible with **Icarus Verilog** simulation.
