# Physical Design & Timing Analysis: RV32I v3 on Sky130

Physical implementation and timing analysis of the 2-way superscalar
RV32I v3 processor using Yosys, OpenSTA, OpenROAD, and the SkyWater
Sky130 open PDK.

This extends the methodology used for RV32I v2. v2 was evaluated
primarily using post-synthesis OpenSTA, while v3 is taken through the
complete physical-design flow: synthesis, floorplanning, placement,
clock-tree synthesis, routing, and post-route timing analysis.

The main goal is to determine how the additional hardware required for
superscalar execution and branch prediction affects area, timing, and
achievable clock frequency.

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

```
120 instructions / 65 cycles = 1.846 IPC
```

Representative workloads also showed improvements over the previous
scalar v2 core:

\| Benchmark \| v2 IPC \| v3 IPC \| Improvement \|

\|---\|---:\|---:\|---:\|

\| Matrix \| 0.7500 \| 0.8824 \| +17.7% \|

\| Bubble Sort \| 0.7600 \| 1.0000 \| +31.6% \|

---

\## Branch Predictor Evaluation

Three predictors were evaluated:

\- Always Not-Taken

\- 512-entry 2-bit Bimodal

\- 10-bit-history Gshare with a 1024-entry 2-bit PHT

\| Benchmark \| Metric \| Not-Taken \| Bimodal \| Gshare \|

\|---\|---\|---:\|---:\|---:\|

\| Fibonacci \| IPC \| 0.9801 \| \*\***1.4752**\*\* \| 1.2314 \|

\| \| Accuracy \| 3.45% \| \*\***89.66%**\*\* \| 55.17% \|

\| Binary Search \| IPC \| 0.8529 \| \*\***0.8764**\*\* \| 0.8512 \|

\| \| Accuracy \| 72.20% \| \*\***78.03%**\*\* \| 71.75% \|

\| Insertion Sort \| IPC \| 0.8711 \| \*\***0.8862**\*\* \| 0.8807 \|

\| \| Accuracy \| 89.26% \| \*\***93.33%**\*\* \| 91.48% \|

\| GCD \| IPC \| 0.8267 \| \*\***0.8442**\*\* \| 0.8380 \|

\| \| Accuracy \| 75.16% \| \*\***77.74%**\*\* \| 76.77% \|

\| String Search \| IPC \| 0.9408 \| 0.9461 \| \*\***0.9670**\*\* \|

\| \| Accuracy \| 82.45% \| 83.97% \| \*\***89.92%**\*\* \|

Bimodal achieved higher IPC on four of five representative applications.

Gshare performed better when useful global branch correlation existed.
On a synthetic branch-correlation stress test, prediction accuracy was:

\`\`\`text

Gshare: 88.75%

Bimodal: 71.46%

Not-Taken: 27.29%

\`\`\`

However, synthesis showed that the additional Gshare state was expensive
when implemented entirely from standard cells.

---

\## Initial Gshare Synthesis

Without SRAM macros, the 1024 × 2-bit Gshare Pattern History Table
synthesized into 2,048 flip-flops plus its associated indexing and
selection logic.

\`\`\`text

Total core:

  Cells: 22,562

  Area: 0.237605 mm²

Gshare predictor:

  Cells: 8,996

  Area: \~0.108051 mm²

  PHT flip-flops: 2,048

  Share of core area: \~45.5%

Register file:

  Cells: 6,428

  Area: \~0.067926 mm²

\`\`\`

The branch predictor alone occupied nearly half of the synthesized core
and was larger than the 4R/2W register file.

---

\## Pre-Layout OpenSTA: Gshare

Standalone OpenSTA was first used to characterize the synthesized design
at the same 17 ns target used for v2.

\`\`\`text

Clock period: 17.00 ns

Target frequency: 58.82 MHz

WNS: -96.07 ns

TNS: -386,257.78 ns

\`\`\`

The worst paths were dominated by the standard-cell implementation of
the Gshare PHT. Several predictor nets had fanouts exceeding 1,000
loads, producing extreme slew and delay.

This demonstrated an important limitation of implementing memory-like
structures as discrete flip-flops: an RTL array that is logically simple
can become a large network of registers, decoders, and multiplexers
after synthesis.

OpenSTA can identify these problems but does not perform placement,
buffering, cell resizing, or routing to repair them.

---

\## Switching to Bimodal

Based on both application performance and implementation cost, Bimodal
was selected for the final physical implementation.

The final predictor contains a 512-entry × 2-bit BHT with two
combinational read ports and one update port.

Standalone synthesis produced:

\`\`\`text

Total core:

  Cells: 17,322

  Area: 0.184122 mm²

Bimodal predictor:

  Cells: 3,880

  Area: 0.054059 mm²

  Predictor FFs: 1,024

Register file:

  Cells: 6,404

  Area: \~0.068700 mm²

\`\`\`

The Bimodal predictor still accounts for approximately 29% of the
synthesized core, but substantially reduces the implementation cost
relative to Gshare.

---

\## Pre-Layout OpenSTA: Bimodal

At the same 17 ns clock:

\`\`\`text

Clock period: 17.00 ns

Target frequency: 58.82 MHz

WNS: -52.87 ns

TNS: -53,668.69 ns

\`\`\`

The predictor was no longer responsible for the worst paths. Instead,
timing became dominated by high-fanout pipeline control signals.

A representative internal register-to-register path reported:

\`\`\`text

Data arrival: 35.766 ns

Required: 16.612 ns

Slack: -19.155 ns

\`\`\`

with high-fanout nodes including:

\`\`\`text

Node Fanout Slew Delay

------------------------------------------

\_3742\_/X 329 15.069 ns 10.755 ns

\_3745\_/Y 229 9.524 ns 19.295 ns

\`\`\`

These paths are important because they are dominated by unbuffered
global control distribution rather than a fundamentally long arithmetic
datapath.

This motivated taking v3 through physical implementation instead of
treating standalone OpenSTA as the final timing result.

---

\## Why v2 Stopped at OpenSTA

The cacheless RV32I v2 core met the same 17 ns target using standalone
OpenSTA:

\`\`\`text

WNS: +0.55 ns

TNS: 0.00 ns

Worst-path arrival: 15.91 ns

Target frequency: 58.82 MHz

\`\`\`

Its critical path was nevertheless a high-fanout
\`dmem_ready\`/pipeline-stall path, including a node with:

\`\`\`text

Load: 1.535 pF

Slew: 10.532 ns

Delay: 7.867 ns

\`\`\`

Because v2 already met its timing target, physical implementation was
outside the scope of that project. The report noted that placement and
buffer insertion would likely improve this high-fanout path.

v3 does not meet its target in standalone OpenSTA, so that assumption
needs to be tested directly through physical implementation.

---

\# OpenROAD Physical Design

The final Bimodal design is implemented using OpenROAD Flow Scripts with
the Sky130 HD standard-cell library.

\## Setup

On Apple Silicon:

\`\`\`bash

docker pull --platform linux/amd64 openroad/orfs:latest

\`\`\`

Launch the flow:

\`\`\`bash

docker run --rm -it \\

  \--platform linux/amd64 \\

  -u "$(id -u):$(id -g)" \\

  -e OMP_NUM_THREADS=1 \\

  -e KMP_AFFINITY=disabled \\

  -v "\$(pwd):/riscv-v3" \\

  -v "\$(pwd)/3-sta/OpenROAD-flow-scripts/flow:/work" \\

  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \\

  -e WORK_HOME=/work \\

  openroad/orfs:latest \\

  bash

\`\`\`

\`OMP_NUM_THREADS=1\` and \`KMP_AFFINITY=disabled\` avoid an OpenMP
CPU-affinity assertion encountered while running the x86-64 OpenROAD
image through Apple Silicon emulation.

The implementation uses:

\`\`\`text

Clock period: 17.00 ns

Clock uncertainty: 0.25 ns

Target frequency: 58.82 MHz

Core utilization: 35%

Placement density: 40%

\`\`\`

---

\## 1. Synthesis

Synthesis converts the SystemVerilog design into a Sky130 standard-cell
netlist.

\`\`\`bash

make synth \\

  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk

\`\`\`

Result:

\`\`\`text

Design area: 199,156 µm²

\`\`\`

---

\## 2. Floorplanning

Floorplanning defines the die/core dimensions, standard-cell rows, and
available placement area.

\`\`\`bash

make floorplan \\

  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk

\`\`\`

The design intentionally uses low utilization to leave room for
buffering, cell resizing, and routing.

\`\`\`text

Die size: \~756.33 × 756.33 µm

Core area: \~565,998 µm²

\`\`\`

---

\## 3. Placement

Placement assigns physical locations to the synthesized standard cells
and optimizes their positions for wire length, congestion, and timing.

\`\`\`bash

make place \\

  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk

\`\`\`

Results:

\`\`\`text

Instances: 25,526

Nets: 18,484

Pins: 71,246

Original HPWL: 891,732 µm

Optimized HPWL: 865,684 µm

Design area: 214,459 µm²

Utilization: 38%

\`\`\`

Detailed placement completed with zero overlaps, alignment problems, or
edge-spacing violations.

---

\## 4. Clock Tree Synthesis

CTS inserts and balances clock buffers so that the clock can physically
drive the thousands of sequential elements in the design while
controlling clock slew and skew.

\`\`\`bash

make cts \\

  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk

\`\`\`

CTS completed successfully.

---

\## 5. Routing

Routing creates the physical metal and via connections between the
placed cells.

\`\`\`bash

make route \\

  DESIGN_CONFIG=./designs/sky130hd/riscv_v3/config.mk

\`\`\`

The routed design contains approximately:

\`\`\`text

Components: 25,834

Nets: 18,478

Terminals: 303

\`\`\`

Routing consists of pin-access analysis, global routing, and detailed
routing while satisfying the Sky130 physical design rules.

---

\## 6. Post-Route Timing Analysis

After detailed routing, OpenROAD performs timing analysis using the
physically implemented clock and signal networks with extracted
interconnect parasitics.

This provides an important comparison with the standalone post-synthesis
OpenSTA analysis. Before physical implementation, the Bimodal design
reported severe timing violations dominated by high-fanout
pipeline-control signals:

``` text
Pre-layout OpenSTA @ 17 ns

WNS:        -52.87 ns
TNS:    -53,668.69 ns
```

After placement, buffering, cell sizing, clock-tree synthesis, detailed
routing, and RC extraction, the final physical implementation meets the
original 17 ns timing target:

``` text
Clock constraint:       17.00 ns
Target frequency:       58.82 MHz

WNS:                      0.00 ns
TNS:                      0.00 ns
Worst setup slack:       +5.90 ns
Setup violations:             0
Hold violations:              0

Reported min period:     11.10 ns
Reported Fmax:           90.12 MHz
```

The result demonstrates that the severe post-synthesis timing violations
were primarily associated with unoptimized high-fanout physical
distribution rather than an inherently long arithmetic datapath.
Physical buffering, placement, cell sizing, clock-tree synthesis, and
routing substantially improved the control distribution.

The 90.12 MHz value is OpenROAD's reported post-route minimum-period
estimate. The implementation itself was optimized and closed against a
17 ns (58.82 MHz) clock constraint. Therefore, 58.82 MHz is the
demonstrated implementation target, while 90.12 MHz represents reported
post-route timing margin rather than a separately closed 90 MHz
implementation.

### Post-Route Critical Path

![Post-route worst timing path](images/openroad/final_worst_path.png)

The highlighted path shows the physical placement and routing associated
with the final critical timing path after RC extraction.

------------------------------------------------------------------------

## 7. Final Physical Implementation

The completed Sky130HD implementation was exported to GDSII after
detailed routing, antenna repair, filler insertion, and final RC
extraction.

``` text
Design cell area:        226,415 µm²
Final utilization:             40%
Routed nets:                18,479
Antenna violations:              0
```

Detailed routing initially encountered 26,216 routing violations.
OpenROAD iteratively repaired the design, then performed antenna-diode
insertion and incremental rerouting until both detailed-routing and
antenna checks converged to zero violations.

The routed implementation contains approximately 1.17 m of interconnect
and about 176k vias.

### Final Layout

![Final physical layout](images/openroad/final_all.png)

Final Sky130HD physical implementation of the 2-way superscalar RV32I
core.

### Detailed Routing

![Final routing](images/openroad/final_routing.png)

Physical metal and via routing across the completed core.

### Clock Distribution

![Final clock distribution](images/openroad/final_clocks.png)

Clock distribution after clock-tree synthesis and physical
implementation.

### IR Drop

![Final IR-drop analysis](images/openroad/final_ir_drop.png)

OpenROAD's final power-grid analysis reported approximately 0.01%
worst-case voltage drop under the flow's analysis assumptions.

------------------------------------------------------------------------

## 8. Physical Verification

The final merged GDSII was checked using the Sky130
physical-verification flow.

``` text
Antenna violations:       0
KLayout DRC violations:   0
LVS:                      Netlists match
```

KLayout DRC completed with zero reported violations. LVS extracted the
final layout connectivity and successfully matched it against the
reference netlist.

The final GDSII is therefore timing-clean at the 17 ns implementation
target, antenna-clean, DRC-clean, and LVS-clean.

------------------------------------------------------------------------

# Results Summary

  -----------------------------------------------------------------------
  Metric         Gshare, Pre-Layout           Bimodal,           Bimodal,
                                            Pre-Layout         Post-Route
  -------------- ------------------ ------------------ ------------------
  Area                   0.2376 mm²         0.1841 mm²         0.2264 mm²
                                                         design-cell area

  WNS @ 17 ns             -96.07 ns          -52.87 ns            0.00 ns

  TNS                -386,257.78 ns      -53,668.69 ns            0.00 ns

  Reported min                   \-                 \-           11.10 ns
  period                                               

  Reported Fmax                  \-                 \-          90.12 MHz

  Setup                          \-                 \-                  0
  violations                                           

  Hold                           \-                 \-                  0
  violations                                           

  Antenna                        \-                 \-                  0
  violations                                           

  Final GDS DRC                  \-                 \-       0 violations

  LVS                            \-                 \-              Match

  Timing               Gshare PHT /   Pipeline-control         Physically
  bottleneck                 fanout             fanout      optimized and
                                                        timing-clean @ 17
                                                                       ns
  -----------------------------------------------------------------------

The pre-layout and post-route area values are not identical metrics: the
post-route value includes physical implementation changes such as
inserted clock and timing-repair cells. The post-route design was
optimized against a 17 ns clock constraint; the 90.12 MHz value is
OpenROAD's reported minimum-period estimate rather than a separately
implemented 90 MHz closure target.

------------------------------------------------------------------------

# Conclusions

The v3 implementation demonstrates why processor structures should be
evaluated using both architectural performance and physical
implementation cost.

Gshare provided better prediction on workloads with useful global branch
correlation, but Bimodal achieved higher IPC on four of five
representative applications while requiring substantially less hardware
in the evaluated standard-cell implementations. The 1024-entry Gshare
implementation consumed approximately 45.5% of total synthesized area
and generated severe high-fanout timing paths.

Switching to Bimodal reduced the standalone synthesized core area from
approximately 0.238 mm² to 0.184 mm² and shifted the dominant pre-layout
timing problem away from the predictor toward global pipeline-control
distribution.

The completed physical implementation shows that the severe timing
violations observed in standalone post-synthesis OpenSTA were not
representative of the physically optimized design. Placement, buffering,
cell sizing, clock-tree synthesis, and routing transformed the Bimodal
implementation from -52.87 ns WNS and -53.7 µs TNS before layout to zero
negative slack at the same 17 ns clock constraint.

The final Sky130HD implementation reports +5.90 ns worst setup slack at
the 17 ns target and an OpenROAD post-route minimum-period estimate of
11.10 ns (90.12 MHz). The final GDSII is antenna-clean, passes KLayout
DRC with zero reported violations, and passes LVS with matching
netlists.

These results also illustrate why post-synthesis timing alone can be
misleading for designs dominated by high-fanout control distribution.
Standalone OpenSTA exposed the structural problem, while physical
implementation demonstrated how much of that problem could be recovered
through actual placement and physical optimization.

Ultimately, superscalar performance must account for both IPC and
achievable clock frequency:

``` text
Instruction throughput ≈ IPC × clock frequency
```

For this implementation, the 17 ns (58.82 MHz) target is physically
closed, while the reported 11.10 ns minimum period provides a useful
estimate of remaining timing margin. A separate implementation run with
a tighter clock constraint would be required to claim physical closure
at approximately 90 MHz.
