module core_riscv_superscalar (
    input  logic clk,
    input  logic rst_n,
    input  logic cpu_enable,

    output logic [31:0] imem_addr,
    output logic        imem_req,
    input  logic [31:0] imem_rdata,
    input  logic        imem_ready,

    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
    output logic        dmem_rd_en,
    output logic        dmem_wr_en,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready,

    // debug / testbench visibility
    output logic [31:0] debug_pc,
    output logic [31:0] debug_instr,
    output logic [31:0] debug_reg_data,
    output logic        debug_halted
);

    /*
    1. All of my RTL logic lives here
    2. All combinational/registered logic are defined here
    3. Use these during testbenches/simulations 
    */

    // 1st stage: IF

    ifid_stage ifid (
        .clk(clk),
        .rst_n(rst_n),
        .stall(),
        .flush(),
        .if1_pc(),
        .if1_instr(),
        .if1_valid(),
        .if2_pc(),
        .if2_instr(),
        .if2_valid(),

        .id1_pc(),
        .id1_instr(),
        .id1_valid(),
        .id2_pc(),
        .id2_instr(),
        .id2_valid()
    );

    // 2nd stage: ID

    idex_stage idex (
        .clk(clk)
    );

    // 3rd stage: EX

    exmem_stage exmem (

    );

    // 4th stage: MEM

    memwb_stage memwb (

    );

    // 5th stage: WB

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule