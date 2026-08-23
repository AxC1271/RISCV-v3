module dispatch_unit (
    // from hazard unit
    input  logic intra_group_raw, // instr_0 writes, instr_1 reads same reg
    input  logic intra_group_waw, // both write to the same register
    input  logic load_use,        // load result needed by either instr
    input  logic branch_depends,  // instr_1 is branch, depends on instr_0
    input  logic two_branches,    // both instr_0 and instr_1 are branches
    // how to issue?
    output logic issue_0,       // 1 = instr_0 proceeds
    output logic issue_1,       // 1 = instr_1 proceeds
    output logic stall_pipeline // 1 = stall entire pipeline
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    assign issue_0 = !load_use;
    assign issue_1 = !(
        load_use        || 
        intra_group_raw ||
        intra_group_waw ||
        branch_depends  ||
        two_branches
    );
    assign stall_pipeline = load_use;

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule