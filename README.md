# RV32I 2-Way Superscalar Processor with Branch Prediction

A 2-way in-order superscalar RISC-V processor designed to explore instruction-level parallelism, data forwarding, and branch prediction. This project builds on my previous single-issue RV32I processor and focuses on both the performance potential and the additional architectural complexity introduced by widening the pipeline.

## Motivation: Breaking the Single-Issue IPC Ceiling

**The problem with a 1-way pipeline:**

From my previous RISC-V v2 processor, I measured approximately:

```text
Single-issue baseline (RISC-V v2):

Fibonacci:   IPC = 0.64
Matrix:      IPC = 0.75
Bubble Sort: IPC = 0.76

Theoretical maximum IPC: 1.0
```

Even with effective forwarding and hazard detection, a single-issue processor fundamentally cannot retire more than one instruction per cycle.

To push beyond that limit, this project introduces:

* **2-wide instruction fetch**
* **2-way in-order issue**
* **Two parallel integer execution lanes**
* **Two writeback paths**
* **Data forwarding**
* **Dynamic branch prediction**

The theoretical peak retirement rate therefore increases from **1 IPC to 2 IPC**.

A dedicated independent-ALU throughput benchmark demonstrates this directly: the processor sustains approximately **1.85 IPC** when given a stream with sufficient instruction-level parallelism.

The remaining gap between 1.85 and the theoretical 2.0 IPC comes primarily from pipeline fill/drain effects and other implementation overhead. Real workloads achieve lower IPC because dependencies, branches, memory operations, and structural hazards reduce the number of instructions that can execute in parallel.

---

## Architecture Overview

### Core Design

**ISA:** RV32I

**Execution:** 2-way in-order superscalar

**Fetch Width:** 2 instructions/cycle

**Maximum Retirement:** 2 instructions/cycle

**Execution Units:** 2 integer ALU lanes

**Memory Architecture:** Harvard instruction/data interfaces

**Data Memory Ports:** 1

**Branch Resolution:** EX stage

**Register File:** 2 writeback paths

**Branch Prediction:** Always-Not-Taken, Bimodal, or Gshare

The processor fetches two adjacent instructions and attempts to dispatch both during the same cycle.

When the instructions are independent and no structural hazard exists, both can proceed through the pipeline in parallel.

When the second instruction cannot safely execute alongside the first, the older instruction is issued first and the younger instruction is replayed.

This preserves in-order architectural behavior while still allowing independent instruction pairs to exploit superscalar execution.

---

# Branch Prediction

Branch prediction becomes increasingly important as the processor gets wider.

In a single-issue pipeline, every incorrectly predicted path wastes instructions fetched and executed behind the branch. With two-wide fetch, more speculative work can exist behind a branch, increasing the cost of choosing the wrong path.

To explore this effect, the processor implements three selectable prediction schemes:

```text
predictor_sel = 00    Always Not Taken
predictor_sel = 01    Bimodal
predictor_sel = 10    Gshare
```

During simulation, the predictor can be selected with:

```bash
+pred=0    # Always Not Taken
+pred=1    # Bimodal
+pred=2    # Gshare
```

This allows the same processor and workload to be executed with different predictors while keeping the rest of the architecture unchanged.

## Always Not Taken

The simplest predictor assumes that every conditional branch will fall through.

Consider:

```asm
addi x1, x0, 0
addi x2, x0, 100

LOOP:
    addi x1, x1, 1
    bne  x1, x2, LOOP
```

The loop branch is taken for almost every iteration.

An Always-Not-Taken predictor therefore repeatedly fetches from the fall-through path, only to discover when the branch reaches EX that execution should have continued at `LOOP`.

The incorrect younger instructions must then be flushed and fetching redirected to the branch target.

Always-Not-Taken has essentially no predictor-table storage cost and provides a useful baseline, but it performs poorly on strongly taken loops.

---

## 2-Bit Bimodal Predictor

The bimodal predictor improves on the static predictor by maintaining a table of **2-bit saturating counters** indexed using bits from the branch PC.

Each entry has four states:

```text
00    Strongly Not Taken
01    Weakly Not Taken
10    Weakly Taken
11    Strongly Taken
```

The most significant bit determines the prediction.

When a branch resolves as taken, its counter moves toward `11`. When it resolves as not taken, the counter moves toward `00`.

For example:

```text
Weakly Taken + Taken
        |
        v
Strongly Taken
```

A single unusual branch outcome therefore does not immediately reverse a well-trained prediction.

This works particularly well for loops. After only a small amount of training, a repeatedly taken loop branch becomes strongly taken and remains predicted taken until the loop exits.

The limitation is that prediction is based primarily on the behavior associated with that branch PC. It cannot directly exploit relationships between the outcomes of different recent branches.

---

## Gshare Branch Predictor

Gshare extends dynamic prediction by incorporating **global branch history**.

The implementation maintains a 10-bit Global History Register:

```text
GHR = {outcome[n-9], ..., outcome[n]}
```

where each bit records whether a recently resolved branch was taken or not taken.

The Pattern History Table is indexed by XORing branch-PC bits with the global history:

```text
index = PC[11:2] XOR GHR
```

The resulting index selects a 2-bit saturating counter from a 1024-entry Pattern History Table. This allows the same static branch to receive different predictions depending on the outcomes of recently executed branches.

That makes Gshare capable of learning **correlated branch behavior** that a simple PC-indexed bimodal predictor cannot represent as effectively.

The tradeoff is additional state and a longer training period. On very short loops, global history can also spread updates across multiple PHT entries, meaning Gshare is not guaranteed to outperform bimodal on every individual workload.

---

# Performance

## Peak Superscalar Throughput

A dedicated IPC benchmark executes a long stream of independent integer instructions.

The workload intentionally removes most dependencies, branches, and memory operations so that the processor's 2-way issue capability can be measured directly.

Measured performance was approximately:

```text
cycles              = 65
benchmark instr     = 120
IPC                 ≈ 1.85

dual issue cycles   = 64
single issue cycles = 1
stall cycles        = 0
replay cycles       = 0
flush cycles        = 0
```

This is an important result because it demonstrates that the core is not merely structurally two-wide: when sufficient instruction-level parallelism exists, it can sustain execution close to its theoretical **2 IPC** limit.

---

## Fibonacci

Fibonacci is deliberately dependency-heavy:

```asm
add  x4, x1, x2
addi x1, x2, 0
addi x2, x4, 0
addi x3, x3, -1
bne  x3, x0, LOOP
```

The workload contains both RAW dependencies and a repeatedly executed loop branch.

After implementing forwarding, a Gshare run produced:

```text
cycles       = 121
retired      = 149
IPC          = 1.2314

branches     = 29
mispredicts  = 13
accuracy     = 55.17%
```

Before the forwarding changes, the same Gshare Fibonacci workload required approximately:

```text
cycles = 239
IPC    = 0.6234
```

The branch statistics remained essentially unchanged.

This is useful because it isolates the effect of the forwarding network: the large performance improvement came from eliminating unnecessary data-hazard stalls rather than from improved branch prediction.

The benchmark also demonstrates an interesting predictor characteristic. Bimodal performed particularly well on this short, repetitive loop because a single PC-indexed counter can quickly learn its strongly taken behavior. Gshare must train multiple history-dependent PHT entries and therefore does not necessarily outperform bimodal on a simple loop.

---

## Additional Workloads

The simulation suite also contains:

```text
tb_core.sv
    Directed functional regression for pipeline correctness.

tb_ipc.sv
    Independent instruction stream used to measure peak 2-way throughput.

tb_fib.sv
    Dependency-heavy arithmetic and loop-branch workload.

tb_bubblesort.sv
    Mixed memory, comparison, dependency, and branch workload.

tb_matrix.sv
    Arithmetic-oriented workload.

tb_branch_predictor.sv
    Dedicated branch-pattern stress test for predictor characterization.
```

Together, these workloads separate different sources of performance loss rather than relying on a single IPC measurement.

---

# Design Challenges

## Challenge 1: Intra-Group Hazards

Fetching two instructions creates hazards that do not exist in the same form in a single-issue pipeline.

Consider a WAW dependency:

```asm
addi x1, x0, 10
add  x1, x5, x6
```

Both instructions want to write `x1`.

The processor cannot allow the younger instruction to violate program order. The older instruction is therefore issued first while the younger instruction is serialized and replayed.

A RAW dependency creates a similar problem:

```asm
add x5, x1, x2
sub x6, x5, x4
```

The younger `sub` requires the value of `x5` produced by the older `add`.

Because both instructions were fetched as the same pair, that result does not yet exist when dispatch occurs. The pair therefore cannot safely execute simultaneously.

The processor issues the older instruction and replays the younger one on the following opportunity.

This differs from a normal pipeline RAW dependency, where forwarding can often supply a value from a later pipeline stage without stalling.

---

## Challenge 2: Register File Complexity

A two-way processor places substantially more pressure on the register file.

Two instructions may need to read operands simultaneously, while two older instructions may also reach writeback in the same cycle.

The processor therefore has to support the operand bandwidth required by both execution lanes while preserving architectural ordering.

Writeback also requires careful handling when both lanes target registers during the same cycle.

The register file remains architecturally identical to RV32I — including the requirement that `x0` always reads as zero — but the amount of simultaneous access increases significantly compared with the single-issue design.

---

## Challenge 3: Data Forwarding Paths

Widening the processor also widens the forwarding problem.

In a single-issue pipeline, an EX-stage instruction generally needs to compare its source registers against one older instruction in each later pipeline stage.

With two execution lanes, an instruction may depend on results produced by either older lane.

The forwarding unit therefore considers multiple possible sources:

```text
Original register value
WB lane 1
WB lane 2
MEM lane 1
MEM lane 2
```

with newer pipeline results taking priority over older ones when appropriate.

Forwarding is applied not only to ALU operands, but also to values used by:

* Branch comparisons
* JALR target generation
* Store data

Loads require special treatment. During MEM, the ALU result associated with a load is its address rather than the loaded value itself. A dependent instruction therefore cannot incorrectly forward that address as register data.

A true load-use dependency still requires a bubble until the loaded value becomes available.

After implementing this forwarding network, the main functional regression improved from approximately:

```text
58 cycles -> 41 cycles
```

for the same instruction sequence.

This illustrates how much performance can be lost when a superscalar processor conservatively stalls dependencies that could instead be resolved through bypassing.

---

## Challenge 4: Branch Misprediction Recovery

A superscalar frontend can have multiple younger instructions in flight behind a branch.

When a branch resolves differently from its prediction, those instructions belong to the wrong architectural path and must not modify processor state.

The processor therefore:

1. Detects the misprediction when the branch resolves.
2. Computes the correct next PC.
3. Flushes younger incorrect instructions.
4. Redirects instruction fetch.
5. Updates the selected predictor.

Correctness is more important than preserving throughput during this event. No wrong-path register or memory operation may be allowed to become architecturally visible.

The performance goal of the branch predictors is therefore not to eliminate the recovery mechanism, but to reduce how often it is required.

---

# Verification

Verification is divided into directed simulation and formal properties.

## Directed Simulation

`tb_core.sv` exercises individual architectural behaviors including arithmetic instructions, hazards, forwarding, branches, memory operations, and superscalar execution.

The current functional regression completes all directed checks successfully:

```text
PASS: 32
FAIL: 0

cycles  = 41
retired = 37
IPC     = 0.9024
```

Separate workload testbenches are then used for performance characterization rather than basic instruction correctness.

This distinction is important: high IPC is meaningless if architectural state is incorrect.

## Formal Verification (SVA)

The formal verification directory is intended to verify architectural invariants that should hold regardless of the exact instruction sequence.

Properties of interest include:

* `x0` always remains zero
* Invalid pipeline entries cannot commit register writes
* Invalid instructions cannot perform memory writes
* A pipeline flush prevents wrong-path instructions from committing
* Register writes occur only for valid destination registers
* In-order architectural behavior is preserved
* Hazard logic prevents unresolved dependencies from executing incorrectly

These properties complement directed simulation by checking invariants across instruction combinations that would be impractical to enumerate manually.

---

# Timing Analysis

Post-synthesis timing analysis is performed separately from functional simulation.

The `/3-sta/` flow is intended to use Yosys/OpenSTA with a Sky130 standard-cell library to determine:

* Critical-path delay
* Maximum clock frequency
* Setup timing
* Combinational paths introduced by superscalar dispatch
* Forwarding-network timing
* Branch-prediction timing

This is particularly important for a superscalar design because improving IPC can increase combinational complexity.

A processor that achieves higher IPC but requires a substantially slower clock may not achieve higher absolute instruction throughput.

For that reason, the final architectural evaluation should consider both:

```text
IPC
```

and:

```text
Instructions/second = IPC × clock frequency
```

---

# Repository Structure

```text
/0-rtl/    - SystemVerilog implementation of the processor

/1-sim/    - directed tests, workloads, and IPC/predictor benchmarks

/2-formal/ - SystemVerilog assertions and SymbiYosys scripts

/3-sta/    - Yosys/OpenSTA static timing analysis
```

---

# Build & Simulate

## Compile

I use Icarus Verilog for RTL simulation.

For example:

```bash
iverilog -g2012 -I ../0-rtl \
    -o fib_sim \
    tb_fib.sv \
    ../0-rtl/core_riscv_superscalar.sv \
    ../0-rtl/*.sv
```

A file list can also be used:

```bash
iverilog -g2012 -o fib_sim -c files.txt
```

## Run

Select the desired predictor using a plusarg:

```bash
vvp fib_sim +pred=0
vvp fib_sim +pred=1
vvp fib_sim +pred=2
```

where:

```text
0 = Always Not Taken
1 = Bimodal
2 = Gshare
```

Other workload executables can be run in the same way:

```bash
vvp bubblesort_sim +pred=2
vvp matrix_sim +pred=2
vvp ipc_sim
```

A typical benchmark reports:

```text
cycles=121 retired=149 IPC=1.2314
predictor=2 branches=29 mispredicts=13 accuracy=55.17%
```

---

# Performance Analysis

The goal of the project is not simply to maximize one benchmark's IPC, but to understand **why** the achieved IPC changes.

The simulation infrastructure measures the effects of:

* Instruction-level parallelism
* 2-way issue and retirement
* RAW and WAW dependencies
* Load-use hazards
* Forwarding
* Single-port data-memory serialization
* Control-flow serialization
* Branch misprediction
* Predictor training behavior
* Pipeline stalls and flushes

The independent instruction benchmark demonstrates the performance ceiling of the architecture at approximately **1.85 IPC**.

Real workloads then show how dependencies, memory traffic, and control flow move execution away from that ideal.

This makes the project both an implementation of a 2-way superscalar RV32I processor and an exploration of the architectural tradeoffs required to move beyond the single-issue IPC ceiling.

---

Thanks for stopping by!