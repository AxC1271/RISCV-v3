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

## Performance: IPC Comparison

---

## Design Challenges

### Challenge 1: Intra-Group Hazards

### Challenge 2: Register File Complexity

### Challenge 3: Data Forwarding Paths

### Challenge 4: Branch Misprediction

---

## Formal Verification (SVA)

---

## Timing Analysis (Sky130 Post-Synth)

---

## Repository Structure

---

## Build & Simulate

### Compile

### Run

---

Thanks for stopping by!