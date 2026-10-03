module branch_unit (
    input logic [31:0] rs1_data,
    input logic [31:0] rs2_data,
    input logic branch,          
    input logic [2:0] funct3,

    // curr pc and target
    input logic [31:0] pc,
    input logic [31:0] imm, // branch offset
    
    // outputs
    output logic branch_taken,      
    output logic [31:0] branch_target
);

    logic condition_met;
    
    // compute branch condition
    always_comb begin
        case (funct3)
            3'b000: condition_met = (rs1_data == rs2_data);                    // BEQ
            3'b001: condition_met = (rs1_data != rs2_data);                    // BNE
            3'b100: condition_met = ($signed(rs1_data) < $signed(rs2_data));   // BLT
            3'b101: condition_met = ($signed(rs1_data) >= $signed(rs2_data));  // BGE
            3'b110: condition_met = (rs1_data < rs2_data);                     // BLTU
            3'b111: condition_met = (rs1_data >= rs2_data);                    // BGEU
            default: condition_met = 1'b0;
        endcase
    end
    
    assign branch_taken = branch && condition_met;
    assign branch_target = pc + imm;

endmodule