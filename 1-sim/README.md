# Simulation Infrastructure & IPC Analysis

This folder contains the testbench and validation infrastructure for the RV32I 2-way superscalar processor before synthesis and FPGA bring-up.

It is used for rapid iteration on pipeline behavior, hazard detection, instruction dispatch, forwarding, branch prediction, memory stalls, and performance characterization across multiple workloads without requiring Vivado or FPGA synthesis.

The simulation suite serves two purposes:

1. Compare the v3 2-way superscalar processor against the previous v2 scalar pipelined implementation using common workloads.
2. Characterize the effect of different branch predictors on IPC and control-flow performance.

---

## Testbenches & Workloads

The current simulation suite contains several workloads targeting different parts of the processor.

### Fibonacci — Branch and Dependency Workload

Exercises conditional branch prediction, loop behavior, data dependencies, forwarding, and misprediction recovery.

The loop contains dependent arithmetic instructions followed by a conditional branch, making prediction accuracy directly affect pipeline utilization and IPC.

This workload is particularly useful for comparing:

* Always Not Taken
* Bimodal
* Gshare

Fibonacci is also used as a common workload between the v2 scalar and v3 superscalar processors.

### Matrix 3×3 Multiply — ALU Workload

Exercises arithmetic throughput, instruction-level parallelism, and data dependencies.

The workload contains sequences of arithmetic operations that test the processor's ability to issue and retire multiple independent instructions while correctly handling dependent operations.

The current matrix workload contains no dynamic conditional branches, so branch predictor selection does not affect its execution.

Its primary purpose is therefore to provide a consistent arithmetic workload for comparing the v2 scalar processor against the v3 superscalar processor.

### Bubble Sort — Mixed Workload

Exercises arithmetic, memory operations, and pipeline dependencies.

The current benchmark is intentionally retained because the same workload was used for the v2 processor, providing a direct scalar-versus-superscalar IPC comparison.

However, the current version executes only one dynamic conditional branch. It therefore does not provide enough branch activity to meaningfully distinguish the branch predictors.

Additional branch-heavy workloads will be used separately for branch predictor characterization.

### Branch Predictor Stress Test

`tb_branch_predictor.sv` provides a synthetic workload designed specifically to exercise different branch behavior.

The test contains multiple controlled branch patterns, including repetitive and correlated behavior, allowing the Always Not Taken, bimodal, and gshare predictors to be compared independently of the application benchmarks.

Current stress-test results are considered preliminary because the testbench reaches its timeout after the intended workload completes. Predictor accuracy remains useful for characterization, but cycle count and IPC should not be treated as final until termination handling is corrected.

---

## Branch Predictors

The simulation processor contains three selectable branch predictors:

```text
predictor_sel = 00    Always Not Taken
predictor_sel = 01    Bimodal
predictor_sel = 10    Gshare
```

The predictor can be selected at simulation time with:

```bash
+pred=0    # Always Not Taken
+pred=1    # Bimodal
+pred=2    # Gshare
```

All predictors are tested using the same processor configuration and workload so that only the prediction strategy changes between runs.

### Always Not Taken

Provides the simplest prediction baseline.

Every conditional branch is predicted not taken.

### Bimodal

Uses a PC-indexed table of 2-bit saturating counters.

The predictor learns the recent taken/not-taken tendency of individual branch instructions.

### Gshare

Uses global branch history combined with the branch PC to index a pattern history table.

This allows the predictor to capture correlations between the outcomes of different branches rather than relying only on the behavior of an individual branch.

The simulation RTL retains all three predictors for comparison. A final implementation can retain only the selected production predictor for synthesis and physical implementation.

---

## Performance Metrics

Because the processor is 2-way superscalar, up to two instructions can retire during a single cycle.

The testbenches therefore count both writeback lanes:

```systemverilog
longint cycle_count, retire_count;

retire_count <= retire_count
              + ((dut.wb1_valid && !dut.wb1_ebreak) ? 1 : 0)
              + ((dut.wb2_valid && !dut.wb2_ebreak) ? 1 : 0);
```

IPC is calculated as:

```text
IPC = retired instructions / elapsed cycles
```

Unlike the previous single-issue processor, IPC is not inherently limited to 1.0.

The theoretical maximum retirement rate of the v3 design is:

```text
2 instructions / cycle
```

Dependencies, branches, memory operations, structural hazards, pipeline fill/drain, and misprediction recovery reduce the achieved IPC.

The terminating `ebreak` instruction is excluded because it is used to terminate simulation rather than perform workload computation.

Each simulation reports results in the form:

```text
cycles=XX retired=XX IPC=X.XXXX
```

---

## Branch Prediction Metrics

The testbenches additionally track conditional branch behavior:

```text
branches
mispredictions
prediction accuracy
```

Prediction accuracy is calculated as:

```text
accuracy = (branches - mispredictions) / branches
```

These statistics allow IPC changes to be correlated with predictor behavior rather than comparing IPC alone.

---

# Benchmark Results

## Fibonacci

Fibonacci currently provides the clearest application-level comparison between the three branch predictors.

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |   Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | ---------: |
| Always Not Taken |    151 |     148 | **0.9801** |       29 |             28 |  **3.45%** |
| Bimodal          |    101 |     149 | **1.4752** |       29 |              3 | **89.66%** |
| Gshare           |    121 |     149 | **1.2314** |       29 |             13 | **55.17%** |

All three configurations produce the expected Fibonacci result:

```text
fib(30) = 0x000CB228
```

### Analysis

The bimodal predictor performs particularly well on this workload because Fibonacci contains a highly repetitive loop branch.

Always Not Taken mispredicts almost every taken loop iteration, resulting in 28 mispredictions and an IPC of only `0.9801`.

Bimodal quickly learns that the loop branch is normally taken, reducing the number of mispredictions to 3 and increasing IPC to `1.4752`.

Gshare reaches `1.2314 IPC` with 13 mispredictions. For this short repetitive loop, global-history indexing provides less benefit than the simpler per-PC behavior captured by bimodal.

Relative to Always Not Taken:

```text
Bimodal IPC improvement ≈ 50.5%
Gshare IPC improvement  ≈ 25.6%
```

The slight difference in retired instruction count (`148` versus `149`) indicates that retirement accounting around termination/speculative instructions should be normalized before treating the retired counts as final architectural instruction counts.

The cycle counts and branch predictor statistics nevertheless demonstrate the performance impact of prediction on this workload.

---

## Matrix 3×3 Multiply

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: |
| Always Not Taken |     17 |      15 | **0.8824** |        0 |              0 |
| Bimodal          |     17 |      15 | **0.8824** |        0 |              0 |
| Gshare           |     17 |      15 | **0.8824** |        0 |              0 |

The current matrix benchmark executes no conditional branches, so all predictors produce identical results.

This makes Matrix unsuitable for predictor characterization but useful for measuring superscalar execution independently of branch prediction.

### v2 vs. v3

The previous v2 scalar pipelined processor achieved approximately:

```text
v2 Matrix IPC = 0.75
```

The v3 superscalar processor achieves:

```text
v3 Matrix IPC = 0.8824
```

This corresponds to an IPC improvement of approximately:

```text
+17.7%
```

Because the exact same workload is retained between processor generations, Matrix provides a useful scalar-versus-superscalar baseline.

---

## Bubble Sort

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions | Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | -------: |
| Always Not Taken |     19 |      19 | **1.0000** |        1 |              0 |     100% |
| Bimodal          |     19 |      19 | **1.0000** |        1 |              0 |     100% |
| Gshare           |     19 |      19 | **1.0000** |        1 |              0 |     100% |

All three predictor configurations produce identical performance.

The workload executes only one dynamic conditional branch, which is predicted correctly by all three predictors. As a result, this benchmark does not meaningfully differentiate predictor quality.

It remains useful because the same workload was used by the previous v2 processor.

### v2 vs. v3

The previous v2 scalar processor achieved approximately:

```text
v2 Bubble Sort IPC = 0.76
```

The v3 superscalar processor achieves:

```text
v3 Bubble Sort IPC = 1.0000
```

This corresponds to an IPC improvement of approximately:

```text
+31.6%
```

The benchmark is therefore retained primarily as a v2-to-v3 microarchitectural comparison rather than as a branch predictor benchmark.

---

# v2 vs. v3 IPC Comparison

The common workloads provide a direct comparison between the previous scalar pipelined processor and the current 2-way superscalar design.

| Workload    | v2 Scalar IPC | v3 Superscalar IPC | IPC Improvement |
| ----------- | ------------: | -----------------: | --------------: |
| Matrix 3×3  |          0.75 |         **0.8824** |      **+17.7%** |
| Bubble Sort |          0.76 |         **1.0000** |      **+31.6%** |

These results isolate the benefit of the superscalar microarchitecture using workloads retained from the previous processor generation.

Final architectural comparison should also consider maximum clock frequency after synthesis and timing closure.

A useful overall throughput metric is:

```text
Instruction throughput ≈ IPC × Fmax
```

This captures the tradeoff between higher IPC and any clock-frequency reduction caused by the additional superscalar dispatch, forwarding, hazard detection, and execution logic.

---

# Branch Predictor Stress Test

A dedicated synthetic branch workload is used to exercise patterns that are not present in the small application benchmarks.

Current results:

| Predictor        | Branches | Mispredictions |   Accuracy |
| ---------------- | -------: | -------------: | ---------: |
| Always Not Taken |      480 |            349 | **27.29%** |
| Bimodal          |      480 |            137 | **71.46%** |
| Gshare           |      480 |             54 | **88.75%** |

The raw runs also currently report:

