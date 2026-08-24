module core_riscv_superscalar (
    input  logic clk,
    input  logic rst_n,
    input  logic cpu_enable,

    output logic[31:0] imem_addr,   // fetch from current pc and pc + 4
    output logic       imem_req,    
    input  logic[31:0] imem_rdata1, // older instruction
    input  logic[31:0] imem_rdata2, // younger instruction
    input  logic       imem_ready,

    output logic[31:0] dmem_addr,
    output logic[31:0] dmem_wdata,
    output logic[3:0]  dmem_wstrb,
    output logic       dmem_rd_en,
    output logic       dmem_wr_en,
    input  logic[31:0] dmem_rdata,
    input  logic       dmem_ready,

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

    logic[31:0] pc_curr, pc_next;

    program_counter pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .pc_write(),
        .pc_in   (pc_next),
        .pc_out  (pc_curr)
    );

    // here I want to try three different predictors
    nt_predictor nt (
        .pc        (pc_curr),
        .prediction()
    );

    bimodal_predictor bimodal (
        .clk         (clk),
        .rst_n       (rst_n),
        .pc          (pc_curr),
        .prediction  (),
        .branch_pc   (),
        .branch_taken()
    );

    gshare_predictor gshare (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc                 (pc_curr),
        .global_history     (),
        .prediction         (),
        .branch_pc          (),
        .branch_taken       (),
        .global_history_next()
    );

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

    register_file registers (
        .clk(clk),
        .rst_n(rst_n),
        .rd1_addr1(),
        .rd1_addr2(),
        .rd2_addr1(),
        .rd2_addr2(),
        .rd1_data1(),
        .rd1_data2(),
        .rd2_data1(),
        .rd2_data2(),

        .wr1_addr(),
        .wr2_addr(),
        .wr1_data(),
        .wr2_data(),
        .reg1_write(),
        .reg2_write()
    );

    control_unit cu1 (
        .instruction(),
        .alu_opcode(),
        .op_a_sel(),
        .alusrc(),
        .regwrite(),
        .memread(),
        .memwrite(),
        .branch(),
        .memtoreg(),
        .jump(),
        .jalr(),
        .uses_rs1(),
        .uses_rs2(),
        .ebreak()
    );

    control_unit cu2 (
        .instruction(),
        .alu_opcode(),
        .op_a_sel(),
        .alusrc(),
        .regwrite(),
        .memread(),
        .memwrite(),
        .branch(),
        .memtoreg(),
        .jump(),
        .jalr(),
        .uses_rs1(),
        .uses_rs2(),
        .ebreak()
    );

    immediate_generator imm1 (
        .instr(),
        .imm()
    );

    immediate_generator imm2 (
        .instr(),
        .imm()
    );

    // 2nd stage: ID

    dispatch_unit dispatch (
        .intra_group_raw(),
        .intra_group_waw(),
        .load_use(),
        .branch_depends(),
        .two_branches(),
        .issue_0(),
        .issue_1(),
        .stall_pipeline()
    );

    idex_stage idex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(),
        .flush(),
        .issue_0(),
        .issue_1(),

        .id1_pc(),
        .id1_instr(),
        .id1_rs1_data(),
        .id1_rs2_data(),
        .id1_imm(),
        .id1_rs1(),
        .id1_rs2(),
        .id1_rd(),
        .id1_alu_opcode(),
        .id1_op_a_sel(),
        .id1_alusrc(),
        .id1_memread(),
        .id1_memwrite(),
        .id1_memtoreg(),
        .id1_regwrite(),
        .id1_branch(),
        .id1_jump(),
        .id1_jalr(),
        .id1_ebreak(),
        .id1_valid(),

        .id2_pc(),
        .id2_instr(),
        .id2_rs1_data(),
        .id2_rs2_data(),
        .id2_imm(),
        .id2_rs1(),
        .id2_rs2(),
        .id2_rd(),
        .id2_alu_opcode(),
        .id2_op_a_sel(),
        .id2_alusrc(),
        .id2_memread(),
        .id2_memwrite(),
        .id2_memtoreg(),
        .id2_regwrite(),
        .id2_branch(),
        .id2_jump(),
        .id2_jalr(),
        .id2_ebreak(),
        .id2_valid(),


        .ex1_pc(),
        .ex1_instr(),
        .ex1_rs1_data(),
        .ex1_rs2_data(),
        .ex1_imm(),
        .ex1_rs1(),
        .ex1_rs2(),
        .ex1_rd(),
        .ex1_alu_opcode(),
        .ex1_op_a_sel(),
        .ex1_alusrc(),
        .ex1_memread(),
        .ex1_memwrite(),
        .ex1_memtoreg(),
        .ex1_regwrite(),
        .ex1_branch(),
        .ex1_jump(),
        .ex1_jalr(),
        .ex1_ebreak(),
        .ex1_valid(),

        .ex2_pc(),
        .ex2_instr(),
        .ex2_rs1_data(),
        .ex2_rs2_data(),
        .ex2_imm(),
        .ex2_rs1(),
        .ex2_rs2(),
        .ex2_rd(),
        .ex2_alu_opcode(),
        .ex2_op_a_sel(),
        .ex2_alusrc(),
        .ex2_memread(),
        .ex2_memwrite(),
        .ex2_memtoreg(),
        .ex2_regwrite(),
        .ex2_branch(),
        .ex2_jump(),
        .ex2_jalr(),
        .ex2_ebreak(),
        .ex2_valid()
    );

    // 3rd stage: EX

    exmem_stage exmem (
        .clk(clk),
        .rst_n(rst_n),
        .stall(),

        .ex1_result(),
        .ex1_store_data(),
        .ex1_rd(),
        .ex1_funct3(),
        .ex1_memread(),
        .ex1_memwrite(),
        .ex1_memtoreg(),
        .ex1_regwrite(),
        .ex1_ebreak(),
        .ex1_valid(),

        .ex2_result(),
        .ex2_store_data(),
        .ex2_rd(),
        .ex2_funct3(),
        .ex2_memread(),
        .ex2_memwrite(),
        .ex2_memtoreg(),
        .ex2_regwrite(),
        .ex2_ebreak(),
        .ex2_valid(),

        .mem1_result(),
        .mem1_store_data(),
        .mem1_rd(),
        .mem1_funct3(),
        .mem1_memread(),
        .mem1_memwrite(),
        .mem1_memtoreg(),
        .mem1_regwrite(),
        .mem1_ebreak(),
        .mem1_valid(),

        .mem2_result(),
        .mem2_store_data(),
        .mem2_rd(),
        .mem2_funct3(),
        .mem2_memread(),
        .mem2_memwrite(),
        .mem2_memtoreg(),
        .mem2_regwrite(),
        .mem2_ebreak(),
        .mem2_valid()
    );

    // 4th stage: MEM

    memwb_stage memwb (
        .clk(clk),
        .rst_n(rst_n),
        .stall(),
        
        .mem1_alu_result(),
        .mem1_rdata(),
        .mem1_rd(),
        .mem1_regwrite(),
        .mem1_memtoreg(),
        .mem1_ebreak(),
        .mem1_valid(),

        .mem2_alu_result(),
        .mem2_rdata(),
        .mem2_rd(),
        .mem2_regwrite(),
        .mem2_memtoreg(),
        .mem2_ebreak(),
        .mem2_valid(),

        .wb1_alu_result(),
        .wb1_rdata(),
        .wb1_rd(),
        .wb1_regwrite(),
        .wb1_memtoreg(),
        .wb1_ebreak(),
        .wb1_valid(),

        .wb2_alu_result(),
        .wb2_rdata(),
        .wb2_rd(),
        .wb2_regwrite(),
        .wb2_memtoreg(),
        .wb2_ebreak(),
        .wb2_valid()
    );

    // 5th stage: WB and combinational assignments
    hazard_unit hu (
        .id1_rd(),
        .id1_rs1(),
        .id1_rs2(),
        .id1_regwrite(),
        .id1_isbranch(),
        
        .id2_rd(),
        .id2_rs1(),
        .id2_rs2(),
        .id2_regwrite(),
        .id2_isbranch(),

        .dmem_rd_en_mem(),
        .rd_mem()
    );

    assign imem_addr = pc_curr;

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
    */

endmodule