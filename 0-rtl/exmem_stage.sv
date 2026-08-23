module exmem_stage (
    input  logic clk,
    input  logic rst_n,
    input  logic stall,

    input  logic[31:0] ex1_result,
    input  logic[31:0] ex1_store_data,  
    input  logic[4:0]  ex1_rd,
    input  logic[2:0]  ex1_funct3,    
    input  logic       ex1_memread,
    input  logic       ex1_memwrite,
    input  logic       ex1_memtoreg,
    input  logic       ex1_regwrite,
    input  logic       ex1_ebreak,
    input  logic       ex1_valid,

    input  logic[31:0] ex2_result,
    input  logic[31:0] ex2_store_data,  
    input  logic[4:0]  ex2_rd,
    input  logic[2:0]  ex2_funct3,    
    input  logic       ex2_memread,
    input  logic       ex2_memwrite,
    input  logic       ex2_memtoreg,
    input  logic       ex2_regwrite,
    input  logic       ex2_ebreak,
    input  logic       ex2_valid,

    output logic[31:0] mem1_alu_result,
    output logic[31:0] mem1_store_data,
    output logic[4:0]  mem1_rd,
    output logic[2:0]  mem1_funct3,
    output logic       mem1_memread,
    output logic       mem1_memwrite,
    output logic       mem1_memtoreg,
    output logic       mem1_regwrite,
    output logic       mem1_ebreak,
    output logic       mem1_valid,

    output logic[31:0] mem2_alu_result,
    output logic[31:0] mem2_store_data,
    output logic[4:0]  mem2_rd,
    output logic[2:0]  mem2_funct3,
    output logic       mem2_memread,
    output logic       mem2_memwrite,
    output logic       mem2_memtoreg,
    output logic       mem2_regwrite,
    output logic       mem2_ebreak,
    output logic       mem2_valid
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem1_alu_result <= 32'h0;
            mem1_store_data <= 32'b0;
            mem1_rd         <= 5'b0;
            mem1_funct3     <= 3'b0;
            mem1_memread    <= 1'b0;
            mem1_memwrite   <= 1'b0;
            mem1_memtoreg   <= 1'b0;
            mem1_regwrite   <= 1'b0;
            mem1_ebreak     <= 1'b0;
            mem1_valid      <= 1'b0;
            
            mem2_alu_result <= 32'h0;
            mem2_store_data <= 32'b0;
            mem2_rd         <= 5'b0;
            mem2_funct3     <= 3'b0;
            mem2_memread    <= 1'b0;
            mem2_memwrite   <= 1'b0;
            mem2_memtoreg   <= 1'b0;
            mem2_regwrite   <= 1'b0;
            mem2_ebreak     <= 1'b0;
            mem2_valid      <= 1'b0;
        end else if (stall) begin
            // hold
        end else begin
            mem1_alu_result <= ex1_result;
            mem1_store_data <= ex1_store_data;
            mem1_rd         <= ex1_rd;
            mem1_funct3     <= ex1_funct3;
            mem1_memread    <= ex1_memread;
            mem1_memwrite   <= ex1_memwrite;
            mem1_memtoreg   <= ex1_memtoreg;
            mem1_regwrite   <= ex1_regwrite;
            mem1_ebreak     <= ex1_ebreak;
            mem1_valid      <= ex1_valid;

            mem2_alu_result <= ex2_result;
            mem2_store_data <= ex2_store_data;
            mem2_rd         <= ex2_rd;
            mem2_funct3     <= ex2_funct3;
            mem2_memread    <= ex2_memread;
            mem2_memwrite   <= ex2_memwrite;
            mem2_memtoreg   <= ex2_memtoreg;
            mem2_regwrite   <= ex2_regwrite;
            mem2_ebreak     <= ex2_ebreak;
            mem2_valid      <= ex2_valid;
        end
    end

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule