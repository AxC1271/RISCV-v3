module register_file (
    input  logic clk,
    input  logic rst_n,

    // read ports, dual 
    input  logic[4:0]  rd1_addr1,
    input  logic[4:0]  rd1_addr2,
    input  logic[4:0]  rd2_addr1,
    input  logic[4:0]  rd2_addr2,
    output logic[31:0] rd1_data1,
    output logic[31:0] rd1_data2,
    output logic[31:0] rd2_data1,
    output logic[31:0] rd2_data2,

    // write ports, also dual
    input  logic[4:0]  wr1_addr,
    input  logic[4:0]  wr2_addr,
    input  logic[31:0] wr1_data,
    input  logic[31:0] wr2_data,
    input  logic       reg1_write,
    input  logic       reg2_write
);
    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    // define the same 32 architectural registers
    logic[31:0] registers [0:31];
    logic bypass_wr1_rd1_1, bypass_wr1_rd1_2; 
    logic bypass_wr2_rd1_1, bypass_wr2_rd1_2;
    logic bypass_wr1_rd2_1, bypass_wr1_rd2_2;
    logic bypass_wr2_rd2_1, bypass_wr2_rd2_2;

    // rd1_data1 (instr_0, rs1)
    assign bypass_wr1_rd1_1 = reg1_write && (wr1_addr == rd1_addr1) && (rd1_addr1 != 5'b0);
    assign bypass_wr2_rd1_1 = reg2_write && (wr2_addr == rd1_addr1) && (rd1_addr1 != 5'b0);

    // rd1_data2 (instr_0, rs2)
    assign bypass_wr1_rd1_2 = reg1_write && (wr1_addr == rd1_addr2) && (rd1_addr2 != 5'b0);
    assign bypass_wr2_rd1_2 = reg2_write && (wr2_addr == rd1_addr2) && (rd1_addr2 != 5'b0);

    // rd2_data1 (instr_1, rs1)
    assign bypass_wr1_rd2_1 = reg1_write && (wr1_addr == rd2_addr1) && (rd2_addr1 != 5'b0);
    assign bypass_wr2_rd2_1 = reg2_write && (wr2_addr == rd2_addr1) && (rd2_addr1 != 5'b0);

    // rd2_data2 (instr_1, rs2)
    assign bypass_wr1_rd2_2 = reg1_write && (wr1_addr == rd2_addr2) && (rd2_addr2 != 5'b0);
    assign bypass_wr2_rd2_2 = reg2_write && (wr2_addr == rd2_addr2) && (rd2_addr2 != 5'b0);

    // make the writes clocked
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                registers[i] <= 32'h0;
            end
        end else begin
            if (reg1_write && (wr1_addr != 5'b0)) begin
                registers[wr1_addr] <= wr1_data;
            end 
            if (reg2_write && (wr2_addr != 5'b0) && (wr2_addr != wr1_addr)) begin
                registers[wr2_addr] <= wr2_data;
            end
        end
    end

    // make the reads combinational
    assign rd1_data1 = (rd1_addr1 == 5'b0) ? 32'b0 :
                   bypass_wr1_rd1_1 ? wr1_data :
                   bypass_wr2_rd1_1 ? wr2_data :
                   registers[rd1_addr1];

    assign rd1_data2 = (rd1_addr2 == 5'b0) ? 32'b0 :
                    bypass_wr1_rd1_2 ? wr1_data :
                    bypass_wr2_rd1_2 ? wr2_data :
                    registers[rd1_addr2];

    assign rd2_data1 = (rd2_addr1 == 5'b0) ? 32'b0 :
                    bypass_wr1_rd2_1 ? wr1_data :
                    bypass_wr2_rd2_1 ? wr2_data :
                    registers[rd2_addr1];

    assign rd2_data2 = (rd2_addr2 == 5'b0) ? 32'b0 :
                    bypass_wr1_rd2_2 ? wr1_data :
                    bypass_wr2_rd2_2 ? wr2_data :
                    registers[rd2_addr2];
    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule