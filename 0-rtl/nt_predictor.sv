module nt_predictor (
    input  logic[31:0] pc,
    output logic       prediction
    );
    
        /*
        1. All of my RTL logic lives here
        2. All combinational/registered logic are defined here
        3. Use these during testbenches/simulations 
        */

        // the test control: always not taken
        assign prediction = 1'b0;
    
        /*
        1. My formal properties live here
        2. All asserts, assumes, and covers are defined here
        3. Use these during SymbiYosys for formal verification
        */
    
    endmodule