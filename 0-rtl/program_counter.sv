module program_counter # (
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input  logic clk,
    input  logic rst_n,
    input  logic pc_write,
    input  logic[31:0] pc_in,
    output logic[31:0] pc_out
);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_out <= RESET_VECTOR;
        end else if (pc_write) begin
            pc_out <= pc_in;
        end
    end
endmodule