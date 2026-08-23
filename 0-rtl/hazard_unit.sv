module hazard_unit (
    // from decode stage, instruction 1
    input  logic[4:0] id1_rd,
    input  logic[4:0] id1_rs1,
    input  logic[4:0] id1_rs2,
    input  logic      id1_regwrite,
    input  logic      id1_isbranch,

    // from decode stage, instruction 2
    input  logic[4:0] id2_rd,
    input  logic[4:0] id2_rs1,
    input  logic[4:0] id2_rs2,
    input  logic      id2_regwrite,
    input  logic      id2_isbranch,

    // from mem stage, for load-use detection
    input  logic      dmem_rd_en_mem,
    input  logic[4:0] rd_mem,

    // output hazard flags
    output logic intra_group_raw, // instr_0 writes, instr_1 reads same reg
    output logic intra_group_waw, // both write to the same register
    output logic load_use,        // load result needed by either instr
    output logic branch_depends,  // instr_1 is branch, depends on instr_0
    output logic two_branches     // both instr_0 and instr_1 are branches
    );
    
        /*
        1. All of my RTL logic lives here
        2. All combinational/registered logic are defined here
        3. Use these during testbenches/simulations 
        */

        assign intra_group_raw = id1_regwrite && (
            (id1_rd == id2_rs1)  || 
            (id1_rd == id2_rs2)) &&
            (id1_rd != 5'b0);

        assign intra_group_waw = 
            (id1_rd == id2_rd) && 
            (id1_regwrite && id2_regwrite) && 
            (id1_rd != 5'b0);

        assign load_use = dmem_rd_en_mem && (
            (rd_mem == id1_rs1)  ||
            (rd_mem == id1_rs2)  ||
            (rd_mem == id2_rs1)  ||
            (rd_mem == id2_rs2)) &&
            (rd_mem != 5'b0);

        assign branch_depends = id2_isbranch && id1_regwrite && 
            (id1_rd == id2_rs1 || id1_rd == id2_rs2) &&
            (id1_rd != 5'b0);
        assign two_branches = (id1_isbranch && id2_isbranch);
        
    
        /*
        1. My formal properties live here
        2. All asserts, assumes, and covers are defined here
        3. Use these during SymbiYosys for formal verification
        */
    
    endmodule