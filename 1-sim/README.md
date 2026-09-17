# Simulation Infrastructure & IPC Analysis

This folder contains the testbench and validation infrastructure for the RV32I 2-way superscalar processor before synthesis and FPGA bring-up.

It is used for rapid iteration on pipeline behavior, hazard detection, instruction dispatch, forwarding, branch prediction, memory stalls, and performance characterization across multiple workloads without requiring Vivado or FPGA synthesis.

The simulation suite serves three main purposes:

1. Compare the v3 2-way superscalar processor against the previous v2 scalar pipelined implementation using common workloads.
2. Characterize how different workloads affect IPC and pipeline utilization.
3. Compare Always Not Taken, Bimodal, and Gshare branch prediction across workloads with very different control-flow behavior.

One of the more interesting results from this testing is that the more sophisticated predictor is not necessarily the best predictor for every workload.

Gshare can exploit correlations between recent branch outcomes, but that additional information only helps when useful global correlation actually exists. Across most of the application workloads tested so far, the simpler Bimodal predictor achieves higher prediction accuracy and IPC. String Search provides an important counterexample where Gshare is able to use branch-history correlation effectively and outperform Bimodal.

This makes predictor selection an architectural tradeoff rather than simply choosing the most complex predictor.

---

# Testbenches & Workloads

The simulation suite contains workloads targeting different parts of the processor.

The goal is not just to report a single IPC number. Different programs expose different limits on superscalar performance, including instruction-level parallelism, dependencies, memory operations, branch frequency, and branch predictability.

## Fibonacci — Branch and Dependency Workload

Exercises conditional branch prediction, loop behavior, data dependencies, forwarding, and misprediction recovery.

The loop contains dependent arithmetic instructions followed by a highly repetitive conditional branch, making prediction accuracy directly affect pipeline utilization and IPC.

Fibonacci is particularly useful for comparing:

* Always Not Taken
* Bimodal
* Gshare

The loop branch is strongly biased toward taken, which makes it a good example of a workload where a simple per-PC predictor performs extremely well.

Fibonacci is also retained as a common workload between the v2 scalar and v3 superscalar processors.

---

## Matrix 3×3 Multiply — ALU Workload

Exercises arithmetic throughput, instruction-level parallelism, and data dependencies.

The workload contains sequences of arithmetic operations that test the processor's ability to issue and retire multiple independent instructions while correctly handling dependent operations.

The current matrix workload contains no dynamic conditional branches, so branch predictor selection does not affect its execution.

Its primary purpose is therefore to provide a consistent arithmetic workload for comparing the v2 scalar processor against the v3 superscalar processor.

---

## Bubble Sort — v2/v3 Baseline

Exercises arithmetic, memory operations, and pipeline dependencies.

The current benchmark is intentionally retained because the exact same workload was used for the v2 processor, providing a direct scalar-versus-superscalar IPC comparison.

The current version executes only one dynamic conditional branch, so it does not contain enough branch activity to meaningfully distinguish the predictors.

It is therefore primarily a v2-to-v3 architectural comparison rather than a branch predictor benchmark.

### C Reference Implementation

```c
void bubble_sort(int *a, int n)
{
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (a[j] > a[j + 1]) {
                int temp = a[j];
                a[j] = a[j + 1];
                a[j + 1] = temp;
            }
        }
    }
}
```

The C code is included as a reference for the algorithm represented by the benchmark. The simulation workload itself is implemented directly in RV32I instructions.

---

## Insertion Sort — Branch, Memory, and Dependency Workload

Insertion Sort provides a more branch-intensive sorting workload than the original Bubble Sort baseline.

The benchmark sorts 16 integers initialized in reverse order:

```text
16 15 14 13 12 ... 3 2 1
```

Reverse ordering intentionally causes significant activity in the inner insertion loop.

This workload exercises:

* conditional branches
* nested loop behavior
* loads and stores
* RAW dependencies
* forwarding
* load-use hazards
* branch prediction
* superscalar issue opportunities

### C Reference Implementation

```c
#define N 16

void insertion_sort(int a[N])
{
    for (int i = 1; i < N; i++) {
        int key = a[i];
        int j = i - 1;

        while (j >= 0 && a[j] > key) {
            a[j + 1] = a[j];
            j--;
        }

        a[j + 1] = key;
    }
}
```

---

## Binary Search — Data-Dependent Control Flow

Binary Search introduces control flow that depends directly on the search key and array contents.

The benchmark searches a sorted 32-element array:

```text
0, 2, 4, 6, ... , 62
```

using a mixture of successful and unsuccessful search keys.

Unlike Fibonacci, the important branch outcomes are not dominated by a single repetitive loop direction. Whether the search moves left or right depends on the current key and midpoint.

This makes Binary Search useful for evaluating predictors on irregular data-dependent control flow.

### C Reference Implementation

```c
int binary_search(const int *a, int n, int key)
{
    int low = 0;
    int high = n - 1;

    while (low <= high) {
        int mid = (low + high) >> 1;

        if (a[mid] == key)
            return mid;

        if (a[mid] < key)
            low = mid + 1;
        else
            high = mid - 1;
    }

    return -1;
}
```

The benchmark performs 16 searches containing both hits and misses.

---

## Euclidean GCD — Repeated Data-Dependent Branches

The GCD benchmark computes the greatest common divisor of 16 integer pairs.

The implementation uses subtraction-based Euclid rather than modulo because the processor implements base RV32I and does not include the RV32M multiply/divide extension.

### C Reference Implementation

```c
int gcd(int a, int b)
{
    while (a != b) {
        if (a > b)
            a = a - b;
        else
            b = b - a;
    }

    return a;
}
```

The workload exercises repeated comparisons and branches whose behavior depends on the changing values of `a` and `b`.

This creates substantially different branch behavior from the strongly biased loop in Fibonacci.

---

## String Search — Correlated Branch Workload

String Search implements the classic "Find the Index of the First Occurrence in a String" / `strStr()` problem.

The benchmark performs 16 substring searches using a naive character-by-character search algorithm.

### C Reference Implementation

```c
int strStr(char *haystack, char *needle)
{
    int n = strlen(haystack);
    int m = strlen(needle);

    for (int i = 0; i <= n - m; i++) {
        int j = 0;

        while (j < m && haystack[i + j] == needle[j])
            j++;

        if (j == m)
            return i;
    }

    return -1;
}
```

The benchmark uses repetitive strings containing partial matches, for example:

```text
haystack = ABABABABABABABAC
needle   = ABABAC
```

This creates sequences where several characters match before a later character fails.

Conceptually, the branch behavior can look like:

```text
match
match
match
match
match
mismatch

match
match
match
match
match
mismatch
...
```

This workload is particularly interesting for Gshare.

Bimodal learns the general taken/not-taken tendency of a static branch. Gshare additionally incorporates recent branch outcomes into its table index.

The repeated partial-match sequences in String Search therefore provide useful branch-history context that is not available to Bimodal.

This is the first application workload in the current suite where Gshare clearly outperforms Bimodal.

---

## Branch Predictor Stress Test

`tb_branch_predictor.sv` provides a synthetic workload specifically designed to exercise different branch behavior.

The test contains controlled branch patterns including:

* strongly biased branches
* alternating branches
* globally correlated branch pairs

Unlike the application workloads, this test intentionally creates branch patterns that isolate predictor behavior.

It is useful for demonstrating that Gshare can outperform Bimodal when recent global branch history contains useful predictive information.

Current stress-test branch accuracy measurements are retained as predictor characterization. Cycle count and IPC are still considered preliminary because the current testbench reaches its timeout after the intended workload completes.

---

# Branch Predictors

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

## Always Not Taken

Provides the simplest prediction baseline.

Every conditional branch is predicted not taken.

No history or prediction table is required.

---

## Bimodal

Uses a PC-indexed table of 2-bit saturating counters.

The predictor learns the taken/not-taken tendency of each static branch independently.

Conceptually, Bimodal answers:

> What does this branch usually do?

This works particularly well for branches with a strong and stable per-PC bias, such as the loop branch in Fibonacci.

---

## Gshare

