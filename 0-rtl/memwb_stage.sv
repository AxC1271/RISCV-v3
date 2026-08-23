module memwb_stage (
    input  logic clk,
    input  logic rst_n,
    input  logic stall,
    input  logic [31:0] mem1_alu_result,
    input  logic [31:0] mem1_rdata,      
    input  logic [4:0]  mem1_rd,
    input  logic        mem1_regwrite,
    input  logic        mem1_memtoreg,
    input  logic        mem1_ebreak,
    input  logic        mem1_valid,

    input  logic [31:0] mem2_alu_result,
    input  logic [31:0] mem2_rdata,      
    input  logic [4:0]  mem2_rd,
    input  logic        mem2_regwrite,
    input  logic        mem2_memtoreg,
    input  logic        mem2_ebreak,
    input  logic        mem2_valid,

    output logic [31:0] wb1_alu_result,
    output logic [31:0] wb1_rdata,
    output logic [4:0]  wb1_rd,
    output logic        wb1_regwrite,
    output logic        wb1_memtoreg,
    output logic        wb1_ebreak,
    output logic        wb1_valid,

    output logic [31:0] wb2_alu_result,
    output logic [31:0] wb2_rdata,
    output logic [4:0]  wb2_rd,
    output logic        wb2_regwrite,
    output logic        wb2_memtoreg,
    output logic        wb2_ebreak,
    output logic        wb2_valid
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wb1_alu_result <= 32'h0;
            wb1_rdata      <= 32'h0;
            wb1_rd         <= 5'h0;
            wb1_regwrite   <= 1'b0;
            wb1_memtoreg   <= 1'b0;
            wb1_ebreak     <= 1'b0;
            wb1_valid      <= 1'b0;

            wb2_alu_result <= 32'h0;
            wb2_rdata      <= 32'h0;
            wb2_rd         <= 5'h0;
            wb2_regwrite   <= 1'b0;
            wb2_memtoreg   <= 1'b0;
            wb2_ebreak     <= 1'b0;
            wb2_valid      <= 1'b0;
        end else if (stall) begin
            // hold
        end else begin
            wb1_alu_result <= mem1_alu_result;
            wb1_rdata      <= mem1_rdata;
            wb1_rd         <= mem1_rd;
            wb1_regwrite   <= mem1_regwrite;
            wb1_memtoreg   <= mem1_memtoreg;
            wb1_ebreak     <= mem1_ebreak;
            wb1_valid      <= mem1_valid;

            wb2_alu_result <= mem2_alu_result;
            wb2_rdata      <= mem2_rdata;
            wb2_rd         <= mem2_rd;
            wb2_regwrite   <= mem2_regwrite;
            wb2_memtoreg   <= mem2_memtoreg;
            wb2_ebreak     <= mem2_ebreak;
            wb2_valid      <= mem2_valid;
        end
    end

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */


endmodule