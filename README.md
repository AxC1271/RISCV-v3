# RV32I 2-Way Superscalar Processor with Branch Prediction

A high-performance in-order superscalar RISC-V processor targeting instruction-level parallelism and branch prediction accuracy. Explores the fundamental IPC ceiling of single-issue pipelines and the architectural/verification challenges of going wide.

## Motivation: Breaking the Single-Issue IPC Ceiling

**The problem with 1-way pipelines:**

From my original RISC-V v2, we derived the following values:

```
Single-issue baseline (RISCV-v2):
Fibonacci: IPC = 0.64 (branch misprediction dominates)
Matrix: IPC = 0.75 (data forwarding effective)
Bubble Sort: IPC = 0.76 (load-use stalls moderate)

Theoretical maximum IPC (1-way): 1.0
```

Even with perfect hazard detection and forwarding, a 1-way pipeline **cannot exceed 1 instruction per cycle**. Achieving better throughput requires:
- **Wider fetch** (2+ instructions/cycle)
- **Parallel execution** (2+ ALUs)
- **Smarter branch prediction** (reduce misprediction penalty)

This project explores all three, while documenting the verification and design complexity that comes with superscalar execution.

## Architecture Overview

### Core Design (2-Way In-Order Superscalar)

**ISA:** RV32I (no caches; tight-coupled BRAM)  
**Issue Width:** 2 instructions/cycle (in-order)  
**Memory:** Harvard, 1-cycle latency

## Branch Predictors

Since we are now fetching 2 instructions instead of one, a branch prediction becomes twice as expensive compared to a one-way pipeline. Instead of squashing two instructions on a mispredict, we have to squash `4`. That's why for this project, I want to explore three different branch predictors and quantitatively measure their accuracy and IPC impact.

### Always Not Taken Predictor

This is the default option and was the predictor chosen for the preceding RISC-V v2. The processor treats the branch instruction as any other instruction and speculatively fetches the two consecutive instructions (curr_pc + 4 and curr_pc + 8), thus believing the branch isn't taken. Sometimes, the branch isn't taken, and we're able to continue executing as expected. However, on a mispredict, the `IF` and `ID` stages have to be flushed (since we are on the wrong path), and we have to incur a 2-cycle penalty. On a code block like:

```s
main:
    addi x1, x0, 0
    addi x2, x0, 100
    blt  x1, x2, LOOP

LOOP:
    addi x1, x1, 1
    bne  x1, x2, LOOP 
```

Here you would incur the 2-cycle penalty on **EVERY** single iteration up until x1 is 100. This is a really simple example, but it goes to show that there are certain workloads that can be extremely hostile to this branch predictor scheme.

**Verdict:** Simple, zero area cost. But loop-heavy and branch-intensive workloads are hostile to this approach. No prediction at all on Fibonacci achieves only 0.64 IPC; this predictor is why.

### 2-bit Saturating Counter

### Gshare Branch Predictor 

---

## Performance: IPC Comparison

---

## Design Challenges

### Challenge 1: Intra-Group Hazards

Let's say you fetch two instructions. An intra-group hazard can either
consist of a WAW or a RAW hazard. Let's say I fetched these two instructions
at the same time:

```s
addi x1, x0, 10
add  x1, x5, x6
```

You have a WAW hazard here, where both instructions write to the same register, x1. In program order, the most recent write would be the younger instruction so we should have that commit later. Therefore, we should always let the first (and older) instruction commit. So x1 = x0 + 10 would first commit before being overwritten by x1 = x5 + x6, which is intended behavior here.

```s
add x5, x1, x2
mul x6, x5, x4
```

Here we have the typical RAW hazard, but it's embedded in the pair of instructions that we just fetched together at the same time. The `mul` instruction needs the result of x5 from the previous `add` instruction, so it needs to stall. Same deal, we still issue the first instruction and forward the result of that to the second instruction. Notice the RAW doesn't really apply in the reverse, since the `add` instruction wouldn't see any new committed values from the younger `mul` instruction.

### Challenge 2: Register File Complexity

### Challenge 3: Data Forwarding Paths

### Challenge 4: Branch Misprediction

---

## Formal Verification (SVA)

There's two steps to verifying the correctness of this processor. First of all, I would be using directed testbenches to stress the core through different types of workloads

---

## Timing Analysis (Sky130 Post-Synth)

---

## Repository Structure

```
/0-rtl/    - pure Verilog implementation of the processor
/1-sim/    - testbenches for different workloads / IPC comparison
/2-formal/ - SystemVerilog assertions + SymbiYosys scripts 
/3-sta/    - static timing analysis with yosys/opensta/tcl scripts
/4-images/ - visual illustrations to better explain certain concepts
```

---

## Build & Simulate

### Compile

Just like what I did with the v2, I will be using `Icarus Verilog` to simulate the processor. For reference, the scripts I'll be running are:

```bash
iverilog -g2012 -I ../0-rtl -o fib_sim tb_fib.sv ../0-rtl/core_riscv.sv ../0-rtl/alu.sv ...
```

Or what I did for this project to smooth the iteration process:

```bash
cat > files.txt << 'EOF'
tb_fib.sv
../0-rtl/core_riscv.sv
../0-rtl/alu.sv
../0-rtl/control_unit.sv
... (all RTL files)
EOF

iverilog -g2012 -o fib_sim -c files.txt
```

### Run

To run the executable, just run the following:

```bash
vvp fib_sim
```

An example output could be:

```
[TB-FIB] Fibonacci(30) benchmark starting...
[TB-FIB] EBREAK retired at T=195000

========== IPC (Fibonacci) ==========
cycles=14  retired=9  IPC=0.6429
Result in x2: 0x00000005 (should be fib(30))
tb_fib.sv:141: $finish called at 235000 (1ps)
```

---

Thanks for stopping by!