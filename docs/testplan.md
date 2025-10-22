# USB Device Controller — Verification Test Plan

## 1. Overview

This document describes the **verification strategy and test plan** for the USB Device Controller project.  
The DUT (Device Under Test) implements a simplified USB 1.1 full-speed **device-side controller** with:
- Control Endpoint 0 (for enumeration and control transfers)
- Data Endpoint 1 (bulk-like loopback)
- Packet interface logic (token decode, data/handshake response)
- Address register, data toggling, and stall handling.

Verification will be performed entirely at the **packet level**, i.e., token and data packets are modeled directly in the testbenches.  
The physical signaling (NRZI, bit-stuffing, etc.) is not modeled — this keeps the design fully synthesizable and focused on logical correctness.

Simulation and automation will use **Icarus Verilog (iverilog + vvp)** with optional `-g2012` flag for SystemVerilog support.  
A Tcl-based automation script will run and evaluate all testbenches automatically.

---

## 2. DUT Description

### 2.1 DUT Name
`usb_top.v`

### 2.2 Hierarchy
The top-level module instantiates:
- `usb_pktif.v` — token & data packet routing
- `usb_ctrl_ep0.v` — control endpoint state machine
- `usb_data_ep1.v` — bulk endpoint with FIFO + data toggle
- `usb_addr_reg.v` — device address register
- `usb_defs.v` — shared constants and PIDs

### 2.3 DUT Interface (high-level)
| Signal | Direction | Width | Description |
|:--------|:-----------|:-------|:-------------|
| `clk` | Input | 1 | Simulation clock |
| `rst_n` | Input | 1 | Active-low reset |
| `in_pkt_valid` | Input | 1 | Indicates incoming packet from host |
| `in_pkt_pid` | Input | 4 | PID of incoming packet (SETUP/OUT/IN) |
| `in_pkt_ep` | Input | 4 | Endpoint number |
| `in_pkt_addr` | Input | 7 | Device address field from token |
| `in_pkt_data` | Input | 8 | Data byte from host |
| `in_pkt_len` | Input | 16 | Packet data length in bytes |
| `out_pkt_valid` | Output | 1 | Device ready to transmit a packet |
| `out_pkt_pid` | Output | 4 | PID of outgoing packet (ACK/NAK/DATAx/STALL) |
| `out_pkt_data` | Output | 8 | Transmit data byte |
| `out_pkt_len` | Output | 16 | Length of outgoing packet |
| `dev_addr` | Output | 7 | Current address stored in address register |

All timing relationships are synchronous to `clk`.

---

## 3. Verification Strategy

### 3.1 Objectives
- Verify correctness of protocol response for all legal transactions:
  - Control transfers: `GET_DESCRIPTOR`, `SET_ADDRESS`
  - Bulk transfers: IN and OUT
- Ensure correct behavior under abnormal and corner conditions:
  - FIFO overflow
  - Invalid PIDs
  - Unrecognized requests
  - Repeated SETUP or IN/OUT packets
- Validate data toggle management (DATA0/DATA1)
- Confirm reset and suspend recovery logic
- Confirm synthesizable behavior (no unsupported constructs)

### 3.2 Approach
- Develop **self-checking testbenches** (each in `tb/*.v`)
- Each test runs independently, compares DUT output against expected results, and prints **PASS/FAIL**
- Automation through **Tcl script** (`sim/run_tests.tcl`)
- Directed + Random + Corner-case tests for each functionality
- Log-based verification: each test’s output stored as `sim/<testname>_log.txt`
- Tcl script scans logs for keyword `"FAIL"` and produces a summary.

### 3.3 Testbench Common Components
- `tb_common.v` provides reusable tasks and functions:
  - Packet builders for SETUP, IN, OUT, ACK, NAK, STALL
  - Response checker task (`expect_packet`)
  - Utility functions for data comparison
  - Scoreboard / reference model for endpoint FIFOs
- Host-side driver FSM (inside each testbench):
  - Sends tokens and data packets to DUT
  - Waits for DUT responses
- Each testbench ends simulation with a clear message:
```

[TESTNAME] PASS

```
or
```

[TESTNAME] FAIL: <reason>

```

---

## 4. Test Cases Summary

| Sl. No | Testbench File | Functionality | Category | Description |
|:--|:--|:--|:--|:--|
| 1 | `tb_reset.v` | Reset Behavior | Directed / Random / Corner | Validate reset and default states |
| 2 | `tb_get_descriptor.v` | GET_DESCRIPTOR Handling | Directed / Random / Corner | Verify control endpoint descriptor response |
| 3 | `tb_set_address.v` | SET_ADDRESS Handling | Directed / Random / Corner | Validate device address update mechanism |
| 4 | `tb_ep1_loopback.v` | Bulk Endpoint Loopback | Directed / Random / Corner | Test IN/OUT data transfers and integrity |
| 5 | `tb_data_toggle.v` | Data Toggle Logic | Directed / Random / Corner | Verify DATA0/DATA1 alternation |
| 6 | `tb_stall.v` | STALL Response | Directed / Random / Corner | Test invalid requests and endpoint stall |
| 7 | `tb_random_stress.v` | Randomized Stress Test | Randomized | Mix of random packet sequences |

---

## 5. Detailed Test Descriptions

### 5.1 Test 1 — `tb_reset.v`
**Objective:** Validate that DUT resets cleanly and initializes all internal registers and FSMs to default.

**Checks:**
- Device address = 0
- FIFO empty
- EP toggles = DATA0
- No pending packet outputs after reset

**Directed:**
- Apply reset for 10 cycles → Release → Check default values

**Random:**
- Randomize reset duration (1–20 cycles)

**Corner:**
- Multiple back-to-back resets, short pulses

**Pass Criteria:** All default values correct, no output packet, PASS message printed.

---

### 5.2 Test 2 — `tb_get_descriptor.v`
**Objective:** Validate GET_DESCRIPTOR (Device) control transfer sequence.

**Checks:**
- Proper parsing of SETUP packet
- Correct device descriptor bytes returned
- Proper status stage ACK
- Descriptor truncation behavior when host requests fewer bytes

**Directed:**
- Send standard GET_DESCRIPTOR for Device (length 18)
- Verify returned bytes against expected ROM values

**Random:**
- Request length randomly between 8–64 bytes

**Corner:**
- Request length > descriptor size (e.g., 512)
- Corrupted PID (simulate error handling)

**Pass Criteria:** All descriptor bytes match expected values; no extra or missing bytes.

---

### 5.3 Test 3 — `tb_set_address.v`
**Objective:** Validate correct operation of SET_ADDRESS request.

**Checks:**
- SET_ADDRESS request properly parsed
- New address not active until after status stage
- `usb_addr_reg` updates with new value

**Directed:**
- Issue SET_ADDRESS to 5, verify address updates after status

**Random:**
- Random address values between 0–127

**Corner:**
- SET_ADDRESS = 0
- SET_ADDRESS issued during reset (ignored)

**Pass Criteria:** Address updated correctly, proper handshake.

---

### 5.4 Test 4 — `tb_ep1_loopback.v`
**Objective:** Verify endpoint 1 bulk IN/OUT loopback mechanism.

**Checks:**
- OUT transfers store data to FIFO
- IN transfers return same data (loopback)
- ACK handshake generation
- FIFO boundary behavior

**Directed:**
- Send OUT with `[0x01, 0x02, ..., 0x10]`, then IN, verify returned payload

**Random:**
- $random payloads (1–64 bytes) repeated multiple times

**Corner:**
- FIFO overflow (send more than depth)
- Repeated IN without OUT

**Pass Criteria:** Returned data identical; no overflow corruption.

---

### 5.5 Test 5 — `tb_data_toggle.v`
**Objective:** Verify DATA0/DATA1 toggling per endpoint.

**Checks:**
- Correct alternation per successful transaction
- Toggle only after ACK handshake
- Reset resets toggle to DATA0

**Directed:**
- Perform two consecutive IN/OUT; verify PID alternates

**Random:**
- Randomized valid transaction sequences (IN/OUT)

**Corner:**
- Missing ACK (host retries) → toggle should not flip

**Pass Criteria:** Toggles alternate correctly only after ACK.

---

### 5.6 Test 6 — `tb_stall.v`
**Objective:** Validate STALL response to unsupported requests.

**Checks:**
- Unsupported control request → STALL response
- Proper recovery after STALL
- No data output on stalled endpoint

**Directed:**
- Send invalid request code to EP0 → expect STALL

**Random:**
- Random unsupported request values

**Corner:**
- Multiple STALLs followed by valid request → recovery

**Pass Criteria:** STALL PID observed; recovery verified.

---

### 5.7 Test 7 — `tb_random_stress.v`
**Objective:** Random stress test for protocol robustness.

**Checks:**
- No FSM lockup or illegal state
- Responses remain legal (ACK/NAK/STALL only)
- Device address correctness maintained
- No cross-endpoint interference

**Method:**
- Generate random tokens (IN/OUT/SETUP)
- Random payloads and endpoint numbers
- Random delays between packets

**Pass Criteria:** No FAIL printed; all transactions either valid or properly rejected.

---

## 6. Automation and Reporting

### 6.1 Test Execution
All testbenches listed in `sim/test_list.txt` will be executed by `sim/run_tests.tcl`.  
Example:
```

tb_reset
tb_get_descriptor
tb_set_address
tb_ep1_loopback
tb_data_toggle
tb_stall
tb_random_stress

```

### 6.2 Automation Script Behavior
- Compile each TB with:
```

iverilog -g2012 -o <tbname>.vvp hw/*.v tb/<tbname>.v tb/tb_common.v

```
- Run simulation:
```

vvp <tbname>.vvp > sim/<tbname>_log.txt

```
- Parse logs for keyword `"FAIL"`.
- Print summary to console:
```

tb_reset... PASS
tb_get_descriptor... FAIL (see sim/tb_get_descriptor_log.txt)
...
Total: 6 PASS, 1 FAIL

```

### 6.3 Log File Format
Each log file will contain:
1. Test header
2. Verbose transaction details
3. Final summary line:
```

[TESTNAME] PASS

```
or
```

[TESTNAME] FAIL: reason

```

---

## 7. Coverage Goals

### 7.1 Functional Coverage
- All packet types exercised (SETUP, IN, OUT, DATA0, DATA1, ACK, NAK, STALL)
- Both endpoints (0 and 1)
- All data toggle transitions
- Address range 0–127
- FIFO full/empty conditions
- Error/stall paths

### 7.2 Code Coverage
- Line coverage target ≥ 95%
- FSM transition coverage ≥ 90%

Code coverage can be optionally collected using `iverilog` + `gcov` integration or manual inspection.

---

## 8. Regression Summary and Pass Criteria

| Criterion | Description |
|:--|:--|
| **All directed tests PASS** | Must pass deterministically |
| **Random tests show stable behavior** | 1000+ transactions without fatal errors |
| **No X/Z propagation** | Outputs remain defined |
| **FSM stable** | No deadlocks or invalid transitions |
| **All coverage goals met** | ≥ 90% across all metrics |

When all conditions above are satisfied, the design is declared **functionally verified**.

---

## 9. Deliverables

- `hw/` — All synthesizable Verilog design files
- `tb/` — Self-checking testbenches
- `sim/run_tests.tcl` — Automation script
- `sim/test_list.txt` — List of tests
- `sim/*_log.txt` — Individual test logs
- `docs/design.md` — Design specification
- `docs/testplan.md` — This document
- `Makefile` — Optional wrapper for automation

---

## 10. Future Enhancements

Potential future extensions include:
- Adding endpoint 2 (interrupt type)
- Implementing standard request parsing (SET_CONFIGURATION, GET_STATUS)
- Integrating simple host model for enumeration
- Code coverage automation with Verilator + gcov
- Continuous Integration with GitHub Actions

