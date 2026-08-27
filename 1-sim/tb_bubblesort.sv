`timescale 1ns / 1ps

module tb_bubblesort();
    localparam CLK_PERIOD  = 10;
    localparam IMEM_WORDS  = 1024;
    localparam DMEM_WORDS  = 16384;
    localparam BASE        = 32'h0000_0000;

    logic clk, rst_n, cpu_enable;
    logic [31:0] imem_addr, imem_rdata;
    logic imem_req, imem_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0] dmem_wstrb;
    logic dmem_rd_en, dmem_wr_en, dmem_ready;
    logic [31:0] debug_pc, debug_instr, debug_reg_data;
    logic debug_halted;

    core_riscv_superscalar dut (
        .clk(clk), 
        .rst_n(rst_n), 
        .cpu_enable(cpu_enable),
        .imem_addr(imem_addr), 
        .imem_req(imem_req), 
        .imem_rdata(imem_rdata), 
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

    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [31:0] imem_index;
    assign imem_index = (imem_addr - BASE) >> 2;

    int MEM_LATENCY;
    initial begin
        if (!$value$plusargs("lat=%d", MEM_LATENCY)) MEM_LATENCY = 1;
        for (int i = 0; i < IMEM_WORDS; i++)
            imem[i] = 32'h00000013;

        // Bubble sort: sort array [5, 3, 8, 1, 9, 2] at addr 0x100
        // Simple 6-element bubble sort (2 passes)
        imem['h000 >> 2] = 32'h10000093; // addi x1, x0, 256    # base = 0x100
        imem['h004 >> 2] = 32'h00500113; // addi x2, x0, 5      # arr[0] = 5
        imem['h008 >> 2] = 32'h0020A023; // sw x2, 0(x1)
        imem['h00C >> 2] = 32'h00300113; // addi x2, x0, 3      # arr[1] = 3
        imem['h010 >> 2] = 32'h0020A223; // sw x2, 4(x1)
        imem['h014 >> 2] = 32'h00800113; // addi x2, x0, 8      # arr[2] = 8
        imem['h018 >> 2] = 32'h0020A423; // sw x2, 8(x1)
        imem['h01C >> 2] = 32'h00100113; // addi x2, x0, 1      # arr[3] = 1
        imem['h020 >> 2] = 32'h0020A623; // sw x2, 12(x1)
        imem['h024 >> 2] = 32'h00900113; // addi x2, x0, 9      # arr[4] = 9
        imem['h028 >> 2] = 32'h0020A823; // sw x2, 16(x1)
        imem['h02C >> 2] = 32'h00200113; // addi x2, x0, 2      # arr[5] = 2
        imem['h030 >> 2] = 32'h0020AA23; // sw x2, 20(x1)
        
        // Simple bubble: load, compare, swap if needed (simplified)
        imem['h034 >> 2] = 32'h0000A283; // lw x5, 0(x1)        # load arr[0]
        imem['h038 >> 2] = 32'h00408303; // lw x6, 4(x1)        # load arr[1]
        imem['h03C >> 2] = 32'h0060532E; // blt x5, x6, +8      # if arr[0] < arr[1], skip swap
        imem['h03C >> 2] = 32'h00605463; // blt x5, x6, 8       # if arr[0] < arr[1], skip
        imem['h040 >> 2] = 32'h0030A023; // sw x6, 0(x1)        # swap: arr[0] = arr[1]
        imem['h044 >> 2] = 32'h0050A223; // sw x5, 4(x1)        # arr[1] = arr[0]
        
        imem['h048 >> 2] = 32'h00100073; // ebreak
    end

    assign imem_rdata = (imem_index < IMEM_WORDS) ? imem[imem_index[$clog2(IMEM_WORDS)-1:0]] : 32'h00000013;

    int imem_cnt;
    assign imem_ready = imem_req && (imem_cnt == MEM_LATENCY-1);
    always_ff @(posedge clk) begin
        if (!imem_req) imem_cnt <= 0;
        else if (imem_ready) imem_cnt <= 0;
        else imem_cnt <= imem_cnt + 1;
    end

    logic [31:0] dmem [0:DMEM_WORDS-1];
    initial for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = 32'h0;
    assign dmem_rdata = dmem[dmem_addr[$clog2(DMEM_WORDS)+1:2]];

    int dmem_cnt;
    logic [31:0] dmem_idx;
    assign dmem_idx   = dmem_addr[$clog2(DMEM_WORDS)+1:2];
    assign dmem_ready = (dmem_rd_en || dmem_wr_en) && (dmem_cnt == MEM_LATENCY-1);
    always_ff @(posedge clk) begin
        if (!(dmem_rd_en || dmem_wr_en)) dmem_cnt <= 0;
        else if (dmem_ready) dmem_cnt <= 0;
        else dmem_cnt <= dmem_cnt + 1;
        if (dmem_wr_en && dmem_ready) begin
            if (dmem_wstrb[0]) dmem[dmem_idx][7:0] <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_idx][15:8] <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_idx][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_idx][31:24] <= dmem_wdata[31:24];
        end
    end

    function automatic [31:0] read_reg(input int unsigned n);
        read_reg = dut.rf.mem[n];
    endfunction

    longint cycle_count, retire_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            retire_count <= 0;
        end else begin
            if (cpu_enable && !debug_halted) begin
                cycle_count <= cycle_count + 1;
                if (dut.wb_valid && !dut.memwb_stall)
                    retire_count <= retire_count + 1;
            end
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

        $display("\n[TB-SORT] Bubble sort benchmark starting...");
        fork
            begin
                wait (debug_halted);
                $display("[TB-SORT] EBREAK retired at T=%0t", $time);
            end
            begin
                repeat (60000) @(posedge clk);
            end
        join_any
        disable fork;
        repeat (4) @(posedge clk);

        $display("\n========== IPC (Bubble Sort) ==========");
        $display("cycles=%0d  retired=%0d  IPC=%0.4f",
                 cycle_count, retire_count,
                 real'(retire_count) / real'(cycle_count));
        $finish;
    end

    initial begin
        #5000000;
        $display("[TIMEOUT]");
        $fatal;
    end

endmodule