# Simulation Infrastructure & IPC Analysis

This folder contains the testbench and validation infrastructure for the RV32I 2-way superscalar processor before synthesis/FPGA bring-up. It is used for rapid iteration on pipeline behavior, hazard detection, instruction dispatch, branch prediction, memory stalls, and performance characterization across multiple workloads without requiring Vivado or FPGA synthesis.

---

## Testbenches & Workloads

Three workloads are used to exercise different aspects of the superscalar pipeline and compare the performance of the supported branch predictors.

### Fibonacci — Branch-Heavy

Exercises conditional branch prediction, loop behavior, and misprediction recovery.

The loop contains arithmetic instructions followed by a conditional branch, creating a workload where branch prediction accuracy directly affects pipeline utilization and IPC.

This workload is useful for comparing:

* Always Not Taken
* Bimodal
* Gshare

### Matrix 3×3 Multiply — ALU-Heavy

Exercises arithmetic throughput, instruction-level parallelism, and data dependencies.

The workload contains sequences of arithmetic operations that test the processor's ability to issue and retire multiple independent instructions while correctly handling dependent operations.

This workload is primarily useful for measuring the benefits and limitations of 2-way superscalar execution when branch behavior is not the dominant performance bottleneck.

### Bubble Sort — Memory and Branch Heavy

Exercises memory accesses, load-use dependencies, conditional branches, and mixed control flow.

Bubble sort combines loads, stores, comparisons, and loop branches, stressing several parts of the processor simultaneously. It provides a workload where both memory stalls and branch prediction can affect overall IPC.

---

## Branch Predictors

The processor contains three branch predictors for simulation and performance comparison:

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

All predictors are tested using the same processor configuration and workload so that only the branch prediction strategy changes between runs.

The Always Not Taken predictor provides a simple baseline. The bimodal predictor uses PC-indexed 2-bit saturating counters, while gshare combines the branch PC with global branch history when indexing its pattern history table.

The final synthesized processor can use only the selected production predictor while the additional predictors remain useful for simulation and IPC comparison.

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

Unlike the previous single-issue processor, IPC is not inherently limited to 1.0. The theoretical maximum retirement rate of the 2-way design is 2 instructions per cycle, although dependencies, branches, memory operations, and pipeline stalls reduce the achieved IPC.

The terminating `ebreak` instruction is excluded from the retired instruction count because it is used to terminate the simulation rather than perform workload computation.

Each simulation reports results in the form:

```text
cycles=XX retired=XX IPC=X.XXXX
```

---

## Branch Prediction Metrics

In addition to IPC, the testbenches track conditional branch behavior:

```text
branches
mispredictions
prediction accuracy
```

Prediction accuracy is calculated as:

```text
accuracy = (branches - mispredictions) / branches
```

A simulation therefore produces statistics similar to:

```text
cycles=120 retired=173 IPC=1.4417
predictor=2 branches=24 mispredicts=3 accuracy=87.50%
```

These statistics make it possible to relate changes in IPC to branch predictor behavior rather than comparing IPC alone.

---

## Predictor Comparison

Each workload should be executed once with each predictor:

```text
                         Always NT       Bimodal       Gshare
Fibonacci                    X              X             X
Matrix Multiply              X              X             X
Bubble Sort                  X              X             X
```

This produces nine primary benchmark runs.

For each run, record:

```text
Cycles
Retired Instructions
IPC
Conditional Branches
Mispredictions
Prediction Accuracy
```

The same workload, memory latency, processor configuration, and initial state should be maintained between predictor runs so that `predictor_sel` is the independent variable.

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

## Compile Source Code

To compile a SystemVerilog testbench using Icarus Verilog:

**Single workload:**

```bash
iverilog -g2012 -I ../0-rtl -o fib_sim tb_fib.sv ../0-rtl/core_riscv_superscalar.sv ../0-rtl/*.sv
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

## Run Simulation

Run a workload by selecting the desired predictor:

```bash
vvp fib_sim +pred=0
vvp fib_sim +pred=1
vvp fib_sim +pred=2
```

The same process can be used for the other workloads:

```bash
vvp matrix_sim +pred=0
vvp matrix_sim +pred=1
vvp matrix_sim +pred=2

vvp bubblesort_sim +pred=0
vvp bubblesort_sim +pred=1
vvp bubblesort_sim +pred=2
```

Memory latency can be specified at the same time:

```bash
vvp fib_sim +pred=2 +lat=2
```

---

## Performance Analysis

The simulation infrastructure is intended to characterize how different architectural effects influence IPC, including:

* 2-way instruction issue and retirement
* RAW and WAW dependencies
* Load-use hazards
* Memory-port serialization
* Memory latency
* Control-flow serialization
* Branch misprediction recovery
* Branch predictor accuracy
* Pipeline stalls and flushes

The predictor comparison specifically evaluates how Always Not Taken, bimodal, and gshare prediction affect execution time and IPC across workloads with different instruction and branch behavior.

After predictor characterization is complete, the simulation-only predictor selection logic can be removed and the desired predictor can be retained for synthesis and FPGA implementation.
