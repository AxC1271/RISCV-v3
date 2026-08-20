module program_counter # (
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input  logic clk,
    input  logic rst_n,
    input  logic pc_write,
    input  logic[31:0] pc_in,
    output logic[31:0] pc_out
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_out <= RESET_VECTOR;
        end else if (pc_write) begin
            pc_out <= pc_in;
        end
    end

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule