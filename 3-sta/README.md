# Physical Design & Timing Analysis: RV32I v3 on Sky130

Physical implementation and timing analysis of the 2-way superscalar RV32I v3 processor using Yosys, OpenSTA, OpenROAD, and the SkyWater Sky130 open PDK.

This extends the methodology used for RV32I v2. v2 was evaluated primarily using post-synthesis OpenSTA, while v3 is taken through the complete physical-design flow: synthesis, floorplanning, placement, clock-tree synthesis, routing, and post-route timing analysis.

The main goal is to determine how the additional hardware required for superscalar execution and branch prediction affects area, timing, and achievable clock frequency.

---

## Architecture

The v3 processor is a 2-way superscalar, in-order RV32I core featuring:

- 2-wide fetch and dispatch
- Dual integer ALUs
- 4-read / 2-write register file
- Multi-lane bypass forwarding
- RAW/WAW, load-use, and structural hazard handling
- Replay of dependent instruction pairs
- Dynamic branch prediction
- Single data-memory port

An independent-ALU benchmark achieved:

```text
120 instructions / 65 cycles = 1.846 IPC
```

Representative workloads also showed improvements over the previous scalar v2 core:

| Benchmark | v2 IPC | v3 IPC | Improvement |
|---|---:|---:|---:|
| Matrix | 0.7500 | 0.8824 | +17.7% |
| Bubble Sort | 0.7600 | 1.0000 | +31.6% |

---

## Branch Predictor Evaluation

Three predictors were evaluated:

- Always Not-Taken
- 512-entry 2-bit Bimodal
- 10-bit-history Gshare with a 1024-entry 2-bit PHT

| Benchmark | Metric | Not-Taken | Bimodal | Gshare |
|---|---|---:|---:|---:|
| Fibonacci | IPC | 0.9801 | **1.4752** | 1.2314 |
| | Accuracy | 3.45% | **89.66%** | 55.17% |
| Binary Search | IPC | 0.8529 | **0.8764** | 0.8512 |
| | Accuracy | 72.20% | **78.03%** | 71.75% |
| Insertion Sort | IPC | 0.8711 | **0.8862** | 0.8807 |
| | Accuracy | 89.26% | **93.33%** | 91.48% |
| GCD | IPC | 0.8267 | **0.8442** | 0.8380 |
| | Accuracy | 75.16% | **77.74%** | 76.77% |
| String Search | IPC | 0.9408 | 0.9461 | **0.9670** |
| | Accuracy | 82.45% | 83.97% | **89.92%** |

Bimodal achieved higher IPC on four of five representative applications.

Gshare performed better when useful global branch correlation existed. On a synthetic branch-correlation stress test, prediction accuracy was:

```text
Gshare:       88.75%
Bimodal:      71.46%
Not-Taken:    27.29%
```

However, synthesis showed that the additional Gshare state was expensive when implemented entirely from standard cells.

---

## Initial Gshare Synthesis

Without SRAM macros, the 1024 × 2-bit Gshare Pattern History Table synthesized into 2,048 flip-flops plus its associated indexing and selection logic.

```text
Total core:
    Cells:                  22,562
    Area:                 0.237605 mm²

Gshare predictor:
    Cells:                   8,996
    Area:                 ~0.108051 mm²
    PHT flip-flops:           2,048
    Share of core area:      ~45.5%

Register file:
    Cells:                   6,428
    Area:                 ~0.067926 mm²
```

The branch predictor alone occupied nearly half of the synthesized core and was larger than the 4R/2W register file.

---

## Pre-Layout OpenSTA: Gshare

Standalone OpenSTA was first used to characterize the synthesized design at the same 17 ns target used for v2.

```text
Clock period:     17.00 ns
Target frequency: 58.82 MHz

WNS:             -96.07 ns
TNS:         -386,257.78 ns
```

