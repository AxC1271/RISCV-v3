module gshare_predictor (
    input  logic[31:0] pc,
    input  logic[9:0] global_history,

    output logic prediction,

    input  logic[31:0] branch_pc,
    input  logic       actual_taken,
    output logic[9:0]  global_history_next
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule