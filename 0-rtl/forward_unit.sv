module forward_unit (

    input logic [4:0] ex1_rs1,
    input logic [4:0] ex1_rs2,
    input logic [4:0] ex2_rs1,
    input logic [4:0] ex2_rs2,

    input logic [4:0] mem1_rd,
    input logic       mem1_regwrite,
    input logic       mem1_valid,

    input logic [4:0] mem2_rd,
    input logic       mem2_regwrite,
    input logic       mem2_valid,

    input logic [4:0] wb1_rd,
    input logic       wb1_regwrite,
    input logic       wb1_valid,

    input logic [4:0] wb2_rd,
    input logic       wb2_regwrite,
    input logic       wb2_valid,

    output logic [2:0] forward_1a,
    output logic [2:0] forward_1b,
    output logic [2:0] forward_2a,
    output logic [2:0] forward_2b

);

    /*
        1. All of my RTL logic lives here
        2. All combinational/registered logic are defined here
        3. Use these during testbenches/simulations 
        */

    // 3'b000 = no forwarding
    // 3'b001 = WB1
    // 3'b010 = WB2
    // 3'b011 = MEM1
    // 3'b100 = MEM2

    always_comb begin

        forward_1a = 3'b000;
        forward_1b = 3'b000;
        forward_2a = 3'b000;
        forward_2b = 3'b000;

        // EX1 rs1

        if (mem1_valid && mem1_regwrite && mem1_rd != 0 &&
            mem1_rd == ex1_rs1)
            forward_1a = 3'b011;

        else if (mem2_valid && mem2_regwrite && mem2_rd != 0 &&
                 mem2_rd == ex1_rs1)
            forward_1a = 3'b100;

        else if (wb1_valid && wb1_regwrite && wb1_rd != 0 &&
                 wb1_rd == ex1_rs1)
            forward_1a = 3'b001;

        else if (wb2_valid && wb2_regwrite && wb2_rd != 0 &&
                 wb2_rd == ex1_rs1)
            forward_1a = 3'b010;


        // EX1 rs2

        if (mem1_valid && mem1_regwrite && mem1_rd != 0 &&
            mem1_rd == ex1_rs2)
            forward_1b = 3'b011;

        else if (mem2_valid && mem2_regwrite && mem2_rd != 0 &&
                 mem2_rd == ex1_rs2)
            forward_1b = 3'b100;

        else if (wb1_valid && wb1_regwrite && wb1_rd != 0 &&
                 wb1_rd == ex1_rs2)
            forward_1b = 3'b001;

        else if (wb2_valid && wb2_regwrite && wb2_rd != 0 &&
                 wb2_rd == ex1_rs2)
            forward_1b = 3'b010;


        // EX2 rs1

        if (mem1_valid && mem1_regwrite && mem1_rd != 0 &&
            mem1_rd == ex2_rs1)
            forward_2a = 3'b011;

        else if (mem2_valid && mem2_regwrite && mem2_rd != 0 &&
                 mem2_rd == ex2_rs1)
            forward_2a = 3'b100;

        else if (wb1_valid && wb1_regwrite && wb1_rd != 0 &&
                 wb1_rd == ex2_rs1)
            forward_2a = 3'b001;

        else if (wb2_valid && wb2_regwrite && wb2_rd != 0 &&
                 wb2_rd == ex2_rs1)
            forward_2a = 3'b010;


        // EX2 rs2

        if (mem1_valid && mem1_regwrite && mem1_rd != 0 &&
            mem1_rd == ex2_rs2)
            forward_2b = 3'b011;

        else if (mem2_valid && mem2_regwrite && mem2_rd != 0 &&
                 mem2_rd == ex2_rs2)
            forward_2b = 3'b100;

        else if (wb1_valid && wb1_regwrite && wb1_rd != 0 &&
                 wb1_rd == ex2_rs2)
            forward_2b = 3'b001;

        else if (wb2_valid && wb2_regwrite && wb2_rd != 0 &&
                 wb2_rd == ex2_rs2)
            forward_2b = 3'b010;

    end

    /*
    1. My formal properties live here
    2. All asserts, assumes, and covers are defined here
    3. Use these during SymbiYosys for formal verification
     */

endmodule