The worst paths were dominated by the standard-cell implementation of the Gshare PHT. Several predictor nets had fanouts exceeding 1,000 loads, producing extreme slew and delay.

This demonstrated an important limitation of implementing memory-like structures as discrete flip-flops: an RTL array that is logically simple can become a large network of registers, decoders, and multiplexers after synthesis.

OpenSTA can identify these problems but does not perform placement, buffering, cell resizing, or routing to repair them.

---

## Switching to Bimodal

Based on both application performance and implementation cost, Bimodal was selected for the final physical implementation.

The final predictor contains a 512-entry × 2-bit BHT with two combinational read ports and one update port.

Standalone synthesis produced:

```text
Total core:
    Cells:                  17,322
    Area:                 0.184122 mm²

Bimodal predictor:
    Cells:                   3,880
    Area:                 0.054059 mm²
    Predictor FFs:            1,024

Register file:
    Cells:                   6,404
    Area:                 ~0.068700 mm²
```

The Bimodal predictor still accounts for approximately 29% of the synthesized core, but substantially reduces the implementation cost relative to Gshare.

---

## Pre-Layout OpenSTA: Bimodal

At the same 17 ns clock:

```text
Clock period:     17.00 ns
Target frequency: 58.82 MHz

WNS:             -52.87 ns
TNS:         -53,668.69 ns
```

The predictor was no longer responsible for the worst paths. Instead, timing became dominated by high-fanout pipeline control signals.

A representative internal register-to-register path reported:

```text
Data arrival:    35.766 ns
Required:        16.612 ns
Slack:          -19.155 ns
```

with high-fanout nodes including:

```text
Node        Fanout      Slew        Delay
------------------------------------------
_3742_/X      329      15.069 ns    10.755 ns
_3745_/Y      229       9.524 ns    19.295 ns
```

These paths are important because they are dominated by unbuffered global control distribution rather than a fundamentally long arithmetic datapath.

This motivated taking v3 through physical implementation instead of treating standalone OpenSTA as the final timing result.

---

## Why v2 Stopped at OpenSTA

The cacheless RV32I v2 core met the same 17 ns target using standalone OpenSTA:

```text
WNS:                 +0.55 ns
TNS:                  0.00 ns
Worst-path arrival:  15.91 ns
Target frequency:    58.82 MHz
```

Its critical path was nevertheless a high-fanout `dmem_ready`/pipeline-stall path, including a node with:

```text
Load:       1.535 pF
Slew:      10.532 ns
Delay:      7.867 ns
```

Because v2 already met its timing target, physical implementation was outside the scope of that project. The report noted that placement and buffer insertion would likely improve this high-fanout path.

v3 does not meet its target in standalone OpenSTA, so that assumption needs to be tested directly through physical implementation.

---

# OpenROAD Physical Design

The final Bimodal design is implemented using OpenROAD Flow Scripts with the Sky130 HD standard-cell library.

## Setup

On Apple Silicon:

```bash
docker pull --platform linux/amd64 openroad/orfs:latest
```

Launch the flow:

```bash
docker run --rm -it \
  --platform linux/amd64 \
  -u "$(id -u):$(id -g)" \
  -e OMP_NUM_THREADS=1 \
  -e KMP_AFFINITY=disabled \
  -v "$(pwd):/riscv-v3" \
  -v "$(pwd)/3-sta/OpenROAD-flow-scripts/flow:/work" \
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
  -e WORK_HOME=/work \
  openroad/orfs:latest \
  bash
```

`OMP_NUM_THREADS=1` and `KMP_AFFINITY=disabled` avoid an OpenMP CPU-affinity assertion encountered while running the x86-64 OpenROAD image through Apple Silicon emulation.

The implementation uses:

```text
Clock period:       17.00 ns
Clock uncertainty:   0.25 ns
Target frequency:   58.82 MHz
Core utilization:      35%
Placement density:      40%
```

---

## 1. Synthesis

