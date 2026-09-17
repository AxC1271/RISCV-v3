`timescale 1ns / 1ps

module tb_gcd();

    localparam CLK_PERIOD = 10;
    localparam IMEM_WORDS = 1024;
    localparam DMEM_WORDS = 16384;
    localparam BASE       = 32'h0000_0000;

    localparam INPUT_BASE  = 32'h0000_0400;
    localparam RESULT_BASE = 32'h0000_0600;
    localparam NUM_PAIRS   = 16;

    logic clk, rst_n, cpu_enable;
    logic [1:0] predictor_sel;

    logic [31:0] imem_addr, imem_rdata1, imem_rdata2;
    logic imem_req, imem_ready;

    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_wstrb;
    logic dmem_rd_en, dmem_wr_en, dmem_ready;

    logic [31:0] debug_pc, debug_instr, debug_reg_data;
    logic debug_halted;

    core_riscv_superscalar dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_enable(cpu_enable),

        .predictor_sel(predictor_sel),

        .imem_addr(imem_addr),
        .imem_req(imem_req),
        .imem_rdata1(imem_rdata1),
        .imem_rdata2(imem_rdata2),
        .imem_ready(imem_ready),

        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_rd_en(dmem_rd_en),
        .dmem_wr_en(dmem_wr_en),
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready),

        .debug_pc(debug_pc),
        .debug_instr(debug_instr),
        .debug_reg_data(debug_reg_data),
        .debug_halted(debug_halted)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end


    function automatic [31:0] enc_r(
        input [6:0] funct7,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3,
        input [4:0] rd,
        input [6:0] opcode
    );
        enc_r = {
            funct7,
            rs2,
            rs1,
            funct3,
            rd,
            opcode
        };
    endfunction

    function automatic [31:0] enc_i(
        input integer imm,
        input [4:0] rs1,
        input [2:0] funct3,
        input [4:0] rd,
        input [6:0] opcode
    );
        logic [11:0] x;

        begin
            x = imm[11:0];

            enc_i = {
                x,
                rs1,
                funct3,
                rd,
                opcode
            };
        end
    endfunction

    function automatic [31:0] enc_s(
        input integer imm,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3
    );
        logic [11:0] x;

        begin
            x = imm[11:0];

            enc_s = {
                x[11:5],
                rs2,
                rs1,
                funct3,
                x[4:0],
                7'b0100011
            };
        end
    endfunction

    function automatic [31:0] enc_b(
        input integer imm,
        input [4:0] rs2,
        input [4:0] rs1,
        input [2:0] funct3
    );
        logic [12:0] x;

        begin
            x = imm[12:0];

            enc_b = {
                x[12],
                x[10:5],
                rs2,
                rs1,
                funct3,
                x[4:1],
                x[11],
                7'b1100011
            };
        end
    endfunction

    function automatic [31:0] enc_j(
        input integer imm,
        input [4:0] rd
    );
        logic [20:0] x;

        begin
            x = imm[20:0];

            enc_j = {
                x[20],
                x[10:1],
                x[11],
                x[19:12],
                rd,
                7'b1101111
            };
        end
    endfunction

    function automatic [31:0] SUB(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        SUB = enc_r(
            7'b0100000,
            rs2,
            rs1,
            3'b000,
            rd,
            7'b0110011
        );
    endfunction

    function automatic [31:0] ADDI(
        input [4:0] rd,
        input [4:0] rs1,
        input integer imm
    );
        ADDI = enc_i(
            imm,
            rs1,
            3'b000,
            rd,
            7'b0010011
        );
    endfunction

    function automatic [31:0] LW(
        input [4:0] rd,
        input [4:0] rs1,
        input integer imm
    );
        LW = enc_i(
            imm,
            rs1,
            3'b010,
            rd,
            7'b0000011
        );
    endfunction

    function automatic [31:0] SW(
        input [4:0] rs2,
        input [4:0] rs1,
        input integer imm
    );
        SW = enc_s(
            imm,
            rs2,
            rs1,
            3'b010
        );
    endfunction

    function automatic [31:0] BEQ(
        input [4:0] rs1,
        input [4:0] rs2,
        input integer imm
    );
        BEQ = enc_b(
            imm,
            rs2,
            rs1,
            3'b000
        );
    endfunction

    function automatic [31:0] BNE(
        input [4:0] rs1,
        input [4:0] rs2,
        input integer imm
    );
        BNE = enc_b(
            imm,
            rs2,
            rs1,
            3'b001
        );
    endfunction

    function automatic [31:0] BLT(
        input [4:0] rs1,
        input [4:0] rs2,
        input integer imm
    );
        BLT = enc_b(
            imm,
            rs2,
            rs1,
            3'b100
        );
    endfunction

    function automatic [31:0] JAL(
        input [4:0] rd,
        input integer imm
    );
        JAL = enc_j(imm, rd);
    endfunction


    logic [31:0] imem [0:IMEM_WORDS-1];

    logic [31:0] imem_index;
    logic [31:0] imem_index2;

    assign imem_index =
        (imem_addr - BASE) >> 2;

    assign imem_index2 =
        imem_index + 1;

    int MEM_LATENCY;
    int PREDICTOR;

    assign imem_rdata1 =
        (imem_index < IMEM_WORDS)
        ? imem[imem_index[$clog2(IMEM_WORDS)-1:0]]
        : 32'h00000013;

    assign imem_rdata2 =
        (imem_index2 < IMEM_WORDS)
        ? imem[imem_index2[$clog2(IMEM_WORDS)-1:0]]
        : 32'h00000013;

    int imem_cnt = 0;

    assign imem_ready =
        imem_req &&
        (imem_cnt == MEM_LATENCY - 1);

    always_ff @(posedge clk) begin

        if (!imem_req)
            imem_cnt <= 0;

        else if (imem_ready)
            imem_cnt <= 0;

        else
            imem_cnt <= imem_cnt + 1;

    end

    logic [31:0] dmem [0:DMEM_WORDS-1];

    int dmem_cnt = 0;

    logic [31:0] dmem_idx;

    assign dmem_idx =
        dmem_addr[$clog2(DMEM_WORDS)+1:2];

    assign dmem_rdata =
        dmem[dmem_addr[$clog2(DMEM_WORDS)+1:2]];

    assign dmem_ready =
        (dmem_rd_en || dmem_wr_en) &&
        (dmem_cnt == MEM_LATENCY - 1);

    always_ff @(posedge clk) begin

        if (!(dmem_rd_en || dmem_wr_en))
            dmem_cnt <= 0;

        else if (dmem_ready)
            dmem_cnt <= 0;

        else
            dmem_cnt <= dmem_cnt + 1;

        if (dmem_wr_en && dmem_ready) begin

            if (dmem_wstrb[0])
                dmem[dmem_idx][7:0]
                    <= dmem_wdata[7:0];

            if (dmem_wstrb[1])
                dmem[dmem_idx][15:8]
                    <= dmem_wdata[15:8];

            if (dmem_wstrb[2])
                dmem[dmem_idx][23:16]
                    <= dmem_wdata[23:16];

            if (dmem_wstrb[3])
                dmem[dmem_idx][31:24]
                    <= dmem_wdata[31:24];

        end
    end

    initial begin

        if (!$value$plusargs("lat=%d", MEM_LATENCY))
            MEM_LATENCY = 1;

        if (!$value$plusargs("pred=%d", PREDICTOR))
            PREDICTOR = 2;

        predictor_sel = PREDICTOR[1:0];

        for (int i = 0; i < IMEM_WORDS; i++)
            imem[i] = 32'h00000013;

        for (int i = 0; i < DMEM_WORDS; i++)
            dmem[i] = 32'h00000000;

        // 16 input pairs.

        dmem[(INPUT_BASE >> 2) + 0]  = 48;
        dmem[(INPUT_BASE >> 2) + 1]  = 18;

        dmem[(INPUT_BASE >> 2) + 2]  = 270;
        dmem[(INPUT_BASE >> 2) + 3]  = 192;

        dmem[(INPUT_BASE >> 2) + 4]  = 1071;
        dmem[(INPUT_BASE >> 2) + 5]  = 462;

        dmem[(INPUT_BASE >> 2) + 6]  = 55;
        dmem[(INPUT_BASE >> 2) + 7]  = 34;

        dmem[(INPUT_BASE >> 2) + 8]  = 144;
        dmem[(INPUT_BASE >> 2) + 9]  = 89;

        dmem[(INPUT_BASE >> 2) + 10] = 391;
        dmem[(INPUT_BASE >> 2) + 11] = 299;

        dmem[(INPUT_BASE >> 2) + 12] = 252;
        dmem[(INPUT_BASE >> 2) + 13] = 105;

        dmem[(INPUT_BASE >> 2) + 14] = 100;
        dmem[(INPUT_BASE >> 2) + 15] = 35;

        dmem[(INPUT_BASE >> 2) + 16] = 81;
        dmem[(INPUT_BASE >> 2) + 17] = 27;

        dmem[(INPUT_BASE >> 2) + 18] = 17;
        dmem[(INPUT_BASE >> 2) + 19] = 13;

        dmem[(INPUT_BASE >> 2) + 20] = 128;
        dmem[(INPUT_BASE >> 2) + 21] = 96;

        dmem[(INPUT_BASE >> 2) + 22] = 221;
        dmem[(INPUT_BASE >> 2) + 23] = 143;

        dmem[(INPUT_BASE >> 2) + 24] = 987;
        dmem[(INPUT_BASE >> 2) + 25] = 610;

        dmem[(INPUT_BASE >> 2) + 26] = 42;
        dmem[(INPUT_BASE >> 2) + 27] = 30;

        dmem[(INPUT_BASE >> 2) + 28] = 625;
        dmem[(INPUT_BASE >> 2) + 29] = 375;

        dmem[(INPUT_BASE >> 2) + 30] = 999;
        dmem[(INPUT_BASE >> 2) + 31] = 27;

        // Registers:
        //
        // x1 = input pointer
        // x2 = output pointer
        // x3 = remaining pairs
        // x4 = a
        // x5 = b

        imem['h000 >> 2] = ADDI(1, 0, 1024);
        // input = 0x400

        imem['h004 >> 2] = ADDI(2, 1, 512);
        // output = 0x600

        imem['h008 >> 2] = ADDI(3, 0, 16);
        // count = 16

        imem['h00C >> 2] = LW(4, 1, 0);
        // a

        imem['h010 >> 2] = LW(5, 1, 4);
        // b

        imem['h014 >> 2] = BEQ(4, 5, 24);
        // a == b -> done at 0x02C

        imem['h018 >> 2] = BLT(4, 5, 12);
        // a < b -> subtract_b at 0x024

        imem['h01C >> 2] = SUB(4, 4, 5);
        // a = a - b

        imem['h020 >> 2] = JAL(0, -12);
        // -> gcd_loop 0x014

        // subtract_b = 0x024

        imem['h024 >> 2] = SUB(5, 5, 4);
        // b = b - a

        imem['h028 >> 2] = JAL(0, -20);
        // -> gcd_loop 0x014

        imem['h02C >> 2] = SW(4, 2, 0);
        // store GCD

        imem['h030 >> 2] = ADDI(1, 1, 8);
        // next pair

        imem['h034 >> 2] = ADDI(2, 2, 4);
        // next output

        imem['h038 >> 2] = ADDI(3, 3, -1);
        // count--

        imem['h03C >> 2] = BNE(3, 0, -48);
        // -> pair_loop 0x00C

        imem['h040 >> 2] = 32'h00100073;
        // ebreak
    end

    longint cycle_count;
    longint retire_count;
    longint branch_count;
    longint mispredict_count;

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

    task automatic check_results;

        integer expected [0:15];
        int errors;

        begin

            expected[0]  = 6;
            expected[1]  = 6;
            expected[2]  = 21;
            expected[3]  = 1;
            expected[4]  = 1;
            expected[5]  = 23;
            expected[6]  = 21;
            expected[7]  = 5;
            expected[8]  = 27;
            expected[9]  = 1;
            expected[10] = 32;
            expected[11] = 13;
            expected[12] = 1;
            expected[13] = 6;
            expected[14] = 125;
            expected[15] = 27;

            errors = 0;

            for (int i = 0; i < NUM_PAIRS; i++) begin

                if (
                    dmem[(RESULT_BASE >> 2) + i]
                    !== expected[i]
                ) begin

                    $display(
                        "FAIL: gcd[%0d]=%0d expected=%0d",
                        i,
                        dmem[(RESULT_BASE >> 2) + i],
                        expected[i]
                    );

                    errors++;

                end
            end

            if (errors == 0)
                $display(
                    "PASS: all 16 GCD results verified"
                );
            else
                $display(
                    "FAIL: GCD benchmark had %0d errors",
                    errors
                );

        end
    endtask

    initial begin

        rst_n = 1'b0;
        cpu_enable = 1'b0;

        #1;

        repeat (5) @(posedge clk);

        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        cpu_enable = 1'b1;

        $display(
            "\n[TB-GCD] Euclidean GCD benchmark starting..."
        );

        fork

            begin
                wait (halted_seen);

                $display(
                    "[TB-GCD] EBREAK retired at T=%0t",
                    $time
                );
            end

            begin
                repeat (200000) @(posedge clk);

                $display(
                    "[TB-GCD] FAIL: benchmark timed out"
                );
            end

        join_any

        disable fork;

        repeat (4) @(posedge clk);

        $display(
            "\n========== IPC (GCD) =========="
        );

        $display(
            "cycles=%0d  retired=%0d  IPC=%0.4f",
            cycle_count,
            retire_count,
            real'(retire_count) / real'(cycle_count)
        );

        $display(
            "predictor=%0d  branches=%0d  mispredicts=%0d  accuracy=%0.2f%%",
            PREDICTOR,
            branch_count,
            mispredict_count,
            branch_count
                ? 100.0 *
                  real'(branch_count - mispredict_count) /
                  real'(branch_count)
                : 0.0
        );

        check_results();

        $finish;
    end

    initial begin

        #20000000;

        $display(
            "[TIMEOUT] Simulation exceeded 20ms"
        );

        $fatal;
    end

endmodule