Uses global branch history combined with the branch PC to index a Pattern History Table.

Conceptually, Gshare answers:

> Given what the recent branches did, what does this branch usually do next?

This allows Gshare to capture correlations between branch outcomes rather than treating each branch independently.

The additional history does not automatically improve prediction.

If a branch already has a strong independent bias, mixing global history into the index can distribute training across multiple PHT entries and may perform worse than a simpler Bimodal predictor.

When meaningful correlation exists, however, Gshare can perform substantially better.

The String Search and synthetic predictor stress workloads demonstrate this behavior.

---

# Performance Metrics

Because the processor is 2-way superscalar, up to two instructions can retire during a single cycle.

The testbenches count both writeback lanes.

For the newer benchmarks, retirement accounting also prevents a younger lane-2 instruction from being counted when the older lane contains the terminating `ebreak`.

```systemverilog
retire_count <= retire_count
    + ((dut.wb1_valid &&
        !dut.wb1_ebreak) ? 1 : 0)

    + ((dut.wb2_valid &&
        !dut.wb2_ebreak &&
        !(dut.wb1_valid &&
          dut.wb1_ebreak)) ? 1 : 0);
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

Dependencies, branches, memory operations, structural hazards, pipeline fill/drain, serialization, and misprediction recovery reduce achieved IPC.

The terminating `ebreak` instruction is excluded because it terminates simulation rather than performing workload computation.

Each simulation reports:

```text
cycles=XX retired=XX IPC=X.XXXX
```

---

# Branch Prediction Metrics

The branch-intensive testbenches additionally track:

```text
branches
mispredictions
prediction accuracy
```

Prediction accuracy is calculated as:

```text
accuracy =
    (branches - mispredictions) / branches
```

These statistics make it possible to connect IPC changes to actual predictor behavior rather than comparing IPC alone.

---

# Benchmark Results

## Fibonacci

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |   Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | ---------: |
| Always Not Taken |    151 |     148 | **0.9801** |       29 |             28 |  **3.45%** |
| Bimodal          |    101 |     149 | **1.4752** |       29 |              3 | **89.66%** |
| Gshare           |    121 |     149 | **1.2314** |       29 |             13 | **55.17%** |

All configurations produce the expected result:

```text
fib(30) = 0x000CB228
```

### Analysis

Fibonacci is an excellent example of a branch that does not require complicated history to predict well.

The important loop branch behaves approximately like:

```text
T T T T T T T T T ... N
```

Always Not Taken therefore mispredicts almost every loop iteration.

Bimodal quickly trains its per-PC saturating counter toward taken, reducing mispredictions from 28 to only 3.

Gshare improves substantially over Always Not Taken but reaches only 55.17% accuracy because the global-history indexing spreads this short repetitive branch across multiple history-dependent PHT entries.

Relative to Always Not Taken:

```text
Bimodal IPC improvement ≈ 50.5%
Gshare IPC improvement  ≈ 25.6%
```

For this workload, the simpler predictor is the better fit.

The slight difference in retired instruction count (`148` versus `149`) comes from the older benchmark's termination accounting and should not be interpreted as a difference in architectural program behavior.

---

## Matrix 3×3 Multiply

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: |
| Always Not Taken |     17 |      15 | **0.8824** |        0 |              0 |
| Bimodal          |     17 |      15 | **0.8824** |        0 |              0 |
| Gshare           |     17 |      15 | **0.8824** |        0 |              0 |

The current Matrix benchmark executes no conditional branches, so all predictors produce identical results.

This makes Matrix unsuitable for predictor characterization but useful for measuring superscalar execution independently of branch prediction.

### v2 vs. v3

```text
v2 Matrix IPC = 0.75
v3 Matrix IPC = 0.8824
```

This corresponds to approximately:

```text
+17.7% IPC
```

Because the exact same workload is retained between processor generations, Matrix provides a useful scalar-versus-superscalar baseline.

---

## Bubble Sort

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions | Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | -------: |
| Always Not Taken |     19 |      19 | **1.0000** |        1 |              0 |     100% |
| Bimodal          |     19 |      19 | **1.0000** |        1 |              0 |     100% |
| Gshare           |     19 |      19 | **1.0000** |        1 |              0 |     100% |

All predictor configurations produce identical performance.

Because this workload executes only one dynamic conditional branch, it does not meaningfully differentiate predictor quality.

It remains useful because the same workload was used by the previous v2 processor.

### v2 vs. v3

```text
v2 Bubble Sort IPC = 0.76
v3 Bubble Sort IPC = 1.0000
```

This corresponds to approximately:

```text
+31.6% IPC
```

Bubble Sort is therefore retained primarily as a v2-to-v3 microarchitectural comparison.

---

## Binary Search

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |   Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | ---------: |
| Always Not Taken |   1013 |     864 | **0.8529** |      223 |             62 |     72.20% |
| Bimodal          |    987 |     865 | **0.8764** |      223 |             49 | **78.03%** |
| Gshare           |   1015 |     864 | **0.8512** |      223 |             63 |     71.75% |

All 16 search results are verified by the testbench.

### Analysis

Binary Search produces significantly more irregular control flow than Fibonacci.

Always Not Taken already reaches 72.20% accuracy because several branch sites have a natural not-taken bias.

Bimodal improves accuracy to 78.03% and reduces mispredictions from 62 to 49.

Gshare reaches 71.75%, slightly below the Always Not Taken baseline for this particular dataset.

The left/right decisions in Binary Search depend strongly on the current search key and midpoint. Recent global branch outcomes do not necessarily provide useful information about the next comparison.

This demonstrates that data-dependent control flow does not automatically imply useful global branch correlation.

---

## Insertion Sort

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |   Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | ---------: |
| Always Not Taken |   1296 |    1129 | **0.8711** |      270 |             29 |     89.26% |
| Bimodal          |   1274 |    1129 | **0.8862** |      270 |             18 | **93.33%** |
| Gshare           |   1282 |    1129 | **0.8807** |      270 |             23 |     91.48% |

All predictor configurations correctly sort the reversed 16-element array.

### Analysis

Bimodal again produces the best result.

Compared with Always Not Taken:

```text
mispredictions: 29 -> 18
reduction:       ≈ 37.9%

IPC:             0.8711 -> 0.8862
improvement:     ≈ 1.7%
```

Gshare also improves over Always Not Taken:

```text
IPC: 0.8711 -> 0.8807
```

but does not outperform Bimodal.

The workload contains several branch sites with consistent local behavior, allowing the per-PC counters in Bimodal to learn their tendencies effectively.

---

## Euclidean GCD

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |   Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | ---------: |
| Always Not Taken |    831 |     687 | **0.8267** |      310 |             77 |     75.16% |
| Bimodal          |    815 |     688 | **0.8442** |      310 |             69 | **77.74%** |
| Gshare           |    821 |     688 | **0.8380** |      310 |             72 |     76.77% |

All 16 GCD results are verified.

### Analysis

GCD produces repeated data-dependent control flow as the operands change during execution.

Bimodal achieves the highest accuracy at 77.74% and the highest IPC at 0.8442.

Relative to Always Not Taken:

```text
mispredictions: 77 -> 69
reduction:       ≈ 10.4%

IPC:             0.8267 -> 0.8442
improvement:     ≈ 2.1%
```

Gshare falls between Always Not Taken and Bimodal.

Like Binary Search, this demonstrates that irregular branches are not automatically globally correlated branches.

---

## String Search

String Search produces the clearest application-level example of Gshare outperforming Bimodal.

| Predictor        | Cycles | Retired |        IPC | Branches | Mispredictions |   Accuracy |
| ---------------- | -----: | ------: | ---------: | -------: | -------------: | ---------: |
| Always Not Taken |   4982 |    4687 | **0.9408** |      923 |            162 |     82.45% |
| Bimodal          |   4954 |    4687 | **0.9461** |      923 |            148 |     83.97% |
| Gshare           |   4847 |    4687 | **0.9670** |      923 |             93 | **89.92%** |

All 16 substring-search results are verified.

This is also the largest realistic branch workload currently in the suite:

```text
4,687 retired instructions
923 dynamic branches
```

The retirement count is identical across all three predictor configurations, making this a particularly clean comparison.

### Analysis

Gshare reduces Bimodal's misprediction count from:

```text
148 -> 93
```

This eliminates 55 mispredictions, corresponding to approximately:

```text
37.2% fewer mispredictions
```

Prediction accuracy increases from:

```text
83.97% -> 89.92%
```

and execution decreases from:

```text
4954 cycles -> 4847 cycles
```

IPC increases from:

```text
0.9461 -> 0.9670
```

or approximately:

```text
+2.2%
```

Compared with Always Not Taken, Gshare eliminates 69 of 162 mispredictions:

```text
≈ 42.6% fewer mispredictions
```

The important difference is the repeated partial-match behavior of substring search.

For example:

```text
haystack = ABABABABABABABAC
needle   = ABABAC
```

produces repeated sequences of successful comparisons followed by mismatches.

The same static comparison branch therefore behaves differently depending on the recent sequence of branch outcomes.

Bimodal only tracks the overall behavior of that static branch.

Gshare can distinguish different recent histories.

For this workload, that extra context contains useful predictive information.

---

# Application Predictor Comparison

The realistic application workloads currently produce:

| Workload       | Always NT IPC | Bimodal IPC | Gshare IPC | Always NT Accuracy | Bimodal Accuracy | Gshare Accuracy |
| -------------- | ------------: | ----------: | ---------: | -----------------: | ---------------: | --------------: |
| Fibonacci      |        0.9801 |  **1.4752** |     1.2314 |              3.45% |       **89.66%** |          55.17% |
| Binary Search  |        0.8529 |  **0.8764** |     0.8512 |             72.20% |       **78.03%** |          71.75% |
| Insertion Sort |        0.8711 |  **0.8862** |     0.8807 |             89.26% |       **93.33%** |          91.48% |
| GCD            |        0.8267 |  **0.8442** |     0.8380 |             75.16% |       **77.74%** |          76.77% |
| String Search  |        0.9408 |      0.9461 | **0.9670** |             82.45% |           83.97% |      **89.92%** |

These results show why predictor performance needs to be evaluated across multiple workloads.

Bimodal produces the highest measured IPC on four of the five branch-intensive application workloads:

```text
Fibonacci
Binary Search
Insertion Sort
GCD
```

Gshare produces the highest IPC on:

```text
String Search
```

This initially seems counterintuitive because Gshare is the more sophisticated predictor.

The results make more sense when looking at what information each predictor is designed to exploit.

```text
Bimodal:
"What does this branch usually do?"

Gshare:
"Given the recent branch history,
 what does this branch usually do?"
```

For many of these workloads, individual branches have strong enough local biases that Bimodal's per-PC counters are sufficient.

In String Search, recent branch history contains additional useful information because of repeated partial-match sequences.

The result is not that one predictor is universally better.

The result is that predictor effectiveness is workload-dependent.

---

# Branch Predictor Stress Test

A dedicated synthetic workload is also used to isolate branch patterns that may not naturally appear in the smaller application benchmarks.

Current branch prediction results are:

| Predictor        | Branches | Mispredictions |   Accuracy |
| ---------------- | -------: | -------------: | ---------: |
| Always Not Taken |      480 |            349 | **27.29%** |
| Bimodal          |      480 |            137 | **71.46%** |
| Gshare           |      480 |             54 | **88.75%** |

The synthetic workload includes explicitly correlated branch behavior.

Gshare reduces mispredictions from 137 to 54 relative to Bimodal.

This result is consistent with String Search and confirms that the Gshare implementation is capable of exploiting global correlation when it is actually present.

The raw stress-test simulations currently report:

| Predictor        | Cycles | Retired | Raw IPC |
| ---------------- | -----: | ------: | ------: |
| Always Not Taken |   1619 |     995 |  0.6146 |
| Bimodal          |   1195 |     995 |  0.8326 |
| Gshare           |   1029 |     995 |  0.9670 |

These IPC values are **not treated as final benchmark results**.

The current stress-test termination logic allows simulation to continue after the intended workload has completed, so the branch accuracy values are retained for predictor characterization while cycle count and IPC will be rerun after termination handling is corrected.

---

# Predictor Selection for Physical Implementation

The simulation RTL intentionally retains all three predictors so they can be evaluated under identical processor and workload conditions.

The final physical implementation does not necessarily need to retain all three.

The current measurements provide an empirical basis for selecting a production predictor.

Across the five realistic branch-intensive application workloads:

```text
Bimodal highest IPC: 4 workloads
Gshare highest IPC:  1 workload
```

Gshare clearly provides value when global branch correlation exists. String Search and the synthetic branch predictor stress test both demonstrate this.

However, the additional history and Pattern History Table complexity only translate into better application performance when that correlation is useful.

The current application results therefore make Bimodal a strong candidate for the final synthesis and timing-analysis configuration.

The decision is not based only on RTL complexity.

It follows the architecture evaluation process:

```text
implement predictors
        ↓
verify correctness
        ↓
benchmark multiple workloads
        ↓
measure IPC and prediction accuracy
        ↓
evaluate implementation cost
        ↓
select production predictor
```

This is especially important because predictor selection affects more than prediction accuracy.

The final tradeoff includes:

* IPC
* misprediction rate
* predictor storage
* combinational complexity
* area
* fanout
* timing
* achievable clock frequency

The final processor should therefore be evaluated using both architectural performance and physical implementation results.

---

# v2 vs. v3 IPC Comparison

The common workloads provide a direct comparison between the previous scalar pipelined processor and the current 2-way superscalar design.

| Workload    | v2 Scalar IPC | v3 Superscalar IPC | IPC Improvement |
| ----------- | ------------: | -----------------: | --------------: |
| Matrix 3×3  |          0.75 |         **0.8824** |      **+17.7%** |
| Bubble Sort |          0.76 |         **1.0000** |      **+31.6%** |

These workloads are intentionally retained even though they are not strong branch predictor benchmarks.

Their purpose is continuity between processor generations.

The final architectural comparison should also include maximum clock frequency after synthesis and timing closure.

A more complete processor throughput metric is:

```text
Instruction throughput ≈ IPC × Fmax
```

A superscalar processor may increase IPC while also introducing additional dispatch, forwarding, hazard-detection, and execution logic into the timing paths.

IPC alone therefore does not determine final processor throughput.

---

# Independent ALU Throughput

A separate throughput benchmark measures the upper end of the superscalar datapath using independent arithmetic instructions.

The benchmark contains 120 independent `ADDI` instructions with no memory operations, dependencies, replays, or branches.

Measured behavior:

```text
cycles              = 65
benchmark instr     = 120

benchmark IPC       ≈ 1.846

dual issue cycles   = 64
single issue cycles = 1
stall cycles        = 0
replay cycles       = 0
flush cycles        = 0

dual retire cycles  = 60
```

The processor therefore reaches approximately:

```text
1.85 IPC
```

on a workload with high instruction-level parallelism.

This is close to the theoretical 2-instruction-per-cycle limit and demonstrates that the front end, dispatch logic, dual execution lanes, forwarding paths, and retirement pipeline can sustain near-maximum throughput when the workload exposes sufficient independent instructions.

This benchmark is intentionally different from the application benchmarks.

It measures the processor's available superscalar throughput rather than typical program behavior.

---

# What Determines IPC?

The benchmark suite demonstrates that superscalar IPC is strongly workload-dependent.

High IPC requires more than simply having two execution lanes.

Performance depends on several interacting factors:

* available instruction-level parallelism
* RAW and WAW dependencies
* forwarding opportunities
* load-use hazards
* memory-port serialization
* memory latency
* branch frequency
* branch predictability
* control-flow serialization
* misprediction recovery
* pipeline fill and drain
* structural hazards

The independent ALU benchmark approaches 1.85 IPC because nearly every instruction can execute independently.

The application workloads achieve lower IPC because real programs contain dependencies, memory operations, and control flow.

This is expected behavior and is one of the main reasons the simulation suite uses multiple workloads instead of reporting a single peak IPC number.

---

# Memory Latency

The testbenches support configurable simulated memory latency through the `+lat` argument.

For example:

```bash
+lat=1
+lat=2
+lat=3
```

This can be used to observe how memory latency affects superscalar utilization and IPC.

When comparing predictors, the same memory latency should be used for every predictor configuration.

---

# Compile Source Code

A SystemVerilog benchmark can be compiled with Icarus Verilog.

For example:

```bash
iverilog -g2012 -I ../0-rtl \
    -o fib_sim \
    tb_fib.sv \
    ../0-rtl/core_riscv_superscalar.sv \
    ../0-rtl/*.sv
```

A file list can also be used to keep the command manageable.

Example:

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

---

# Run Simulation

Each branch-intensive benchmark can be run with all three predictors.

### Fibonacci

```bash
vvp fib_sim +pred=0
vvp fib_sim +pred=1
vvp fib_sim +pred=2
```

### Binary Search

```bash
vvp binarysearch_sim +pred=0
vvp binarysearch_sim +pred=1
vvp binarysearch_sim +pred=2
```

### Insertion Sort

```bash
vvp insertionsort_sim +pred=0
vvp insertionsort_sim +pred=1
vvp insertionsort_sim +pred=2
```

### GCD

```bash
vvp gcd_sim +pred=0
vvp gcd_sim +pred=1
vvp gcd_sim +pred=2
```

### String Search

```bash
vvp findstring_sim +pred=0
vvp findstring_sim +pred=1
vvp findstring_sim +pred=2
```

### Matrix

```bash
vvp matrix_sim +pred=0
vvp matrix_sim +pred=1
vvp matrix_sim +pred=2
```

### Bubble Sort

```bash
vvp bubblesort_sim +pred=0
vvp bubblesort_sim +pred=1
vvp bubblesort_sim +pred=2
```

### Branch Predictor Stress Test

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

# Current Takeaways

The simulation results have produced several useful architectural observations.

### Superscalar execution can approach the theoretical limit

The independent ALU benchmark reaches approximately:

```text
1.85 IPC
```

showing that the 2-way pipeline can sustain near-two-wide execution when sufficient instruction-level parallelism exists.

### Real application IPC is workload-dependent

Dependencies, memory operations, and branches reduce available parallelism.

The application benchmarks intentionally exercise different combinations of these effects rather than trying to maximize IPC.

### Branch predictor complexity does not guarantee better prediction

Bimodal outperforms Gshare on Fibonacci, Binary Search, Insertion Sort, and GCD.

These workloads contain branch behavior that is captured effectively by simple per-PC saturating counters.

### Gshare is useful when global correlation exists

String Search reverses the trend.

Gshare reaches:

```text
89.92% accuracy
0.9670 IPC
```

compared with Bimodal:

```text
83.97% accuracy
0.9461 IPC
```

The synthetic correlated branch test shows the same behavior even more strongly:

```text
Bimodal accuracy = 71.46%
Gshare accuracy  = 88.75%
```

This demonstrates that the Gshare implementation works as intended, but its advantage depends on workload behavior.

### Bimodal is currently the leading production-predictor candidate

For the current application suite, Bimodal provides the strongest overall measured IPC behavior while requiring less predictor complexity than Gshare.

This makes Bimodal a reasonable candidate for the final synthesis, physical implementation, and timing-analysis configuration.

Gshare remains in the simulation RTL because its results provide useful architectural characterization and demonstrate the performance benefit of global history on correlated workloads.

---

# Next Steps

The next stage of the project moves from simulation-level architectural performance toward physical implementation.

Planned work includes:

* finalize the production branch predictor
* synthesize the selected processor configuration
* analyze standard-cell area
* run static timing analysis
* investigate critical paths and high-fanout structures
* perform physical implementation
* determine post-layout maximum clock frequency
* compare v2 and v3 using both IPC and clock frequency

The final processor comparison will therefore consider:

```text
Architectural performance
        +
Physical implementation cost
        ↓
IPC × Fmax
area
timing
```

The simulation results provide the architectural side of that decision.

The synthesis and timing results will determine whether the additional superscalar hardware translates into higher overall instruction throughput after physical implementation.
