`timescale 1ns / 1ps

module tb_binary_search();

    localparam CLK_PERIOD = 10;
    localparam IMEM_WORDS = 1024;
    localparam DMEM_WORDS = 16384;
    localparam BASE       = 32'h0000_0000;

    localparam ARRAY_BASE  = 32'h0000_0400;
    localparam KEY_BASE    = 32'h0000_0500;
    localparam RESULT_BASE = 32'h0000_0600;

    localparam NUM_SEARCHES = 16;

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
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
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
            enc_i = {x, rs1, funct3, rd, opcode};
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

    function automatic [31:0] ADD(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        ADD = enc_r(
            7'b0000000,
            rs2,
            rs1,
            3'b000,
            rd,
            7'b0110011
        );
    endfunction

    function automatic [31:0] SRL(
        input [4:0] rd,
        input [4:0] rs1,
        input [4:0] rs2
    );
        SRL = enc_r(
            7'b0000000,
            rs2,
            rs1,
            3'b101,
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

    function automatic [31:0] SLLI(
        input [4:0] rd,
        input [4:0] rs1,
        input integer shamt
    );
        SLLI = enc_i(
            shamt,
            rs1,
            3'b001,
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

        // Sorted array:
        //
        // 0, 2, 4, 6, ... 62

        for (int i = 0; i < 32; i++)
            dmem[(ARRAY_BASE >> 2) + i] = 2 * i;

        // Search keys.
        //
        // First eight are hits.
        // Last eight are misses.

        dmem[(KEY_BASE >> 2) + 0]  = 0;
        dmem[(KEY_BASE >> 2) + 1]  = 62;
        dmem[(KEY_BASE >> 2) + 2]  = 30;
        dmem[(KEY_BASE >> 2) + 3]  = 14;
        dmem[(KEY_BASE >> 2) + 4]  = 46;
        dmem[(KEY_BASE >> 2) + 5]  = 2;
        dmem[(KEY_BASE >> 2) + 6]  = 58;
        dmem[(KEY_BASE >> 2) + 7]  = 18;

        dmem[(KEY_BASE >> 2) + 8]  = 7;
        dmem[(KEY_BASE >> 2) + 9]  = 31;
        dmem[(KEY_BASE >> 2) + 10] = 63;
        dmem[(KEY_BASE >> 2) + 11] = 15;
        dmem[(KEY_BASE >> 2) + 12] = 45;
        dmem[(KEY_BASE >> 2) + 13] = 1;
        dmem[(KEY_BASE >> 2) + 14] = 53;
        dmem[(KEY_BASE >> 2) + 15] = 27;

        // Registers:
        //
        // x1  = array base
        // x2  = key base
        // x3  = result base
        // x4  = query index
        // x5  = number of queries
        // x6  = key
        // x7  = low
        // x8  = high
        // x9  = mid
        // x10 = array[mid]
        // x11 = address temp
        // x12 = result
        // x13 = shift amount = 1

        imem['h000 >> 2] = ADDI(1, 0, 1024);
        // x1 = 0x400

        imem['h004 >> 2] = ADDI(2, 1, 256);
        // x2 = 0x500

        imem['h008 >> 2] = ADDI(3, 2, 256);
        // x3 = 0x600

        imem['h00C >> 2] = ADDI(4, 0, 0);
        // query = 0

        imem['h010 >> 2] = ADDI(5, 0, 16);
        // 16 searches

        imem['h014 >> 2] = ADDI(13, 0, 1);
        // shift amount for SRL

        imem['h018 >> 2] = SLLI(11, 4, 2);
        imem['h01C >> 2] = ADD(11, 2, 11);
        imem['h020 >> 2] = LW(6, 11, 0);
        // key = keys[query]

        imem['h024 >> 2] = ADDI(7, 0, 0);
        // low = 0

        imem['h028 >> 2] = ADDI(8, 0, 31);
        // high = 31

        imem['h02C >> 2] = ADDI(12, 0, -1);
        // result = -1


        imem['h030 >> 2] = BLT(8, 7, 52);
        // if high < low -> store_result 0x064

        imem['h034 >> 2] = ADD(9, 7, 8);
        // mid = low + high

        imem['h038 >> 2] = SRL(9, 9, 13);
        // mid >>= 1

        imem['h03C >> 2] = SLLI(11, 9, 2);
        imem['h040 >> 2] = ADD(11, 1, 11);

        imem['h044 >> 2] = LW(10, 11, 0);
        // value = array[mid]

        imem['h048 >> 2] = BEQ(10, 6, 24);
        // if value == key -> found 0x060

        imem['h04C >> 2] = BLT(10, 6, 12);
        // if value < key -> right 0x058

        // left:
        imem['h050 >> 2] = ADDI(8, 9, -1);
        // high = mid - 1

        imem['h054 >> 2] = JAL(0, -36);
        // -> search_loop 0x030

        // right:
        imem['h058 >> 2] = ADDI(7, 9, 1);
        // low = mid + 1

        imem['h05C >> 2] = JAL(0, -44);
        // -> search_loop 0x030

        // found:
        imem['h060 >> 2] = ADDI(12, 9, 0);
        // result = mid


        imem['h064 >> 2] = SLLI(11, 4, 2);
        imem['h068 >> 2] = ADD(11, 3, 11);
        imem['h06C >> 2] = SW(12, 11, 0);

        imem['h070 >> 2] = ADDI(4, 4, 1);
        // query++

        imem['h074 >> 2] = BLT(4, 5, -92);
        // -> query_loop 0x018

        imem['h078 >> 2] = 32'h00100073;
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

            expected[0]  = 0;
            expected[1]  = 31;
            expected[2]  = 15;
            expected[3]  = 7;
            expected[4]  = 23;
            expected[5]  = 1;
            expected[6]  = 29;
            expected[7]  = 9;

            expected[8]  = -1;
            expected[9]  = -1;
            expected[10] = -1;
            expected[11] = -1;
            expected[12] = -1;
            expected[13] = -1;
            expected[14] = -1;
            expected[15] = -1;

            errors = 0;

            for (int i = 0; i < NUM_SEARCHES; i++) begin

                if (
                    $signed(
                        dmem[(RESULT_BASE >> 2) + i]
                    ) !== expected[i]
                ) begin

                    $display(
                        "FAIL: search[%0d] result=%0d expected=%0d",
                        i,
                        $signed(
                            dmem[(RESULT_BASE >> 2) + i]
                        ),
                        expected[i]
                    );

                    errors++;

                end
            end

            if (errors == 0)
                $display(
                    "PASS: all 16 binary-search results verified"
                );
            else
                $display(
                    "FAIL: binary search had %0d errors",
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
            "\n[TB-BSEARCH] Binary Search benchmark starting..."
        );

        fork

            begin
                wait (halted_seen);

                $display(
                    "[TB-BSEARCH] EBREAK retired at T=%0t",
                    $time
                );
            end

            begin
                repeat (200000) @(posedge clk);

                $display(
                    "[TB-BSEARCH] FAIL: benchmark timed out"
                );
            end

        join_any

        disable fork;

        repeat (4) @(posedge clk);

        $display(
            "\n========== IPC (Binary Search) =========="
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