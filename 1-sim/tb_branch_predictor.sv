`timescale 1ns/1ps

// branch-predictor stress benchmark for core_riscv_superscalar
//
// run the same binary/program with:
//   vvp pred_sim +pred=0    // always not-taken
//   vvp pred_sim +pred=1    // bimodal
//   vvp pred_sim +pred=2    // gshare
//
// Workload phases:
//   1) strongly taken loop
//   2) alternating T/NT branch
//   3) correlated pair: branch B outcome depends on branch A history
//

module tb_branch_predictor;

    localparam int IMEM_WORDS = 256;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic cpu_enable = 1'b0;
    logic [1:0] predictor_sel;

    logic [31:0] imem_addr;
    logic        imem_req;
    logic [31:0] imem_rdata1, imem_rdata2;
    logic        imem_ready;

    logic [31:0] dmem_addr;
    logic        dmem_rd_en, dmem_wr_en;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_wstrb;
    logic [31:0] dmem_rdata;
    logic        dmem_ready;
    logic        debug_halted;

    logic [31:0] imem [0:IMEM_WORDS-1];
    integer idx;
    integer pred_arg;
    integer timeout;
    integer alt_loop_word;
    integer corr_loop_word;
    integer a_taken_word;
    integer after_a_word;
    integer b_taken_word;
    integer after_b_word;

    integer cycles;
    integer retired;
    integer branches;
    integer mispredicts;

    integer loop_branches, loop_misses;
    integer alt_branches, alt_misses;
    integer corr_a_branches, corr_a_misses;
    integer corr_b_branches, corr_b_misses;

    integer pc_loop_branch;
    integer pc_alt_branch;
    integer pc_corr_a;
    integer pc_corr_b;

    core_riscv_superscalar dut (
        .clk(clk), .rst_n(rst_n), .cpu_enable(cpu_enable),
        .predictor_sel(predictor_sel),

        .imem_addr(imem_addr),
        .imem_req(imem_req),
        .imem_rdata1(imem_rdata1),
        .imem_rdata2(imem_rdata2),
        .imem_ready(imem_ready),

        .dmem_addr(dmem_addr),
        .dmem_rd_en(dmem_rd_en),
        .dmem_wr_en(dmem_wr_en),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready),

        .debug_halted(debug_halted)
    );

    always #5 clk = ~clk;

    always_comb begin
        idx = imem_addr >> 2;
        imem_rdata1 = 32'h00000013;
        imem_rdata2 = 32'h00000013;
        if (idx >= 0 && idx < IMEM_WORDS)
            imem_rdata1 = imem[idx];
        if ((idx+1) >= 0 && (idx+1) < IMEM_WORDS)
            imem_rdata2 = imem[idx+1];
    end

    assign imem_ready = imem_req;
    assign dmem_rdata = 32'b0;
    assign dmem_ready = 1'b1;

    function automatic [31:0] enc_addi(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input integer imm
    );
        enc_addi = {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic [31:0] enc_andi(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input integer imm
    );
        enc_andi = {imm[11:0], rs1, 3'b111, rd, 7'b0010011};
    endfunction

    function automatic [31:0] enc_bne(
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input integer imm
    );
        logic [12:0] b;
        begin
            b = imm[12:0];
            enc_bne = {b[12], b[10:5], rs2, rs1, 3'b001,
                       b[4:1], b[11], 7'b1100011};
        end
    endfunction

    function automatic [31:0] enc_beq(
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input integer imm
    );
        logic [12:0] b;
        begin
            b = imm[12:0];
            enc_beq = {b[12], b[10:5], rs2, rs1, 3'b000,
                       b[4:1], b[11], 7'b1100011};
        end
    endfunction

    function automatic [31:0] enc_jal(
        input logic [4:0] rd,
        input integer imm
    );
        logic [20:0] j;
        begin
            j = imm[20:0];
            enc_jal = {j[20], j[10:1], j[11], j[19:12],
                       rd, 7'b1101111};
        end
    endfunction

    integer p;
    task automatic emit(input [31:0] insn);
        begin
            imem[p] = insn;
            p = p + 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("pred=%d", pred_arg))
            pred_arg = 2;

        case (pred_arg)
            0: predictor_sel = 2'b00;
            1: predictor_sel = 2'b01;
            default: predictor_sel = 2'b10;
        endcase

        for (p = 0; p < IMEM_WORDS; p = p + 1)
            imem[p] = 32'h00000013;

        p = 0;

        // ------------------------------------------------------------
        // Phase 1: strongly taken loop.
        // 64 dynamic branches: T x63, N x1.
        // ------------------------------------------------------------
        emit(enc_addi(5'd1, 5'd0, 64));
        alt_loop_word = p;                     // reuse helper as loop start
        emit(enc_addi(5'd1, 5'd1, -1));
        pc_loop_branch = p * 4;
        emit(enc_bne(5'd1, 5'd0,
                     (alt_loop_word - p) * 4));

        // ------------------------------------------------------------
        // Phase 2: alternating branch.
        // The measured branch sees T,N,T,N,... at one static PC.
        // A separate loop-control branch keeps the phase running.
        // ------------------------------------------------------------
        emit(enc_addi(5'd2, 5'd0, 64));
        alt_loop_word = p;
        emit(enc_andi(5'd3, 5'd2, 1));
        pc_alt_branch = p * 4;
        emit(enc_bne(5'd3, 5'd0, 8));          // taken skips one NOP
        emit(32'h00000013);
        emit(enc_addi(5'd2, 5'd2, -1));
        emit(enc_bne(5'd2, 5'd0,
                     (alt_loop_word - p) * 4));

        // ------------------------------------------------------------
        // Phase 3: correlated branch pair.
        //
        // A and B test the SAME alternating condition, back-to-back.
        // Thus B's outcome is perfectly correlated with the immediately
        // preceding outcome of A. Both paths reconverge by merely
        // skipping a NOP; no JAL is needed.
        // ------------------------------------------------------------
        emit(enc_addi(5'd4, 5'd0, 96));
        corr_loop_word = p;

        emit(enc_andi(5'd5, 5'd4, 1));

        pc_corr_a = p * 4;
        emit(enc_bne(5'd5, 5'd0, 8));          // A
        emit(32'h00000013);                    // skipped when A taken

        pc_corr_b = p * 4;
        emit(enc_bne(5'd5, 5'd0, 8));          // B, same outcome as A
        emit(32'h00000013);                    // skipped when B taken

        emit(enc_addi(5'd4, 5'd4, -1));
        emit(enc_bne(5'd4, 5'd0,
                     (corr_loop_word - p) * 4));

        emit(32'h00100073);                    // EBREAK

        cycles = 0;
        retired = 0;
        branches = 0;
        mispredicts = 0;
        loop_branches = 0; loop_misses = 0;
        alt_branches = 0; alt_misses = 0;
        corr_a_branches = 0; corr_a_misses = 0;
        corr_b_branches = 0; corr_b_misses = 0;

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        cpu_enable <= 1'b1;

        $display("[TB-PRED] Branch predictor stress test starting...");
        $display("[TB-PRED] predictor=%0d (0=NT, 1=bimodal, 2=gshare)",
                 pred_arg);
    end

    always @(posedge clk) begin
        if (rst_n && cpu_enable && !debug_halted) begin
            cycles <= cycles + 1;

            retired <= retired
                + ((dut.wb1_valid && !dut.wb1_ebreak) ? 1 : 0)
                + ((dut.wb2_valid && !dut.wb2_ebreak) ? 1 : 0);

            if (dut.branch_update_valid) begin
                branches <= branches + 1;
                if (dut.mispredict)
                    mispredicts <= mispredicts + 1;

                if (dut.branch_pc_ex == pc_loop_branch) begin
                    loop_branches <= loop_branches + 1;
                    if (dut.mispredict) loop_misses <= loop_misses + 1;
                end

                if (dut.branch_pc_ex == pc_alt_branch) begin
                    alt_branches <= alt_branches + 1;
                    if (dut.mispredict) alt_misses <= alt_misses + 1;
                end

                if (dut.branch_pc_ex == pc_corr_a) begin
                    corr_a_branches <= corr_a_branches + 1;
                    if (dut.mispredict) corr_a_misses <= corr_a_misses + 1;
                end

                if (dut.branch_pc_ex == pc_corr_b) begin
                    corr_b_branches <= corr_b_branches + 1;
                    if (dut.mispredict) corr_b_misses <= corr_b_misses + 1;
                end
            end
        end
    end

    initial begin
        timeout = 0;
        wait(rst_n && cpu_enable);

        while (!debug_halted && timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        @(negedge clk);

        if (!debug_halted) begin
            $display("FAIL: predictor stress test timed out");
            $display("  pc=0x%08h cycles=%0d retired=%0d branches=%0d misses=%0d",
                     dut.pc_curr, cycles, retired, branches, mispredicts);
            $display("  x1=%0d x2=%0d x4=%0d",
                     dut.registers.registers[1],
                     dut.registers.registers[2],
                     dut.registers.registers[4]);
            $finish;
        end

        $display("");
        $display("========== BRANCH PREDICTOR STRESS ==========");
        $display("predictor=%0d", pred_arg);
        $display("cycles=%0d  retired=%0d  IPC=%0.4f",
                 cycles, retired,
                 cycles ? (1.0 * retired / cycles) : 0.0);

        if (branches != 0)
            $display("ALL:      branches=%0d misses=%0d accuracy=%0.2f%%",
                     branches, mispredicts,
                     100.0 * (branches-mispredicts) / branches);

        if (loop_branches != 0)
            $display("LOOP:     branches=%0d misses=%0d accuracy=%0.2f%%",
                     loop_branches, loop_misses,
                     100.0 * (loop_branches-loop_misses) / loop_branches);

        if (alt_branches != 0)
            $display("ALTERNATE:branches=%0d misses=%0d accuracy=%0.2f%%",
                     alt_branches, alt_misses,
                     100.0 * (alt_branches-alt_misses) / alt_branches);

        if (corr_a_branches != 0)
            $display("CORR-A:   branches=%0d misses=%0d accuracy=%0.2f%%",
                     corr_a_branches, corr_a_misses,
                     100.0 * (corr_a_branches-corr_a_misses) / corr_a_branches);

        if (corr_b_branches != 0)
            $display("CORR-B:   branches=%0d misses=%0d accuracy=%0.2f%%",
                     corr_b_branches, corr_b_misses,
                     100.0 * (corr_b_branches-corr_b_misses) / corr_b_branches);

        $display("=============================================");
        $display("Run this same test with +pred=0, +pred=1, and +pred=2.");
        $finish;
    end

endmodule
