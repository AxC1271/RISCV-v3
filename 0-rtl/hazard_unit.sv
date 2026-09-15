module hazard_unit (
    // decode stage - instruction 1 (older)
    input  logic       id1_valid,
    input  logic [4:0] id1_rd,
    input  logic [4:0] id1_rs1,
    input  logic [4:0] id1_rs2,
    input  logic       id1_regwrite,
    input  logic       id1_isbranch,
    input  logic       id1_uses_rs1,
    input  logic       id1_uses_rs2,

    // decode stage - instruction 2 (younger)
    input  logic       id2_valid,
    input  logic [4:0] id2_rd,
    input  logic [4:0] id2_rs1,
    input  logic [4:0] id2_rs2,
    input  logic       id2_regwrite,
    input  logic       id2_isbranch,
    input  logic       id2_uses_rs1,
    input  logic       id2_uses_rs2,

    // execute-stage loads only. Ordinary EX/MEM ALU RAW hazards are
    // handled by forwarding and must not stall decode.
    input  logic       ex1_memread,
    input  logic [4:0] ex1_rd,
    input  logic       ex1_valid,
    input  logic       ex2_memread,
    input  logic [4:0] ex2_rd,
    input  logic       ex2_valid,

    output logic intra_group_raw,
    output logic intra_group_waw,
    output logic load_use,
    output logic branch_depends,
    output logic two_branches
);

    // Same-cycle lane dependency cannot be solved by MEM/WB forwarding:
    // the younger instruction must be replayed/serialized.
    assign intra_group_raw =
        id1_valid && id2_valid && id1_regwrite && (id1_rd != 5'd0) &&
        ((id2_uses_rs1 && (id1_rd == id2_rs1)) ||
         (id2_uses_rs2 && (id1_rd == id2_rs2)));

    assign intra_group_waw =
        id1_valid && id2_valid && id1_regwrite && id2_regwrite &&
        (id1_rd != 5'd0) && (id1_rd == id2_rd);

    // One-cycle load-use interlock. After this bubble, the load reaches WB
    // when the consumer reaches EX, so the forwarding unit can supply wb*_data.
    assign load_use =
        (ex1_valid && ex1_memread && (ex1_rd != 5'd0) &&
            ((id1_valid && id1_uses_rs1 && (ex1_rd == id1_rs1)) ||
             (id1_valid && id1_uses_rs2 && (ex1_rd == id1_rs2)) ||
             (id2_valid && id2_uses_rs1 && (ex1_rd == id2_rs1)) ||
             (id2_valid && id2_uses_rs2 && (ex1_rd == id2_rs2)))) ||
        (ex2_valid && ex2_memread && (ex2_rd != 5'd0) &&
            ((id1_valid && id1_uses_rs1 && (ex2_rd == id1_rs1)) ||
             (id1_valid && id1_uses_rs2 && (ex2_rd == id1_rs2)) ||
             (id2_valid && id2_uses_rs1 && (ex2_rd == id2_rs1)) ||
             (id2_valid && id2_uses_rs2 && (ex2_rd == id2_rs2))));

    // Kept for compatibility with the current dispatch_unit. This is a
    // specialized form of intra_group_raw for a younger branch.
    assign branch_depends =
        id1_valid && id2_valid && id2_isbranch && id1_regwrite &&
        (id1_rd != 5'd0) &&
        ((id2_uses_rs1 && (id1_rd == id2_rs1)) ||
         (id2_uses_rs2 && (id1_rd == id2_rs2)));

    assign two_branches =
        id1_valid && id2_valid && id1_isbranch && id2_isbranch;

endmodule