| Predictor        | Cycles | Retired | Raw IPC |
| ---------------- | -----: | ------: | ------: |
| Always Not Taken |   1619 |     995 |  0.6146 |
| Bimodal          |   1195 |     995 |  0.8326 |
| Gshare           |   1029 |     995 |  0.9670 |

However, these IPC values are **not considered final benchmark results**.

The current stress test reaches the testbench timeout after the intended branch workload completes, allowing additional instructions to execute before simulation terminates.

The branch accuracy results are therefore retained as preliminary predictor characterization, while cycle and IPC measurements should be rerun after fixing termination handling.

The stress test demonstrates a different predictor behavior from Fibonacci:

```text
Fibonacci
Bimodal accuracy = 89.66%
Gshare accuracy  = 55.17%

Predictor Stress Test
Bimodal accuracy = 71.46%
Gshare accuracy  = 88.75%
```

This illustrates why predictor performance should be evaluated across multiple branch patterns rather than using a single workload.

---

# Current Predictor Comparison

The current results can be summarized as:

| Workload            | Always NT |    Bimodal |     Gshare | Predictor Relevance |
| ------------------- | --------: | ---------: | ---------: | ------------------- |
| Fibonacci IPC       |    0.9801 | **1.4752** |     1.2314 | High                |
| Matrix IPC          |    0.8824 |     0.8824 |     0.8824 | None                |
| Bubble Sort IPC     |    1.0000 |     1.0000 |     1.0000 | Very Low            |
| BP Stress Accuracy* |    27.29% |     71.46% | **88.75%** | High                |

`*` Preliminary until the branch predictor stress-test termination issue is corrected.

Matrix and Bubble Sort are retained because they provide direct v2-to-v3 IPC baselines. Additional branch-intensive application workloads will be added to provide more realistic branch predictor comparisons.

---

## Memory Latency

The testbenches support configurable simulated memory latency through the `+lat` argument.

For example:

```bash
+lat=1
+lat=2
+lat=3
```

This can be used to observe how memory latency affects superscalar utilization and IPC.

When comparing branch predictors, the same memory latency should be used for all predictor configurations.

---

# Compile Source Code

To compile a SystemVerilog testbench using Icarus Verilog:

```bash
iverilog -g2012 -I ../0-rtl \
    -o fib_sim \
    tb_fib.sv \
    ../0-rtl/core_riscv_superscalar.sv \
    ../0-rtl/*.sv
```

A file list can also be used to keep the compilation command manageable.

For example:

```bash
cat > files.txt << 'EOF'
tb_fib.sv
../0-rtl/core_riscv_superscalar.sv
../0-rtl/alu.sv
../0-rtl/branch_unit.sv
../0-rtl/control_unit.sv
../0-rtl/dispatch_unit.sv
../0-rtl/exmem_stage.sv
../0-rtl/forward_unit.sv
../0-rtl/hazard_unit.sv
../0-rtl/idex_stage.sv
../0-rtl/ifid_stage.sv
../0-rtl/immediate_generator.sv
../0-rtl/memwb_stage.sv
../0-rtl/program_counter.sv
../0-rtl/register_file.sv
../0-rtl/nt_predictor.sv
../0-rtl/bimodal_predictor.sv
../0-rtl/gshare_predictor.sv
EOF

iverilog -g2012 -o fib_sim -c files.txt
```

This generates an Icarus Verilog simulation executable.

---

# Run Simulation

Run Fibonacci with each predictor:

```bash
vvp fib_sim +pred=0
vvp fib_sim +pred=1
vvp fib_sim +pred=2
```

Matrix:

```bash
vvp matrix_sim +pred=0
vvp matrix_sim +pred=1
vvp matrix_sim +pred=2
```

Bubble Sort:

```bash
vvp bubblesort_sim +pred=0
vvp bubblesort_sim +pred=1
vvp bubblesort_sim +pred=2
```

Branch predictor stress test:

```bash
vvp bp_sim +pred=0
vvp bp_sim +pred=1
vvp bp_sim +pred=2
```

Memory latency can be specified simultaneously:

```bash
vvp fib_sim +pred=2 +lat=2
```

---

# Performance Analysis

The simulation infrastructure characterizes several architectural effects on IPC:

* 2-way instruction issue and retirement
* RAW and WAW dependencies
* Forwarding
* Load-use hazards
* Memory-port serialization
* Memory latency
* Control-flow serialization
* Branch misprediction recovery
* Branch predictor accuracy
* Pipeline stalls and flushes

The existing Matrix and Bubble Sort workloads provide continuity with the previous v2 scalar processor and allow direct comparison of IPC between processor generations.

Fibonacci and the dedicated predictor stress test demonstrate that branch predictor effectiveness depends strongly on workload behavior.

Future branch-intensive application workloads will complement the synthetic predictor stress test and provide more realistic characterization of bimodal and gshare prediction.

After predictor characterization is complete, the simulation-only predictor selection logic can be removed and the desired production predictor retained for synthesis and physical implementation.
