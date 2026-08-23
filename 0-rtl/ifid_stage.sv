module ifid_stage (
    input  logic clk,
    input  logic rst_n,
    input  logic stall,
    input  logic flush,
    input  logic[31:0] if1_pc,
    input  logic[31:0] if1_instr,
    input  logic       if1_valid,
    input  logic[31:0] if2_pc,
    input  logic[31:0] if2_instr,
    input  logic       if2_valid,
    output logic[31:0] id1_pc,
    output logic[31:0] id1_instr,
    output logic       id1_valid,
    output logic[31:0] id2_pc,
    output logic[31:0] id2_instr,
    output logic       id2_valid
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    always_ff @(posedge clk) begin
        if (!rst_n || flush) begin
            id1_pc    <= 32'h0;
            id1_instr <= 32'h00000013;
            id1_valid <= 1'b0;  
            id2_pc    <= 32'h0;
            id2_instr <= 32'h00000013;
            id2_valid <= 1'b0;           
        end else if (stall) begin
            // hold
        end else begin
            id1_pc    <= if1_pc;
            id1_instr <= if1_instr;
            id1_valid <= if1_valid;
            id2_pc    <= if2_pc;
            id2_instr <= if2_instr;
            id2_valid <= if2_valid;
        end
    end

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule