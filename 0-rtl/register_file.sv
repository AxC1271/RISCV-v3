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

    

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule