module idex_stage (
    input  logic clk,
    input  logic rst_n,
    input  logic stall,
    input  logic flush,
    input  logic issue_0,
    input  logic issue_1,

    input  logic[31:0] id1_pc,
    input  logic[31:0] id1_instr,
    input  logic[31:0] id1_rs1_data,
    input  logic[31:0] id1_rs2_data,
    input  logic[31:0] id1_imm,
    input  logic[4:0]  id1_rs1,
    input  logic[4:0]  id1_rs2,
    input  logic[4:0]  id1_rd,
    input  logic[3:0]  id1_alu_opcode,
    input  logic[1:0]  id1_op_a_sel,
    input  logic       id1_alusrc,
    input  logic       id1_memread,
    input  logic       id1_memwrite,
    input  logic       id1_memtoreg,
    input  logic       id1_regwrite,
    input  logic       id1_branch,
    input  logic       id1_jump,
    input  logic       id1_jalr,
    input  logic       id1_ebreak,
    input  logic       id1_valid,

    input  logic[31:0] id2_pc,
    input  logic[31:0] id2_instr,
    input  logic[31:0] id2_rs1_data,
    input  logic[31:0] id2_rs2_data,
    input  logic[31:0] id2_imm,
    input  logic[4:0]  id2_rs1,
    input  logic[4:0]  id2_rs2,
    input  logic[4:0]  id2_rd,
    input  logic[3:0]  id2_alu_opcode,
    input  logic[1:0]  id2_op_a_sel,
    input  logic       id2_alusrc,
    input  logic       id2_memread,
    input  logic       id2_memwrite,
    input  logic       id2_memtoreg,
    input  logic       id2_regwrite,
    input  logic       id2_branch,
    input  logic       id2_jump,
    input  logic       id2_jalr,
    input  logic       id2_ebreak,
    input  logic       id2_valid,

    output logic[31:0] ex1_pc,
    output logic[31:0] ex1_instr,
    output logic[31:0] ex1_rs1_data,
    output logic[31:0] ex1_rs2_data,
    output logic[31:0] ex1_imm,
    output logic[4:0]  ex1_rs1,
    output logic[4:0]  ex1_rs2,
    output logic[4:0]  ex1_rd,
    output logic[3:0]  ex1_alu_opcode,
    output logic[1:0]  ex1_op_a_sel,
    output logic       ex1_alusrc,
    output logic       ex1_memread,
    output logic       ex1_memwrite,
    output logic       ex1_memtoreg,
    output logic       ex1_regwrite,
    output logic       ex1_branch,
    output logic       ex1_jump,
    output logic       ex1_jalr,
    output logic       ex1_ebreak,
    output logic       ex1_valid,

    output logic[31:0] ex2_pc,
    output logic[31:0] ex2_instr,
    output logic[31:0] ex2_rs1_data,
    output logic[31:0] ex2_rs2_data,
    output logic[31:0] ex2_imm,
    output logic[4:0]  ex2_rs1,
    output logic[4:0]  ex2_rs2,
    output logic[4:0]  ex2_rd,
    output logic[3:0]  ex2_alu_opcode,
    output logic[1:0]  ex2_op_a_sel,
    output logic       ex2_alusrc,
    output logic       ex2_memread,
    output logic       ex2_memwrite,
    output logic       ex2_memtoreg,
    output logic       ex2_regwrite,
    output logic       ex2_branch,
    output logic       ex2_jump,
    output logic       ex2_jalr,
    output logic       ex2_ebreak,
    output logic       ex2_valid
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