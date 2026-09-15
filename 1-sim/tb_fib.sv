`timescale 1ns / 1ps

module tb_fib();
    localparam CLK_PERIOD  = 10;
    localparam IMEM_WORDS  = 1024;
    localparam DMEM_WORDS  = 16384;
    localparam BASE        = 32'h0000_0000;

    logic clk, rst_n, cpu_enable;
    logic [1:0] predictor_sel;
    logic [31:0] imem_addr, imem_rdata1, imem_rdata2;
    logic imem_req, imem_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0] dmem_wstrb;
    logic dmem_rd_en, dmem_wr_en, dmem_ready;
    logic [31:0] debug_pc, debug_instr, debug_reg_data;
    logic debug_halted;

    core_riscv_superscalar dut (
        .clk(clk), .rst_n(rst_n), .cpu_enable(cpu_enable),
        .predictor_sel(predictor_sel),
        .imem_addr(imem_addr), .imem_req(imem_req), .imem_rdata1(imem_rdata1), .imem_rdata2(imem_rdata2), .imem_ready(imem_ready),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_rd_en(dmem_rd_en), .dmem_wr_en(dmem_wr_en), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .debug_pc(debug_pc), .debug_instr(debug_instr), .debug_reg_data(debug_reg_data), .debug_halted(debug_halted)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // instruction memory
    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [31:0] imem_index, imem_index2;
    assign imem_index = (imem_addr - BASE) >> 2;
    assign imem_index2 = imem_index + 1;

    int MEM_LATENCY;
    int PREDICTOR;
    initial begin
        if (!$value$plusargs("lat=%d", MEM_LATENCY)) MEM_LATENCY = 1;
        if (!$value$plusargs("pred=%d", PREDICTOR)) PREDICTOR = 2;
        predictor_sel = PREDICTOR[1:0];
        for (int i = 0; i < IMEM_WORDS; i++)
            imem[i] = 32'h00000013; // NOP

        // Fibonacci(30) iterative
        // x1 = a = 0, x2 = b = 1, x3 = count = 30
        // Loop: c = a + b, a = b, b = c, count--, branch back
        imem['h000 >> 2] = 32'h00000093; // addi x1, x0, 0      # a = 0
        imem['h004 >> 2] = 32'h00100113; // addi x2, x0, 1      # b = 1
        imem['h008 >> 2] = 32'h01E00193; // addi x3, x0, 30     # count = 30
        imem['h00C >> 2] = 32'h002081B3; // add  x3, x1, x2     # c = a + b (WRONG, reusing x3)
        // Let me redo:
        imem['h000 >> 2] = 32'h00000093; // addi x1, x0, 0      # x1 = a = 0
        imem['h004 >> 2] = 32'h00100113; // addi x2, x0, 1      # x2 = b = 1
        imem['h008 >> 2] = 32'h01E00193; // addi x3, x0, 30     # x3 = count = 30
        // LOOP (offset 0x0C):
        imem['h00C >> 2] = 32'h002080B3; // add  x1, x1, x2     # wait, need temp. Let me use x4
        imem['h00C >> 2] = 32'h00208233; // add  x4, x1, x2     # x4 = c = a + b
        imem['h010 >> 2] = 32'h00210093; // addi x1, x2, 0      # x1 = a = b (copy x2 to x1)
        imem['h014 >> 2] = 32'h00420113; // addi x2, x4, 0      # x2 = b = c (copy x4 to x2)
        imem['h018 >> 2] = 32'hFFF18193; // addi x3, x3, -1     # x3 = count - 1
        imem['h01C >> 2] = 32'hFE031CE3; // bne  x3, x0, -12    # if x3 != 0, jump to LOOP (offset 0x0C = -12 from 0x1C)
        imem['h020 >> 2] = 32'h00100073; // ebreak              # halt
    end

    assign imem_rdata1 = (imem_index < IMEM_WORDS) ? imem[imem_index[$clog2(IMEM_WORDS)-1:0]] : 32'h00000013;
    assign imem_rdata2 = (imem_index2 < IMEM_WORDS) ? imem[imem_index2[$clog2(IMEM_WORDS)-1:0]] : 32'h00000013;

    int imem_cnt = 0;
    assign imem_ready = imem_req && (imem_cnt == MEM_LATENCY-1);
    always_ff @(posedge clk) begin
        if (!imem_req)         imem_cnt <= 0;
        else if (imem_ready)   imem_cnt <= 0;
        else                   imem_cnt <= imem_cnt + 1;
    end

    // data memory
    logic [31:0] dmem [0:DMEM_WORDS-1];
    initial for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = 32'h0;

    assign dmem_rdata = dmem[dmem_addr[$clog2(DMEM_WORDS)+1:2]];

    int dmem_cnt = 0;
    logic [31:0] dmem_idx;
    assign dmem_idx   = dmem_addr[$clog2(DMEM_WORDS)+1:2];
    assign dmem_ready = (dmem_rd_en || dmem_wr_en) && (dmem_cnt == MEM_LATENCY-1);
    always_ff @(posedge clk) begin
        if (!(dmem_rd_en || dmem_wr_en)) dmem_cnt <= 0;
        else if (dmem_ready)             dmem_cnt <= 0;
        else                             dmem_cnt <= dmem_cnt + 1;
        if (dmem_wr_en && dmem_ready) begin
            if (dmem_wstrb[0]) dmem[dmem_idx][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_idx][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_idx][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_idx][31:24] <= dmem_wdata[31:24];
        end
    end

    function automatic [31:0] read_reg(input int unsigned n);
        read_reg = dut.registers.mem[n];
    endfunction

    // IPC instrumentation
    longint cycle_count, retire_count;
    longint branch_count, mispredict_count;
    logic halted_seen;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_count      <= 0;
            retire_count     <= 0;
            branch_count     <= 0;
            mispredict_count <= 0;
            halted_seen      <= 1'b0;
        end else if (cpu_enable && !halted_seen) begin
            cycle_count <= cycle_count + 1;
            retire_count <= retire_count
                          + ((dut.wb1_valid && !dut.wb1_ebreak) ? 1 : 0)
                          + ((dut.wb2_valid && !dut.wb2_ebreak) ? 1 : 0);

            if (dut.branch_update_valid)
                branch_count <= branch_count + 1;

            if (dut.mispredict)
                mispredict_count <= mispredict_count + 1;

            if (debug_halted)
                halted_seen <= 1'b1;
        end
    end

    initial begin
        rst_n = 1'b0;
        cpu_enable = 1'b0;
        #1;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        cpu_enable = 1'b1;

        $display("\n[TB-FIB] Fibonacci(30) benchmark starting...");
        fork
            begin
                wait (halted_seen);
                $display("[TB-FIB] EBREAK retired at T=%0t", $time);
            end
            begin
                repeat (60000) @(posedge clk);
            end
        join_any
        disable fork;
        repeat (4) @(posedge clk);

        $display("\n========== IPC (Fibonacci) ==========");
        $display("cycles=%0d  retired=%0d  IPC=%0.4f",
                 cycle_count, retire_count,
                 real'(retire_count) / real'(cycle_count));
        $display("predictor=%0d  branches=%0d  mispredicts=%0d  accuracy=%0.2f%%",
                 PREDICTOR, branch_count, mispredict_count,
                 branch_count ? 100.0 * real'(branch_count - mispredict_count) / real'(branch_count) : 0.0);
        $display("Result in x2: 0x%08h (should be fib(30))", read_reg(2));
        $finish;
    end

    initial begin
        #5000000;
        $display("[TIMEOUT] Simulation exceeded 5ms");
        $fatal;
    end

endmodule