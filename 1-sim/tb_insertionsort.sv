`timescale 1ns / 1ps

module tb_insertionsort();

    localparam CLK_PERIOD = 10;
    localparam IMEM_WORDS = 1024;
    localparam DMEM_WORDS = 16384;
    localparam BASE       = 32'h0000_0000;
    localparam DATA_BASE  = 32'h0000_0400;
    localparam N          = 16;

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

    function automatic [31:0] BGE(
        input [4:0] rs1,
        input [4:0] rs2,
        input integer imm
    );
        BGE = enc_b(
            imm,
            rs2,
            rs1,
            3'b101
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

    assign imem_index  = (imem_addr - BASE) >> 2;
    assign imem_index2 = imem_index + 1;

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
        imem_req && (imem_cnt == MEM_LATENCY - 1);

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
                dmem[dmem_idx][7:0] <= dmem_wdata[7:0];

            if (dmem_wstrb[1])
                dmem[dmem_idx][15:8] <= dmem_wdata[15:8];

            if (dmem_wstrb[2])
                dmem[dmem_idx][23:16] <= dmem_wdata[23:16];

            if (dmem_wstrb[3])
                dmem[dmem_idx][31:24] <= dmem_wdata[31:24];
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

        // Reversed input:
        //
        // 16, 15, 14, ... 2, 1
        //
        // This is intentionally branch-heavy for insertion sort.

        for (int i = 0; i < N; i++)
            dmem[(DATA_BASE >> 2) + i] = N - i;

        // Register allocation:
        //
        // x1 = base address
        // x2 = N
        // x3 = i
        // x4 = key
        // x5 = j
        // x6 = address
        // x7 = a[j]

        imem['h000 >> 2] = ADDI(1, 0, 1024);  // x1 = 0x400
        imem['h004 >> 2] = ADDI(2, 0, 16);    // x2 = N
        imem['h008 >> 2] = ADDI(3, 0, 1);     // i = 1

        // outer: 0x00C

        imem['h00C >> 2] = SLLI(6, 3, 2);     // x6 = i * 4
        imem['h010 >> 2] = ADD(6, 1, 6);      // x6 = &a[i]
        imem['h014 >> 2] = LW(4, 6, 0);       // key = a[i]
        imem['h018 >> 2] = ADDI(5, 3, -1);    // j = i - 1

        // inner_test: 0x01C

        imem['h01C >> 2] = BLT(5, 0, 32);
        // if j < 0 -> insert at 0x03C

        imem['h020 >> 2] = SLLI(6, 5, 2);
        imem['h024 >> 2] = ADD(6, 1, 6);
        imem['h028 >> 2] = LW(7, 6, 0);       // x7 = a[j]

        imem['h02C >> 2] = BGE(4, 7, 16);
        // if key >= a[j] -> insert at 0x03C

        imem['h030 >> 2] = SW(7, 6, 4);
        // a[j + 1] = a[j]

        imem['h034 >> 2] = ADDI(5, 5, -1);
        // j--

        imem['h038 >> 2] = JAL(0, -28);
        // back to 0x01C

        // insert: 0x03C

        imem['h03C >> 2] = ADDI(5, 5, 1);
        imem['h040 >> 2] = SLLI(6, 5, 2);
        imem['h044 >> 2] = ADD(6, 1, 6);
        imem['h048 >> 2] = SW(4, 6, 0);

        imem['h04C >> 2] = ADDI(3, 3, 1);
        // i++

        imem['h050 >> 2] = BLT(3, 2, -68);
        // if i < N -> outer at 0x00C

        imem['h054 >> 2] = 32'h00100073;
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

        int errors;

        begin

            errors = 0;

            for (int i = 0; i < N; i++) begin

                if (dmem[(DATA_BASE >> 2) + i] !== (i + 1)) begin

                    $display(
                        "FAIL: a[%0d]=%0d expected=%0d",
                        i,
                        dmem[(DATA_BASE >> 2) + i],
                        i + 1
                    );

                    errors++;

                end
            end

            if (errors == 0)
                $display(
                    "PASS: 16-element insertion sort verified"
                );
            else
                $display(
                    "FAIL: insertion sort had %0d errors",
                    errors
                );

        end
    endtask

    // ------------------------------------------------------------
    // Simulation
    // ------------------------------------------------------------

    initial begin

        rst_n = 1'b0;
        cpu_enable = 1'b0;

        #1;

        repeat (5) @(posedge clk);

        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        cpu_enable = 1'b1;

        $display(
            "\n[TB-INSERT] Insertion Sort benchmark starting..."
        );

        fork

            begin
                wait (halted_seen);

                $display(
                    "[TB-INSERT] EBREAK retired at T=%0t",
                    $time
                );
            end

            begin
                repeat (200000) @(posedge clk);

                $display(
                    "[TB-INSERT] FAIL: benchmark timed out"
                );
            end

        join_any

        disable fork;

        repeat (4) @(posedge clk);

        $display(
            "\n========== IPC (Insertion Sort) =========="
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