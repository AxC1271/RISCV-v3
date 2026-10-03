module nt_predictor (
    input  logic[31:0] pc,
    output logic       prediction
    );
        // the test control: always not taken
        assign prediction = 1'b0;
    endmodule