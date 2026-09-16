module core_riscv_superscalar_FINAL (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_enable,
    output logic[31:0]  imem_addr,     // fetch from current pc and pc + 4
    output logic        imem_req,    
    input  logic[31:0]  imem_rdata1,   // older instruction
    input  logic[31:0]  imem_rdata2,   // younger instruction
    input  logic        imem_ready,
    output logic[31:0]  dmem_addr,
    output logic[31:0]  dmem_wdata,
    output logic[3:0]   dmem_wstrb,
    output logic        dmem_rd_en,
    output logic        dmem_wr_en,
    input  logic[31:0]  dmem_rdata,
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

    logic[31:0] pc_curr, pc_next;
    logic flush;
    logic pc_write;
    logic mem_stall;
    logic replay_second;

    program_counter pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .pc_write(pc_write),
        .pc_in   (pc_next),
        .pc_out  (pc_curr)
    );

    // gshare-only branch prediction
    logic prediction_gshare, prediction_gshare2;
    logic prediction_if1, prediction_if2;

    logic[9:0] global_history, global_history_next;
    logic branch_update_valid, branch_taken_ex;
    logic[31:0] branch_pc_ex;
    logic[9:0] branch_history_ex;

    gshare_predictor gshare (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc                 (pc_curr),
        .pc2                (pc_curr + 32'd4),
        .global_history     (global_history),
        .prediction         (prediction_gshare),
        .prediction2        (prediction_gshare2),
        .branch_pc          (branch_pc_ex),
        .branch_history     (branch_history_ex),
        .branch_taken       (branch_taken_ex),
        .branch_valid       (branch_update_valid),
        .global_history_next(global_history_next)
    );

    assign prediction_if1 = prediction_gshare;
    assign prediction_if2 = prediction_gshare2;

    always_ff @(posedge clk) begin
        if (!rst_n)
            global_history <= 10'b0;
        else if (branch_update_valid)
            global_history <= global_history_next;
    end

    logic[31:0] if1_imm, if2_imm;
    logic if1_branch, if2_branch, if1_jump, if2_jump, if1_jalr, if2_jalr;
    logic if1_predicted_taken, if2_predicted_taken;
    logic[31:0] if1_predicted_target, if2_predicted_target;

    immediate_generator ifimm1 (.instr(imem_rdata1), .imm(if1_imm));
    immediate_generator ifimm2 (.instr(imem_rdata2), .imm(if2_imm));

    assign if1_branch = (imem_rdata1[6:0] == 7'b1100011);
    assign if2_branch = (imem_rdata2[6:0] == 7'b1100011);
    assign if1_jump = (imem_rdata1[6:0] == 7'b1101111);
    assign if2_jump = (imem_rdata2[6:0] == 7'b1101111);
    assign if1_jalr = (imem_rdata1[6:0] == 7'b1100111);
    assign if2_jalr = (imem_rdata2[6:0] == 7'b1100111);
    assign if1_predicted_taken = if1_jump || (if1_branch && prediction_if1);
    assign if2_predicted_taken = if2_jump || (if2_branch && prediction_if2);
    assign if1_predicted_target = pc_curr + if1_imm;
    assign if2_predicted_target = pc_curr + 32'd4 + if2_imm;

    // 1st stage: IF

    logic[31:0] id1_pc, id2_pc;
    logic[31:0] id1_instr, id2_instr;
    logic id1_valid, id2_valid;
    logic id1_predicted_taken, id2_predicted_taken;
    logic[9:0] id1_branch_history, id2_branch_history;
    logic fetch_flush;

    ifid_stage ifid (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_pipeline || mem_stall || !imem_ready || !cpu_enable),
        .flush(fetch_flush),
        .replay_second(replay_second),
        .if1_pc(pc_curr),
        .if1_instr(imem_rdata1),
        .if1_valid(imem_ready && cpu_enable), // always pass in 1'b1 unless squashed
        .if1_predicted_taken(if1_predicted_taken),
        .if1_branch_history(global_history),
        .if2_pc(pc_curr + 4),
        .if2_instr(imem_rdata2),
        .if2_valid(imem_ready && cpu_enable && !(if1_predicted_taken || if1_jalr)), // always pass in 1'b1 unless squashed
        .if2_predicted_taken(if2_predicted_taken),
        .if2_branch_history(global_history),
        .id1_pc(id1_pc),
        .id1_instr(id1_instr),
        .id1_valid(id1_valid),
        .id1_predicted_taken(id1_predicted_taken),
        .id1_branch_history(id1_branch_history),
        .id2_pc(id2_pc),
        .id2_instr(id2_instr),
        .id2_valid(id2_valid),
        .id2_predicted_taken(id2_predicted_taken),
        .id2_branch_history(id2_branch_history)
    );

    logic[31:0] id_rd1_data1, id_rd1_data2;
    logic[31:0] id_rd2_data1, id_rd2_data2;
    logic[31:0] wb1_data, wb2_data;
    logic[4:0] wb1_rd, wb2_rd;
    logic wb1_regwrite, wb2_regwrite, wb1_valid, wb2_valid;
    logic wb1_ebreak, wb2_ebreak;

    register_file registers (
        .clk(clk),
        .rst_n(rst_n),
        .rd1_addr1(id1_instr[19:15]),
        .rd1_addr2(id1_instr[24:20]),
        .rd2_addr1(id2_instr[19:15]),
        .rd2_addr2(id2_instr[24:20]),
        .rd1_data1(id_rd1_data1),
        .rd1_data2(id_rd1_data2),
        .rd2_data1(id_rd2_data1),
        .rd2_data2(id_rd2_data2),
        .wr1_addr(wb1_rd),
        .wr2_addr(wb2_rd),
        .wr1_data(wb1_data),
        .wr2_data(wb2_data),
        .reg1_write(wb1_regwrite && wb1_valid),
        .reg2_write(wb2_regwrite && wb2_valid)
    );

    logic[3:0] id1_alu_opcode, id2_alu_opcode;
    logic[1:0] id1_op_a_sel, id2_op_a_sel;
    logic id1_alusrc, id2_alusrc;
    logic id1_regwrite, id2_regwrite;
    logic id1_memread, id2_memread;
    logic id1_memwrite, id2_memwrite;
    logic id1_branch, id2_branch;
    logic id1_memtoreg, id2_memtoreg;
    logic id1_jump, id2_jump;
    logic id1_jalr, id2_jalr;
    logic id1_uses_rs1, id1_uses_rs2, id2_uses_rs1, id2_uses_rs2; 
    logic id1_ebreak, id2_ebreak;

    control_unit cu1 (
        .instruction(id1_instr),
        .alu_opcode(id1_alu_opcode),
        .op_a_sel(id1_op_a_sel),
        .alusrc(id1_alusrc),
        .regwrite(id1_regwrite),
        .memread(id1_memread),
        .memwrite(id1_memwrite),
        .branch(id1_branch),
        .memtoreg(id1_memtoreg),
        .jump(id1_jump),
        .jalr(id1_jalr),
        .uses_rs1(id1_uses_rs1),
        .uses_rs2(id1_uses_rs2),
        .ebreak(id1_ebreak)
    );

    control_unit cu2 (
        .instruction(id2_instr),
        .alu_opcode(id2_alu_opcode),
        .op_a_sel(id2_op_a_sel),
        .alusrc(id2_alusrc),
        .regwrite(id2_regwrite),
        .memread(id2_memread),
        .memwrite(id2_memwrite),
        .branch(id2_branch),
        .memtoreg(id2_memtoreg),
        .jump(id2_jump),
        .jalr(id2_jalr),
        .uses_rs1(id2_uses_rs1),
        .uses_rs2(id2_uses_rs2),
        .ebreak(id2_ebreak)
    );

    logic [31:0] id1_imm, id2_imm;

    immediate_generator imm1 (
        .instr(id1_instr),
        .imm(id1_imm)
    );

    immediate_generator imm2 (
        .instr(id2_instr),
        .imm(id2_imm)
    );

    // 2nd stage: ID

    logic intra_group_raw, intra_group_waw;
    logic load_use, branch_depends, two_branches;
    logic issue_0, issue_1, stall_pipeline;
    logic structural_hazard, control_in_slot0, control_in_slot1;

    assign structural_hazard = id1_valid && id2_valid && (id1_memread || id1_memwrite) && (id2_memread || id2_memwrite);
    assign control_in_slot0 = id1_valid && (id1_branch || id1_jump);
    assign control_in_slot1 = id2_valid && (id2_branch || id2_jump);

    dispatch_unit dispatch (
        .intra_group_raw(intra_group_raw),
        .intra_group_waw(intra_group_waw),
        .load_use       (load_use),
        .branch_depends (branch_depends),
        .two_branches   (two_branches),
        .structural_hazard(structural_hazard),
        .control_in_slot0(control_in_slot0),
        .control_in_slot1(control_in_slot1),
        .issue_0        (issue_0),
        .issue_1        (issue_1),
        .stall_pipeline (stall_pipeline)
    );

    assign replay_second = id2_valid && issue_0 && !issue_1 && !flush && !mem_stall;

    logic[31:0] ex1_pc, ex2_pc, ex1_instr, ex2_instr;
    logic[31:0] ex1_rs1_data, ex1_rs2_data, ex2_rs1_data, ex2_rs2_data;
    logic[31:0] ex1_imm, ex2_imm;
    logic[4:0] ex1_rs1, ex1_rs2, ex1_rd, ex2_rs1, ex2_rs2, ex2_rd;
    logic[3:0] ex1_alu_opcode, ex2_alu_opcode;
    logic[1:0] ex1_op_a_sel, ex2_op_a_sel;
    logic ex1_alusrc, ex2_alusrc, ex1_memread, ex2_memread, ex1_memwrite, ex2_memwrite;
    logic ex1_memtoreg, ex2_memtoreg, ex1_regwrite, ex2_regwrite, ex1_branch, ex2_branch;
    logic ex1_jump, ex2_jump, ex1_jalr, ex2_jalr, ex1_ebreak, ex2_ebreak, ex1_valid, ex2_valid;
    logic ex1_predicted_taken, ex2_predicted_taken;
    logic[9:0] ex1_branch_history, ex2_branch_history;

    idex_stage idex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(mem_stall),
        .flush(flush),
        .issue_0(issue_0 && id1_valid && !stall_pipeline),
        .issue_1(issue_1 && id2_valid && !stall_pipeline),
        .id1_pc(id1_pc), .id1_instr(id1_instr), .id1_rs1_data(id_rd1_data1), .id1_rs2_data(id_rd1_data2),
        .id1_imm(id1_imm), .id1_rs1(id1_instr[19:15]), .id1_rs2(id1_instr[24:20]), .id1_rd(id1_instr[11:7]),
        .id1_alu_opcode(id1_alu_opcode), .id1_op_a_sel(id1_op_a_sel), .id1_alusrc(id1_alusrc),
        .id1_memread(id1_memread), .id1_memwrite(id1_memwrite), .id1_memtoreg(id1_memtoreg), .id1_regwrite(id1_regwrite),
        .id1_branch(id1_branch), .id1_jump(id1_jump), .id1_jalr(id1_jalr), .id1_ebreak(id1_ebreak), .id1_valid(id1_valid),
        .id1_predicted_taken(id1_predicted_taken), .id1_branch_history(id1_branch_history),
        .id2_pc(id2_pc), .id2_instr(id2_instr), .id2_rs1_data(id_rd2_data1), .id2_rs2_data(id_rd2_data2),
        .id2_imm(id2_imm), .id2_rs1(id2_instr[19:15]), .id2_rs2(id2_instr[24:20]), .id2_rd(id2_instr[11:7]),
        .id2_alu_opcode(id2_alu_opcode), .id2_op_a_sel(id2_op_a_sel), .id2_alusrc(id2_alusrc),
        .id2_memread(id2_memread), .id2_memwrite(id2_memwrite), .id2_memtoreg(id2_memtoreg), .id2_regwrite(id2_regwrite),
        .id2_branch(id2_branch), .id2_jump(id2_jump), .id2_jalr(id2_jalr), .id2_ebreak(id2_ebreak), .id2_valid(id2_valid),
        .id2_predicted_taken(id2_predicted_taken), .id2_branch_history(id2_branch_history),
        .ex1_pc(ex1_pc), .ex1_instr(ex1_instr), .ex1_rs1_data(ex1_rs1_data), .ex1_rs2_data(ex1_rs2_data), .ex1_imm(ex1_imm),
        .ex1_rs1(ex1_rs1), .ex1_rs2(ex1_rs2), .ex1_rd(ex1_rd), .ex1_alu_opcode(ex1_alu_opcode), .ex1_op_a_sel(ex1_op_a_sel),
        .ex1_alusrc(ex1_alusrc), .ex1_memread(ex1_memread), .ex1_memwrite(ex1_memwrite), .ex1_memtoreg(ex1_memtoreg),
        .ex1_regwrite(ex1_regwrite), .ex1_branch(ex1_branch), .ex1_jump(ex1_jump), .ex1_jalr(ex1_jalr), .ex1_ebreak(ex1_ebreak),
        .ex1_valid(ex1_valid), .ex1_predicted_taken(ex1_predicted_taken), .ex1_branch_history(ex1_branch_history),
        .ex2_pc(ex2_pc), .ex2_instr(ex2_instr), .ex2_rs1_data(ex2_rs1_data), .ex2_rs2_data(ex2_rs2_data), .ex2_imm(ex2_imm),
        .ex2_rs1(ex2_rs1), .ex2_rs2(ex2_rs2), .ex2_rd(ex2_rd), .ex2_alu_opcode(ex2_alu_opcode), .ex2_op_a_sel(ex2_op_a_sel),
        .ex2_alusrc(ex2_alusrc), .ex2_memread(ex2_memread), .ex2_memwrite(ex2_memwrite), .ex2_memtoreg(ex2_memtoreg),
        .ex2_regwrite(ex2_regwrite), .ex2_branch(ex2_branch), .ex2_jump(ex2_jump), .ex2_jalr(ex2_jalr), .ex2_ebreak(ex2_ebreak),
        .ex2_valid(ex2_valid), .ex2_predicted_taken(ex2_predicted_taken), .ex2_branch_history(ex2_branch_history)
    );

    // Forwarding sources from EX/MEM
    logic[31:0] mem1_result, mem1_store_data, mem2_result, mem2_store_data;
    logic[4:0] mem1_rd, mem2_rd;
    logic[2:0] mem1_funct3, mem2_funct3;
    logic mem1_memread, mem1_memwrite, mem1_memtoreg, mem1_regwrite, mem1_ebreak, mem1_valid;
    logic mem2_memread, mem2_memwrite, mem2_memtoreg, mem2_regwrite, mem2_ebreak, mem2_valid;

    // 3rd stage: EX
    logic[31:0] ex1_a, ex1_b, ex2_a, ex2_b, ex1_alu_result, ex2_alu_result;
    logic[31:0] ex1_result, ex2_result;
    logic[31:0] branch_target_ex;
    logic conditional_taken_ex, actual_taken_ex, mispredict;
    logic[31:0] redirect_pc;

    // forwarded source operands for both execution lanes

    logic[31:0] ex1_rs1_fwd, ex1_rs2_fwd, ex2_rs1_fwd, ex2_rs2_fwd;
    logic[2:0] forward_1a, forward_1b, forward_2a, forward_2b;

    forward_unit fu (
        .ex1_rs1(ex1_rs1), .ex1_rs2(ex1_rs2),
        .ex2_rs1(ex2_rs1), .ex2_rs2(ex2_rs2),
        .mem1_rd(mem1_rd),
        .mem1_regwrite(mem1_regwrite && !mem1_memread),
        .mem1_valid(mem1_valid),
        .mem2_rd(mem2_rd),
        .mem2_regwrite(mem2_regwrite && !mem2_memread),
        .mem2_valid(mem2_valid),
        .wb1_rd(wb1_rd), .wb1_regwrite(wb1_regwrite), .wb1_valid(wb1_valid),
        .wb2_rd(wb2_rd), .wb2_regwrite(wb2_regwrite), .wb2_valid(wb2_valid),
        .forward_1a(forward_1a), .forward_1b(forward_1b),
        .forward_2a(forward_2a), .forward_2b(forward_2b)
    );

    always_comb begin

        case (forward_1a)
            3'b001: ex1_rs1_fwd = wb1_data;
            3'b010: ex1_rs1_fwd = wb2_data;
            3'b011: ex1_rs1_fwd = mem1_result;
            3'b100: ex1_rs1_fwd = mem2_result;
            default: ex1_rs1_fwd = ex1_rs1_data;
        endcase

        case (forward_1b)
            3'b001: ex1_rs2_fwd = wb1_data;
            3'b010: ex1_rs2_fwd = wb2_data;
            3'b011: ex1_rs2_fwd = mem1_result;
            3'b100: ex1_rs2_fwd = mem2_result;
            default: ex1_rs2_fwd = ex1_rs2_data;
        endcase

        case (forward_2a)
            3'b001: ex2_rs1_fwd = wb1_data;
            3'b010: ex2_rs1_fwd = wb2_data;
            3'b011: ex2_rs1_fwd = mem1_result;
            3'b100: ex2_rs1_fwd = mem2_result;
            default: ex2_rs1_fwd = ex2_rs1_data;
        endcase

        case (forward_2b)
            3'b001: ex2_rs2_fwd = wb1_data;
            3'b010: ex2_rs2_fwd = wb2_data;
            3'b011: ex2_rs2_fwd = mem1_result;
            3'b100: ex2_rs2_fwd = mem2_result;
            default: ex2_rs2_fwd = ex2_rs2_data;
        endcase
    end

    always_comb begin

        case (ex1_op_a_sel)
            2'b01: ex1_a = ex1_pc;
            2'b10: ex1_a = 32'b0;
            default: ex1_a = ex1_rs1_fwd;
        endcase

        case (ex2_op_a_sel)
            2'b01: ex2_a = ex2_pc;
            2'b10: ex2_a = 32'b0;
            default: ex2_a = ex2_rs1_fwd;
        endcase

    end

    assign ex1_b = ex1_alusrc ? ex1_imm : ex1_rs2_fwd;
    assign ex2_b = ex2_alusrc ? ex2_imm : ex2_rs2_fwd;

    alu alu1 (.a(ex1_a), .b(ex1_b), .alu_opcode(ex1_alu_opcode), .result(ex1_alu_result));
    alu alu2 (.a(ex2_a), .b(ex2_b), .alu_opcode(ex2_alu_opcode), .result(ex2_alu_result));

    assign ex1_result = ex1_jump ? (ex1_pc + 32'd4) : ex1_alu_result;
    assign ex2_result = ex2_jump ? (ex2_pc + 32'd4) : ex2_alu_result;

    branch_unit bu (
        .rs1_data(ex1_rs1_fwd),
        .rs2_data(ex1_rs2_fwd),
        .branch(ex1_branch && ex1_valid),
        .funct3(ex1_instr[14:12]),
        .pc(ex1_pc),
        .imm(ex1_imm),
        .branch_taken(conditional_taken_ex),
        .branch_target(branch_target_ex)
    );

    assign actual_taken_ex = conditional_taken_ex || (ex1_jump && ex1_valid);
    assign redirect_pc = ex1_jalr ? ((ex1_rs1_fwd + ex1_imm) & 32'hffff_fffe) : branch_target_ex;
    assign mispredict = ex1_valid && (ex1_branch || ex1_jump) && ((actual_taken_ex != ex1_predicted_taken) || (actual_taken_ex && ex1_jalr));
    assign flush = mispredict;
    assign branch_update_valid = ex1_valid && ex1_branch;
    assign branch_taken_ex = conditional_taken_ex;
    assign branch_pc_ex = ex1_pc;
    assign branch_history_ex = ex1_branch_history;

    exmem_stage exmem (
        .clk(clk), .rst_n(rst_n), .stall(mem_stall),
        .ex1_result(ex1_result), .ex1_store_data(ex1_rs2_fwd), .ex1_rd(ex1_rd), .ex1_funct3(ex1_instr[14:12]),
        .ex1_memread(ex1_memread), .ex1_memwrite(ex1_memwrite), .ex1_memtoreg(ex1_memtoreg), .ex1_regwrite(ex1_regwrite),
        .ex1_ebreak(ex1_ebreak), .ex1_valid(ex1_valid),
        .ex2_result(ex2_result), .ex2_store_data(ex2_rs2_fwd), .ex2_rd(ex2_rd), .ex2_funct3(ex2_instr[14:12]),
        .ex2_memread(ex2_memread), .ex2_memwrite(ex2_memwrite), .ex2_memtoreg(ex2_memtoreg), .ex2_regwrite(ex2_regwrite),
        .ex2_ebreak(ex2_ebreak), .ex2_valid(ex2_valid),
        .mem1_alu_result(mem1_result), .mem1_store_data(mem1_store_data), .mem1_rd(mem1_rd), .mem1_funct3(mem1_funct3),
        .mem1_memread(mem1_memread), .mem1_memwrite(mem1_memwrite), .mem1_memtoreg(mem1_memtoreg), .mem1_regwrite(mem1_regwrite),
        .mem1_ebreak(mem1_ebreak), .mem1_valid(mem1_valid),
        .mem2_alu_result(mem2_result), .mem2_store_data(mem2_store_data), .mem2_rd(mem2_rd), .mem2_funct3(mem2_funct3),
        .mem2_memread(mem2_memread), .mem2_memwrite(mem2_memwrite), .mem2_memtoreg(mem2_memtoreg), .mem2_regwrite(mem2_regwrite),
        .mem2_ebreak(mem2_ebreak), .mem2_valid(mem2_valid)

    );

    // 4th stage: MEM

    logic mem_lane2;
    logic[31:0] mem_addr_sel, mem_store_sel, mem_load_data, mem_load_shifted;
    logic[2:0] mem_funct3_sel;
    logic mem_read_sel, mem_write_sel;

    assign mem_lane2 = !(mem1_valid && (mem1_memread || mem1_memwrite)) && mem2_valid && (mem2_memread || mem2_memwrite);
    assign mem_addr_sel = mem_lane2 ? mem2_result : mem1_result;
    assign mem_store_sel = mem_lane2 ? mem2_store_data : mem1_store_data;
    assign mem_funct3_sel = mem_lane2 ? mem2_funct3 : mem1_funct3;
    assign mem_read_sel = mem_lane2 ? mem2_memread : mem1_memread;
    assign mem_write_sel = mem_lane2 ? mem2_memwrite : mem1_memwrite;
    assign dmem_addr = mem_addr_sel;
    assign dmem_rd_en = cpu_enable && mem_read_sel;
    assign dmem_wr_en = cpu_enable && mem_write_sel;
    assign mem_stall = cpu_enable && (mem_read_sel || mem_write_sel) && !dmem_ready;

    always_comb begin

        dmem_wdata = mem_store_sel;
        dmem_wstrb = 4'b0000;

        case (mem_funct3_sel)

            3'b000: begin
                dmem_wdata = mem_store_sel << (8 * mem_addr_sel[1:0]);
                dmem_wstrb = 4'b0001 << mem_addr_sel[1:0];
            end

            3'b001: begin
                dmem_wdata = mem_store_sel << (16 * mem_addr_sel[1]);
                dmem_wstrb = 4'b0011 << (2 * mem_addr_sel[1]);
            end

            default: begin
                dmem_wdata = mem_store_sel;
                dmem_wstrb = 4'b1111;
            end
        endcase
    end

    always_comb begin

        mem_load_shifted = dmem_rdata >> (8 * mem_addr_sel[1:0]);

        case (mem_funct3_sel)
            3'b000: mem_load_data = {{24{mem_load_shifted[7]}}, mem_load_shifted[7:0]};
            3'b001: mem_load_data = {{16{mem_load_shifted[15]}}, mem_load_shifted[15:0]};
            3'b100: mem_load_data = {24'b0, mem_load_shifted[7:0]};
            3'b101: mem_load_data = {16'b0, mem_load_shifted[15:0]};
            default: mem_load_data = dmem_rdata;
        endcase
    end

    logic[31:0] wb1_alu_result, wb1_rdata, wb2_alu_result, wb2_rdata;
    logic wb1_memtoreg, wb2_memtoreg;

    memwb_stage memwb (
        .clk(clk),
        .rst_n(rst_n),
        .stall(mem_stall),
        .mem1_alu_result(mem1_result),
        .mem1_rdata(mem1_memread ? mem_load_data : 32'b0),
        .mem1_rd(mem1_rd),
        .mem1_regwrite(mem1_regwrite),
        .mem1_memtoreg(mem1_memtoreg),
        .mem1_ebreak(mem1_ebreak),
        .mem1_valid(mem1_valid),
        .mem2_alu_result(mem2_result),
        .mem2_rdata(mem2_memread ? mem_load_data : 32'b0),
        .mem2_rd(mem2_rd),
        .mem2_regwrite(mem2_regwrite),
        .mem2_memtoreg(mem2_memtoreg),
        .mem2_ebreak(mem2_ebreak),
        .mem2_valid(mem2_valid),
        .wb1_alu_result(wb1_alu_result),
        .wb1_rdata(wb1_rdata),
        .wb1_rd(wb1_rd),
        .wb1_regwrite(wb1_regwrite),
        .wb1_memtoreg(wb1_memtoreg),
        .wb1_ebreak(wb1_ebreak),
        .wb1_valid(wb1_valid),
        .wb2_alu_result(wb2_alu_result),
        .wb2_rdata(wb2_rdata),
        .wb2_rd(wb2_rd),
        .wb2_regwrite(wb2_regwrite),
        .wb2_memtoreg(wb2_memtoreg),
        .wb2_ebreak(wb2_ebreak),
        .wb2_valid(wb2_valid)
    );

    assign wb1_data = wb1_memtoreg ? wb1_rdata : wb1_alu_result;
    assign wb2_data = wb2_memtoreg ? wb2_rdata : wb2_alu_result;

    // 5th stage: WB and combinational assignments

    hazard_unit hu (
        .id1_valid(id1_valid),
        .id1_rd(id1_instr[11:7]),
        .id1_rs1(id1_instr[19:15]),
        .id1_rs2(id1_instr[24:20]),
        .id1_regwrite(id1_regwrite && id1_valid),
        .id1_isbranch(id1_branch && id1_valid),
        .id1_uses_rs1(id1_uses_rs1),
        .id1_uses_rs2(id1_uses_rs2),
        .id2_valid(id2_valid),
        .id2_rd(id2_instr[11:7]),
        .id2_rs1(id2_instr[19:15]),
        .id2_rs2(id2_instr[24:20]),
        .id2_regwrite(id2_regwrite && id2_valid),
        .id2_isbranch(id2_branch && id2_valid),
        .id2_uses_rs1(id2_uses_rs1),
        .id2_uses_rs2(id2_uses_rs2),
        .ex1_memread(ex1_memread), .ex1_rd(ex1_rd), .ex1_valid(ex1_valid),
        .ex2_memread(ex2_memread), .ex2_rd(ex2_rd), .ex2_valid(ex2_valid),
        .intra_group_raw(intra_group_raw),
        .intra_group_waw(intra_group_waw),
        .load_use(load_use),
        .branch_depends(branch_depends),
        .two_branches(two_branches)
    );

    always_comb begin
        if (flush)
            pc_next = actual_taken_ex ? redirect_pc : (ex1_pc + 32'd4);
        else if (if1_predicted_taken)
            pc_next = if1_predicted_target;
        else if (if2_predicted_taken)
            pc_next = if2_predicted_target;
        else
            pc_next = pc_curr + 32'd8;
    end

    assign pc_write = cpu_enable && !mem_stall && !stall_pipeline && !replay_second && (imem_ready || flush);
    assign fetch_flush = flush;
    assign imem_addr = pc_curr;
    assign imem_req = cpu_enable && !mem_stall;
    assign debug_pc = wb1_valid ? wb1_alu_result : pc_curr;
    assign debug_instr = wb1_valid ? 32'h00000013 : id1_instr;
    assign debug_reg_data = wb1_data;
    assign debug_halted = (wb1_valid && wb1_ebreak) || (wb2_valid && wb2_ebreak);

    /*
    1. My formal properties live here*
    2. All asserts, assumes, and covers are defined here*
    3. Use these during SymbiYosys for formal verification*
    */

endmodule