Synthesis converts the SystemVerilog design into a Sky130 standard-cell netlist.

```bash
make synth \
  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk
```

Result:

```text
Design area: 199,156 µm²
```

---

## 2. Floorplanning

Floorplanning defines the die/core dimensions, standard-cell rows, and available placement area.

```bash
make floorplan \
  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk
```

The design intentionally uses low utilization to leave room for buffering, cell resizing, and routing.

```text
Die size:        ~756.33 × 756.33 µm
Core area:       ~565,998 µm²
```

---

## 3. Placement

Placement assigns physical locations to the synthesized standard cells and optimizes their positions for wire length, congestion, and timing.

```bash
make place \
  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk
```

Results:

```text
Instances:               25,526
Nets:                    18,484
Pins:                    71,246

Original HPWL:          891,732 µm
Optimized HPWL:         865,684 µm

Design area:            214,459 µm²
Utilization:                 38%
```

Detailed placement completed with zero overlaps, alignment problems, or edge-spacing violations.

---

## 4. Clock Tree Synthesis

CTS inserts and balances clock buffers so that the clock can physically drive the thousands of sequential elements in the design while controlling clock slew and skew.

```bash
make cts \
  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk
```

CTS completed successfully.

---

## 5. Routing

Routing creates the physical metal and via connections between the placed cells.

```bash
make route \
  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk
```

The routed design contains approximately:

```text
Components:    25,834
Nets:          18,478
Terminals:        303
```

Routing consists of pin-access analysis, global routing, and detailed routing while satisfying the Sky130 physical design rules.

---

## 6. Post-Route Timing Analysis

After routing, OpenROAD can estimate/extract interconnect parasitics and perform timing analysis using the physically implemented clock and signal networks.

This is the key comparison against the standalone OpenSTA result: high-fanout pipeline-control nets can now be physically buffered, placed, and routed rather than analyzed as an unoptimized synthesized network.

### Final Results

TODO after routing completes:

```text
Clock period:       17.00 ns
Target frequency:   58.82 MHz

WNS:                TODO
TNS:                TODO
Worst setup path:   TODO
Worst hold slack:   TODO
Final area:         TODO
Final utilization:  TODO
DRC violations:     TODO
```

---

# Results Summary

| Metric | Gshare, Pre-Layout | Bimodal, Pre-Layout | Bimodal, Post-Route |
|---|---:|---:|---:|
| Cells | 22,562 | 17,322 | TODO |
| Area | 0.2376 mm² | 0.1841 mm² | TODO |
| Predictor area | ~0.1081 mm² | ~0.0541 mm² | ~0.0541 mm² + physical optimization |
| WNS @ 17 ns | −96.07 ns | −52.87 ns | TODO |
| TNS | −386,257.78 ns | −53,668.69 ns | TODO |
| Timing bottleneck | Gshare PHT/fanout | Pipeline control fanout | TODO |

---

# Conclusions

The v3 implementation demonstrates why processor structures should be evaluated using both architectural performance and physical implementation cost.

Gshare provided better prediction on workloads with useful global branch correlation, but Bimodal achieved higher IPC on four of five representative applications while requiring substantially less hardware. The standard-cell Gshare implementation consumed approximately 45.5% of total synthesized area and generated severe high-fanout timing paths.

Switching to Bimodal reduced core area from approximately 0.238 mm² to 0.184 mm² and shifted the critical timing problem away from the predictor toward global pipeline-control distribution.

Unlike v2, v3 is therefore carried through the complete OpenROAD physical-design flow. The final post-route analysis will determine whether physical buffering, placement, clock-tree synthesis, and routing can recover the severe high-fanout timing penalties observed in standalone OpenSTA.

Ultimately, superscalar performance must account for both IPC and achievable clock frequency:

```text
Instruction throughput ≈ IPC × clock frequency
```

The final physical timing result therefore determines whether the IPC gains of the 2-way architecture translate into higher overall processor throughput.