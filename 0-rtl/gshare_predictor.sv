module gshare_predictor (
    input  logic       clk,
    input  logic       rst_n,
    input  logic[31:0] pc,
    input  logic[9:0]  global_history,
    output logic       prediction,

    input  logic[31:0] branch_pc,
    input  logic[9:0]  branch_history,
    input  logic       branch_taken,
    input  logic       branch_valid,
    output logic[9:0]  global_history_next
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */
    
    logic[1:0] pht [0:1023];
    logic[9:0] pht_rd_idx, pht_wr_idx;

    // just like bimodals, reads are combinational
    assign pht_rd_idx = pc[11:2] ^ global_history;
    assign pht_wr_idx = branch_pc[11:2] ^ branch_history;
    assign prediction = pht[pht_rd_idx][1];

    // updates are sequential
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 1024; i++)
                pht[i] <= 2'b00;
        end else if (branch_valid) begin

            // saturating counter update
            if (branch_taken && pht[pht_wr_idx] != 2'b11)
                pht[pht_wr_idx] <= pht[pht_wr_idx] + 2'b01;
            else if (!branch_taken && pht[pht_wr_idx] != 2'b00)
                pht[pht_wr_idx] <= pht[pht_wr_idx] - 2'b01;
        end
    end

    assign global_history_next = {global_history[8:0], branch_taken};

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule