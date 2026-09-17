`timescale 1ns / 1ps

module tb_string_search();

    localparam CLK_PERIOD = 10;
    localparam IMEM_WORDS = 1024;
    localparam DMEM_WORDS = 16384;
    localparam BASE       = 32'h0000_0000;

    localparam HAYSTACK_BASE = 32'h0000_0400;
    localparam NEEDLE_BASE   = 32'h0000_0800;
    localparam RESULT_BASE   = 32'h0000_0C00;

    localparam NUM_SEARCHES = 16;

    logic clk, rst_n, cpu_enable;
    logic [1:0] predictor_sel;

    logic [31:0] imem_addr;
    logic [31:0] imem_rdata1;
    logic [31:0] imem_rdata2;
    logic imem_req;
    logic imem_ready;

    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [31:0] dmem_rdata;
    logic [3:0]  dmem_wstrb;
    logic dmem_rd_en;
    logic dmem_wr_en;
    logic dmem_ready;

    logic [31:0] debug_pc;
    logic [31:0] debug_instr;
    logic [31:0] debug_reg_data;
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
        clk = 1'b0;
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
        JAL = enc_j(
            imm,
            rd
        );
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
        ? imem[
            imem_index[$clog2(IMEM_WORDS)-1:0]
          ]
        : 32'h00100073;

    assign imem_rdata2 =
        (imem_index2 < IMEM_WORDS)
        ? imem[
            imem_index2[$clog2(IMEM_WORDS)-1:0]
          ]
        : 32'h00100073;

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
        dmem[
            dmem_addr[$clog2(DMEM_WORDS)+1:2]
        ];

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

    // ============================================================
    // TEST DATA
    // ============================================================

    // Each test uses the same haystack:
    //
    //     ABABABABABABABAC
    //
    // 16 characters long.
    //
    // Instead of storing 16 different needles in separate memory
    // regions, this benchmark uses a table of:
    //
    //     needle_start
    //     needle_length
    //     expected_result
    //
    // Needles are stored sequentially beginning at NEEDLE_BASE.
    //
    // The benchmark performs 16 independent substring searches.

    integer expected [0:NUM_SEARCHES-1];


    task automatic write_char(
        input integer word_addr,
        input [7:0] c
    );
        begin
            dmem[word_addr] = {24'b0, c};
        end
    endtask

    initial begin : initialize_test

        integer h;
        integer n;
        integer table_base;

        if (!$value$plusargs("lat=%d", MEM_LATENCY))
            MEM_LATENCY = 1;

        if (!$value$plusargs("pred=%d", PREDICTOR))
            PREDICTOR = 2;

        predictor_sel = PREDICTOR[1:0];

        for (int i = 0; i < IMEM_WORDS; i++)
            imem[i] = 32'h00100073;

        for (int i = 0; i < DMEM_WORDS; i++)
            dmem[i] = 32'h00000000;

        // ========================================================
        // HAYSTACK
        //
        // "ABABABABABABABAC"
        // ========================================================

        h = HAYSTACK_BASE >> 2;

        write_char(h +  0, "A");
        write_char(h +  1, "B");
        write_char(h +  2, "A");
        write_char(h +  3, "B");
        write_char(h +  4, "A");
        write_char(h +  5, "B");
        write_char(h +  6, "A");
        write_char(h +  7, "B");
        write_char(h +  8, "A");
        write_char(h +  9, "B");
        write_char(h + 10, "A");
        write_char(h + 11, "B");
        write_char(h + 12, "A");
        write_char(h + 13, "B");
        write_char(h + 14, "A");
        write_char(h + 15, "C");

        // ========================================================
        // NEEDLES
        //
        // Store all needles sequentially.
        //
        // Search cases intentionally include:
        //
        // - immediate matches
        // - matches near the end
        // - long partial matches
        // - complete misses
        // - repeated AB patterns
        //
        // This is still a normal naive substring-search workload,
        // but it provides meaningful branch-history behavior.
        // ========================================================

        n = NEEDLE_BASE >> 2;

        // --------------------------------------------------------
        // 0: "ABABAC"
        //
        // Match begins at index 10.
        // --------------------------------------------------------

        write_char(n + 0, "A");
        write_char(n + 1, "B");
        write_char(n + 2, "A");
        write_char(n + 3, "B");
        write_char(n + 4, "A");
        write_char(n + 5, "C");

        expected[0] = 10;

        // --------------------------------------------------------
        // 1: "ABAC"
        //
        // Match begins at index 12.
        // --------------------------------------------------------

        write_char(n + 6, "A");
        write_char(n + 7, "B");
        write_char(n + 8, "A");
        write_char(n + 9, "C");

        expected[1] = 12;

        // --------------------------------------------------------
        // 2: "BAC"
        //
        // Match begins at index 13.
        // --------------------------------------------------------

        write_char(n + 10, "B");
        write_char(n + 11, "A");
        write_char(n + 12, "C");

        expected[2] = 13;

        // --------------------------------------------------------
        // 3: "AC"
        //
        // Match begins at index 14.
        // --------------------------------------------------------

        write_char(n + 13, "A");
        write_char(n + 14, "C");

        expected[3] = 14;

        // --------------------------------------------------------
        // 4: "ABAB"
        //
        // Immediate match at 0.
        // --------------------------------------------------------

        write_char(n + 15, "A");
        write_char(n + 16, "B");
        write_char(n + 17, "A");
        write_char(n + 18, "B");

        expected[4] = 0;

        // --------------------------------------------------------
        // 5: "BABA"
        //
        // Match at 1.
        // --------------------------------------------------------

        write_char(n + 19, "B");
        write_char(n + 20, "A");
        write_char(n + 21, "B");
        write_char(n + 22, "A");

        expected[5] = 1;

        // --------------------------------------------------------
        // 6: "C"
        //
        // Match at final character.
        // --------------------------------------------------------

        write_char(n + 23, "C");

        expected[6] = 15;

        // --------------------------------------------------------
        // 7: "A"
        // --------------------------------------------------------

        write_char(n + 24, "A");

        expected[7] = 0;

        // --------------------------------------------------------
        // 8: "ABABAD"
        //
        // Long partial matches, but no complete match.
        // --------------------------------------------------------

        write_char(n + 25, "A");
        write_char(n + 26, "B");
        write_char(n + 27, "A");
        write_char(n + 28, "B");
        write_char(n + 29, "A");
        write_char(n + 30, "D");

        expected[8] = -1;

        // --------------------------------------------------------
        // 9: "ABABABAD"
        //
        // Even longer partial matches.
        // --------------------------------------------------------

        write_char(n + 31, "A");
        write_char(n + 32, "B");
        write_char(n + 33, "A");
        write_char(n + 34, "B");
        write_char(n + 35, "A");
        write_char(n + 36, "B");
        write_char(n + 37, "A");
        write_char(n + 38, "D");

        expected[9] = -1;

        // --------------------------------------------------------
        // 10: "D"
        // --------------------------------------------------------

        write_char(n + 39, "D");

        expected[10] = -1;

        // --------------------------------------------------------
        // 11: "BC"
        //
        // Match at 13? No:
        // index 13 = B
        // index 14 = A
        //
        // So no BC sequence exists.
        // --------------------------------------------------------

        write_char(n + 40, "B");
        write_char(n + 41, "C");

        expected[11] = -1;

        // --------------------------------------------------------
        // 12: "ABABAB"
        // --------------------------------------------------------

        write_char(n + 42, "A");
        write_char(n + 43, "B");
        write_char(n + 44, "A");
        write_char(n + 45, "B");
        write_char(n + 46, "A");
        write_char(n + 47, "B");

        expected[12] = 0;

        // --------------------------------------------------------
        // 13: "BABAB"
        // --------------------------------------------------------

        write_char(n + 48, "B");
        write_char(n + 49, "A");
        write_char(n + 50, "B");
        write_char(n + 51, "A");
        write_char(n + 52, "B");

        expected[13] = 1;

        // --------------------------------------------------------
        // 14: "ABABABAC"
        //
        // Match at index 8.
        // --------------------------------------------------------

        write_char(n + 53, "A");
        write_char(n + 54, "B");
        write_char(n + 55, "A");
        write_char(n + 56, "B");
        write_char(n + 57, "A");
        write_char(n + 58, "B");
        write_char(n + 59, "A");
        write_char(n + 60, "C");

        expected[14] = 8;

        // --------------------------------------------------------
        // 15: "ABABABABAC"
        //
        // Match at index 6.
        // --------------------------------------------------------

        write_char(n + 61, "A");
        write_char(n + 62, "B");
        write_char(n + 63, "A");
        write_char(n + 64, "B");
        write_char(n + 65, "A");
        write_char(n + 66, "B");
        write_char(n + 67, "A");
        write_char(n + 68, "B");
        write_char(n + 69, "A");
        write_char(n + 70, "C");

        expected[15] = 6;

        // ========================================================
        // SEARCH DESCRIPTOR TABLE
        //
        // Located at 0x1000.
        //
        // Each entry:
        //
        //   +0  needle word offset
        //   +4  needle length
        //
        // Two words per search.
        // ========================================================

        table_base = 32'h1000 >> 2;

        // needle offset, length

        dmem[table_base +  0] = 0;
        dmem[table_base +  1] = 6;

        dmem[table_base +  2] = 6;
        dmem[table_base +  3] = 4;

        dmem[table_base +  4] = 10;
        dmem[table_base +  5] = 3;

        dmem[table_base +  6] = 13;
        dmem[table_base +  7] = 2;

        dmem[table_base +  8] = 15;
        dmem[table_base +  9] = 4;

        dmem[table_base + 10] = 19;
        dmem[table_base + 11] = 4;

        dmem[table_base + 12] = 23;
        dmem[table_base + 13] = 1;

        dmem[table_base + 14] = 24;
        dmem[table_base + 15] = 1;

        dmem[table_base + 16] = 25;
        dmem[table_base + 17] = 6;

        dmem[table_base + 18] = 31;
        dmem[table_base + 19] = 8;

        dmem[table_base + 20] = 39;
        dmem[table_base + 21] = 1;

        dmem[table_base + 22] = 40;
        dmem[table_base + 23] = 2;

        dmem[table_base + 24] = 42;
        dmem[table_base + 25] = 6;

        dmem[table_base + 26] = 48;
        dmem[table_base + 27] = 5;

        dmem[table_base + 28] = 53;
        dmem[table_base + 29] = 8;

        dmem[table_base + 30] = 61;
        dmem[table_base + 31] = 10;

        // ========================================================
        // RV32I PROGRAM
        // ========================================================
        //
        // Equivalent high-level operation:
        //
        // for each needle:
        //
        //     result = -1;
        //
        //     for (i = 0; i <= HLEN - NLEN; i++) {
        //
        //         j = 0;
        //
        //         while (j < NLEN &&
        //                haystack[i+j] == needle[j]) {
        //             j++;
        //         }
        //
        //         if (j == NLEN) {
        //             result = i;
        //             break;
        //         }
        //     }
        //
        //     results[q] = result;
        //
        // ========================================================

        // --------------------------------------------------------
        // Register allocation
        //
        // x1  = haystack base       0x400
        // x2  = needle base         0x800
        // x3  = result base         0xC00
        // x4  = descriptor base     0x1000
        //
        // x5  = query index
        // x6  = number searches
        //
        // x7  = needle pointer
        // x8  = needle length
        // x9  = max starting index
        //
        // x10 = i
        // x11 = j
        // x12 = temporary address
        // x13 = haystack character
        // x14 = needle character
        // x15 = result
        // x16 = temporary
        // --------------------------------------------------------

        // 0x000
        imem['h000 >> 2] = ADDI(1, 0, 1024);
        // x1 = 0x400

        // 0x004
        imem['h004 >> 2] = ADDI(2, 1, 1024);
        // x2 = 0x800

        // 0x008
        imem['h008 >> 2] = ADDI(3, 2, 1024);
        // x3 = 0xC00

        // 0x00C
        imem['h00C >> 2] = ADDI(4, 0, 1024);
        // temporary x4 = 0x400

        // 0x010
        imem['h010 >> 2] = SLLI(4, 4, 2);
        // x4 = 0x1000 descriptor table

        // 0x014
        imem['h014 >> 2] = ADDI(5, 0, 0);
        // query = 0

        // 0x018
        imem['h018 >> 2] = ADDI(6, 0, NUM_SEARCHES);
        // number searches

        // 0x01C
        imem['h01C >> 2] = SLLI(12, 5, 3);

        // 0x020
        imem['h020 >> 2] = ADD(12, 4, 12);

        // Load needle word offset.

        // 0x024
        imem['h024 >> 2] = LW(16, 12, 0);

        // Load needle length.

        // 0x028
        imem['h028 >> 2] = LW(8, 12, 4);

        // needle_ptr = needle_base + offset * 4

        // 0x02C
        imem['h02C >> 2] = SLLI(16, 16, 2);

        // 0x030
        imem['h030 >> 2] = ADD(7, 2, 16);

        // max_i = 16 - needle_length

        // 0x034
        imem['h034 >> 2] = ADDI(9, 0, 16);

        // 0x038
        imem['h038 >> 2] = enc_r(
            7'b0100000,
            8,
            9,
            3'b000,
            9,
            7'b0110011
        );
        // SUB x9, x9, x8

        // result = -1

        // 0x03C
        imem['h03C >> 2] = ADDI(15, 0, -1);

        // i = 0

        // 0x040
        imem['h040 >> 2] = ADDI(10, 0, 0);

        // 0x044
        imem['h044 >> 2] = BLT(9, 10, 76);
        // -> 0x090

        // j = 0

        // 0x048
        imem['h048 >> 2] = ADDI(11, 0, 0);

        // 0x04C
        imem['h04C >> 2] = BEQ(11, 8, 56);
        // -> 0x084

        // haystack address:
        //
        // (i + j) * 4 + haystack_base

        // 0x050
        imem['h050 >> 2] = ADD(12, 10, 11);

        // 0x054
        imem['h054 >> 2] = SLLI(12, 12, 2);

        // 0x058
        imem['h058 >> 2] = ADD(12, 1, 12);

        // 0x05C
        imem['h05C >> 2] = LW(13, 12, 0);

        // needle address = needle_ptr + j*4

        // 0x060
        imem['h060 >> 2] = SLLI(12, 11, 2);

        // 0x064
        imem['h064 >> 2] = ADD(12, 7, 12);

        // 0x068
        imem['h068 >> 2] = LW(14, 12, 0);

        // mismatch?
        //
        // if haystack_char != needle_char -> next_i

        // 0x06C
        imem['h06C >> 2] = BNE(13, 14, 16);
        // -> 0x07C

        // j++

        // 0x070
        imem['h070 >> 2] = ADDI(11, 11, 1);

        // continue comparison

        // 0x074
        imem['h074 >> 2] = JAL(0, -40);
        // -> 0x04C

        // Padding / unreachable EBREAK at 0x078
        imem['h078 >> 2] = 32'h00100073;

        imem['h07C >> 2] = ADDI(10, 10, 1);

        // back to outer loop

        imem['h080 >> 2] = JAL(0, -60);
        // -> 0x044

        // result = i

        imem['h084 >> 2] = ADDI(15, 10, 0);

        // jump to store_result

        imem['h088 >> 2] = JAL(0, 8);
        // -> 0x090

        // Padding
        imem['h08C >> 2] = 32'h00100073;

        // result address = RESULT_BASE + query*4

        imem['h090 >> 2] = SLLI(12, 5, 2);

        imem['h094 >> 2] = ADD(12, 3, 12);

        imem['h098 >> 2] = SW(15, 12, 0);

        // query++

        imem['h09C >> 2] = ADDI(5, 5, 1);

        // if query < NUM_SEARCHES -> query_loop

        imem['h0A0 >> 2] = BLT(5, 6, -132);
        // 0x0A0 - 132 = 0x01C

        // Done

        imem['h0A4 >> 2] = 32'h00100073;
        // EBREAK
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

        end
        else if (cpu_enable && !halted_seen) begin

            cycle_count <= cycle_count + 1;

            retire_count <= retire_count
                + (
                    (dut.wb1_valid &&
                     !dut.wb1_ebreak)
                    ? 1 : 0
                  )
                + (
                    (dut.wb2_valid &&
                     !dut.wb2_ebreak &&
                     !(dut.wb1_valid &&
                       dut.wb1_ebreak))
                    ? 1 : 0
                  );

            if (dut.branch_update_valid)
                branch_count <= branch_count + 1;

            if (dut.mispredict)
                mispredict_count <=
                    mispredict_count + 1;

            if (
                debug_halted ||
                (dut.wb1_valid && dut.wb1_ebreak) ||
                (dut.wb2_valid && dut.wb2_ebreak)
            )
                halted_seen <= 1'b1;
        end
    end


    task automatic check_results;

        int errors;
        integer actual;

        begin

            errors = 0;

            for (int i = 0; i < NUM_SEARCHES; i++) begin

                actual =
                    $signed(
                        dmem[
                            (RESULT_BASE >> 2) + i
                        ]
                    );

                if (actual !== expected[i]) begin

                    $display(
                        "FAIL: search[%0d] result=%0d expected=%0d",
                        i,
                        actual,
                        expected[i]
                    );

                    errors++;
                end
            end

            if (errors == 0) begin

                $display(
                    "PASS: all %0d substring-search results verified",
                    NUM_SEARCHES
                );

            end
            else begin

                $display(
                    "FAIL: substring search had %0d errors",
                    errors
                );

            end
        end
    endtask


    task automatic print_results;

        begin

            $display(
                "\nSubstring search results:"
            );

            for (int i = 0; i < NUM_SEARCHES; i++) begin

                $display(
                    "  search[%0d] -> %0d",
                    i,
                    $signed(
                        dmem[
                            (RESULT_BASE >> 2) + i
                        ]
                    )
                );

            end
        end
    endtask

    initial begin

        rst_n      = 1'b0;
        cpu_enable = 1'b0;

        #1;

        repeat (5)
            @(posedge clk);

        rst_n = 1'b1;

        repeat (2)
            @(posedge clk);

        cpu_enable = 1'b1;

        $display(
            "\n[TB-STRSTR] String Search benchmark starting..."
        );

        $display(
            "[TB-STRSTR] predictor=%0d memory_latency=%0d",
            PREDICTOR,
            MEM_LATENCY
        );

        fork

            begin

                wait (halted_seen);

                $display(
                    "[TB-STRSTR] EBREAK retired at T=%0t",
                    $time
                );

            end

            begin

                repeat (200000)
                    @(posedge clk);

                $display(
                    "[TB-STRSTR] FAIL: benchmark timed out"
                );

            end

        join_any

        disable fork;

        repeat (4)
            @(posedge clk);

        $display(
            "\n========== IPC (String Search) =========="
        );

        $display(
            "cycles=%0d  retired=%0d  IPC=%0.4f",
            cycle_count,
            retire_count,
            cycle_count
                ? real'(retire_count) /
                  real'(cycle_count)
                : 0.0
        );

        $display(
            "predictor=%0d  branches=%0d  mispredicts=%0d  accuracy=%0.2f%%",
            PREDICTOR,
            branch_count,
            mispredict_count,
            branch_count
                ? 100.0 *
                  real'(
                      branch_count -
                      mispredict_count
                  ) /
                  real'(branch_count)
                : 0.0
        );

        check_results();

        if ($test$plusargs("results"))
            print_results();

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