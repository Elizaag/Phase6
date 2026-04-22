// iverilog -o riscv_sim RISCV_TOP.v CACHE.v MUX_2_1.v MUX_3_1.v ALU_CONTROL.v ALU.v REGISTER.v DATA_MEMORY.v INSTRUCTION_MEMORY.v DECODER.v CONTROL.v BRANCH_JUMP.v IF_ID.v ID_EX.v EX_MEM.v MEM_WB.v FORWARDING_UNIT.v HAZARD_DETECTION.v

module RISCV_TOP (
    input iClk,
    input iRstN
);

    // ==========================================================
    // Hazard / stall control wires
    // ==========================================================
    wire       pcWrite;
    wire       if_id_write;
    wire       id_ex_flush;

    // Branch/jump flush
    wire       branch_flush;

    // ==========================================================
    // Program Counter
    // ==========================================================
    reg  [31:0] wPC;
    wire [31:0] wNextPC;
    wire [31:0] pc_plus4;

    assign pc_plus4 = wPC + 32'd4;

    // ==========================================================
    // IF Stage: Instruction Fetch through cache
    // ==========================================================
    wire [31:0] wInstr;

    wire        ic_mem_we;
    wire [31:0] ic_mem_addr;
    wire [31:0] ic_mem_wdata;
    wire [31:0] ic_mem_rdata;
    wire        icache_stall;

    CACHE icache (
        .i_clk(iClk),
        .i_rstn(iRstN), 
        .i_read (1'b1),
        .i_write (1'b0),
        .i_addr (wPC),
        .i_cpu_data (32'b0),
        .i_funct (2'b10),
        .i_mem_ready (1'b1),
        .i_mem_valid (1'b1),
        .i_mem_rd_data(ic_mem_rdata),
        .o_cpu_data (wInstr),
        .o_miss (icache_stall),
        .o_mem_rd (ic_mem_rd),
        .o_mem_rd_addr(ic_mem_addr),
        .o_mem_wr (),
        .o_mem_wr_addr (),
        .o_mem_wr_data ()
    );

    INSTRUCTION_MEMORY imem (
        .iRdAddr(ic_mem_addr),
        .oInstr(ic_mem_rdata)
    );

    // Treat any non-idle cache state as busy.
    // This avoids the CPU running ahead while the cache is still in compare/prefetch/fill.
    wire icache_busy;
    assign icache_busy = (icache.state != 3'd0);

    // ==========================================================
    // IF/ID Pipeline Register
    // ==========================================================
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;

    // ==========================================================
    // ID Stage: Decode
    // ==========================================================
    wire [6:0]  id_opcode;
    wire [4:0]  id_rd, id_rs1_pre, id_rs1, id_rs2;
    wire [2:0]  id_funct3;
    wire [6:0]  id_funct7;
    wire [31:0] id_imm;

    // ==========================================================
    // ID Stage: Control
    // ==========================================================
    wire        id_lui, id_pcSrc, id_memRd, id_memWr;
    wire        id_memtoReg, id_aluSrc1, id_aluSrc2;
    wire        id_regWrite, id_branch, id_jump;
    wire [2:0]  id_aluOp;
    wire        id_falseRs1, id_falseRs2;

    // ==========================================================
    // ID Stage: Register File
    // ==========================================================
    wire [31:0] id_rs1Data, id_rs2Data;

    // MEM/WB writeback wires (declared here, driven later)
    wire        mem_wb_regWrite;
    wire [4:0]  mem_wb_rd;
    wire [31:0] wb_to_reg;

    // ==========================================================
    // Hazard Detection Unit
    // ==========================================================
    wire       id_ex_memRd_fwd, id_memWr_fwd;
    wire [4:0] id_ex_rd_fwd;

    // ==========================================================
    // ID/EX Pipeline Register
    // ==========================================================
    wire        id_ex_lui, id_ex_pcSrc, id_ex_memRd, id_ex_memWr;
    wire        id_ex_memtoReg, id_ex_aluSrc1, id_ex_aluSrc2;
    wire        id_ex_regWrite, id_ex_branch, id_ex_jump;
    wire [2:0]  id_ex_aluOp;
    wire [31:0] id_ex_pc, id_ex_rs1Data, id_ex_rs2Data, id_ex_imm;
    wire [2:0]  id_ex_funct3;
    wire [6:0]  id_ex_funct7;
    wire [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;

    // ==========================================================
    // EX Stage: Forwarding Unit
    // ==========================================================
    wire [1:0] forwardA, forwardB;
    wire       forwardM;

    wire        ex_mem_regWrite;
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_memWr;
    wire [4:0]  ex_mem_rs2;
    wire        mem_wb_memtoReg;

    // ==========================================================
    // EX Stage: ALU input muxes with forwarding
    // ==========================================================
    wire [31:0] ex_mem_aluOut;
    wire [31:0] fwd_rs1;
    wire [31:0] fwd_rs2;
    wire [31:0] aluInA;
    wire [31:0] aluInB;

    // ==========================================================
    // EX Stage: ALU Control + ALU
    // ==========================================================
    wire [3:0]  aluCtrl;
    wire [31:0] ex_aluOut;
    wire        ex_aluZero;
    wire [31:0] ex_pc_plus4;

    // ==========================================================
    // Branch/Jump resolution
    // ==========================================================
    wire [31:0] ex_nextPC;

    // ==========================================================
    // EX/MEM Pipeline Register
    // ==========================================================
    wire        ex_mem_lui, ex_mem_memRd;
    wire        ex_mem_memtoReg, ex_mem_branch, ex_mem_jump, ex_mem_pcSrc;
    wire        ex_mem_aluZero;
    wire [31:0] ex_mem_rs2Data, ex_mem_imm, ex_mem_pcPlus4, ex_mem_pc;
    wire [31:0] mem_wb_memReadData, mem_wb_aluOut, mem_wb_imm, mem_wb_pcPlus4;
    wire [2:0]  ex_mem_funct3;

    // ==========================================================
    // MEM Stage: Data Cache
    // ==========================================================
    wire [31:0] mem_readData;
    wire [31:0] ex_mem_fwd_data;

    wire        dc_mem_we;
    wire [31:0] dc_mem_addr;
    wire [31:0] dc_mem_wdata;
    wire [31:0] dc_mem_rdata;
    wire        dcache_stall;

    CACHE dcache (
        .clk(iClk),
        .rst(!iRstN),
        .cpu_re(ex_mem_memRd),
        .cpu_we(ex_mem_memWr),
        .cpu_addr(ex_mem_aluOut),
        .cpu_wdata(ex_mem_fwd_data),
        .cpu_funct3(ex_mem_funct3),
        .cpu_rdata(mem_readData),
        .cpu_stall(dcache_stall),
        .mem_we(dc_mem_we),
        .mem_addr(dc_mem_addr),
        .mem_wdata(dc_mem_wdata),
        .mem_rdata(dc_mem_rdata)
    );

    DATA_MEMORY data_memory (
        .iClk(iClk),
        .iRstN(iRstN),
        .iAddress(dc_mem_addr),
        .iWriteData(dc_mem_wdata),
        .iFunct3(3'b010),      // backing memory is word-at-a-time for cache fills/writebacks
        .iMemWrite(dc_mem_we),
        .iMemRead(1'b1),
        .oReadData(dc_mem_rdata)
    );

    wire dcache_busy;
    assign dcache_busy = (dcache.state != 3'd0);

    // Freeze the whole visible pipeline while either cache is busy.
    wire cache_freeze;
    assign cache_freeze = icache_busy | dcache_busy;

    // Only freeze the pipeline regs on cache activity.
    // Keep the cache/memory themselves on the real clock so fills can complete.
    //The following lines not needed
    // wire pipeClk;
    //assign pipeClk = iClk & ~cache_freeze;

    // PC update: hazard unit still controls normal load-use stalls.
    // Cache activity also freezes the PC.
    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN)
            wPC <= 32'd0;
        else if (pcWrite && !cache_freeze)
            wPC <= wNextPC;
    end

    IF_ID if_id_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iFlush(branch_flush),
        .iStall((!if_id_write) | cache_freeze),
        .iPC(wPC),
        .iInstr(wInstr),
        .oPC(if_id_pc),
        .oInstr(if_id_instr)
    );

    DECODER decoder (
        .iInstr(if_id_instr),
        .oOpcode(id_opcode),
        .oRd(id_rd),
        .oFunct3(id_funct3),
        .oRs1(id_rs1_pre),
        .oRs2(id_rs2),
        .oFunct7(id_funct7),
        .oImm(id_imm)
    );

    CONTROL control (
        .iOpcode(id_opcode),
        .oLui(id_lui),
        .oPcSrc(id_pcSrc),
        .oMemRd(id_memRd),
        .oMemWr(id_memWr),
        .oAluOp(id_aluOp),
        .oMemtoReg(id_memtoReg),
        .oAluSrc1(id_aluSrc1),
        .oAluSrc2(id_aluSrc2),
        .oRegWrite(id_regWrite),
        .oBranch(id_branch),
        .oJump(id_jump),
        .oFalseRs1(id_falseRs1),
        .oFalseRs2(id_falseRs2)
    );

    assign id_rs1 = (id_lui) ? 5'b0 : id_rs1_pre;

    REGISTER register (
        .iClk(iClk),
        .iRstN(iRstN),
        .iWriteEn(mem_wb_regWrite),
        .iRdAddr(mem_wb_rd),
        .iRs1Addr(id_rs1),
        .iRs2Addr(id_rs2),
        .iWriteData(wb_to_reg),
        .oRs1Data(id_rs1Data),
        .oRs2Data(id_rs2Data)
    );

    HAZARD_DETECTION hazard_detect (
        .iID_EX_MemRd(id_ex_memRd_fwd),
        .iID_EX_MemWr(id_memWr_fwd),
        .iID_EX_Rd(id_ex_rd_fwd),
        .iIF_ID_Rs1(id_rs1),
        .iIF_ID_Rs2(id_rs2),
        .iFalseRs1(id_falseRs1),
        .iFalseRs2(id_falseRs2),
        .oPCWrite(pcWrite),
        .oIF_IDWrite(if_id_write),
        .oID_EX_Flush(id_ex_flush)
    );

    assign id_ex_memRd_fwd = id_ex_memRd;
    assign id_memWr_fwd    = id_ex_memWr;
    assign id_ex_rd_fwd    = id_ex_rd;

    ID_EX id_ex_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iFlush(id_ex_flush | branch_flush),
        .iStall(cache_freeze),
        .iLui(id_lui),
        .iPcSrc(id_pcSrc),
        .iMemRd(id_memRd),
        .iMemWr(id_memWr),
        .iAluOp(id_aluOp),
        .iMemtoReg(id_memtoReg),
        .iAluSrc1(id_aluSrc1),
        .iAluSrc2(id_aluSrc2),
        .iRegWrite(id_regWrite),
        .iBranch(id_branch),
        .iJump(id_jump),
        .iPC(if_id_pc),
        .iRs1Data(id_rs1Data),
        .iRs2Data(id_rs2Data),
        .iImm(id_imm),
        .iFunct3(id_funct3),
        .iFunct7(id_funct7),
        .iRs1(id_rs1),
        .iRs2(id_rs2),
        .iRd(id_rd),
        .oLui(id_ex_lui),
        .oPcSrc(id_ex_pcSrc),
        .oMemRd(id_ex_memRd),
        .oMemWr(id_ex_memWr),
        .oAluOp(id_ex_aluOp),
        .oMemtoReg(id_ex_memtoReg),
        .oAluSrc1(id_ex_aluSrc1),
        .oAluSrc2(id_ex_aluSrc2),
        .oRegWrite(id_ex_regWrite),
        .oBranch(id_ex_branch),
        .oJump(id_ex_jump),
        .oPC(id_ex_pc),
        .oRs1Data(id_ex_rs1Data),
        .oRs2Data(id_ex_rs2Data),
        .oImm(id_ex_imm),
        .oFunct3(id_ex_funct3),
        .oFunct7(id_ex_funct7),
        .oRs1(id_ex_rs1),
        .oRs2(id_ex_rs2),
        .oRd(id_ex_rd)
    );

    FORWARDING_UNIT fwd_unit (
        .iID_EX_Rs1(id_ex_rs1),
        .iID_EX_Rs2(id_ex_rs2),
        .iEX_MEM_Rd(ex_mem_rd),
        .iEX_MEM_RegWrite(ex_mem_regWrite),
        .iEX_MEM_DataWrite(ex_mem_memWr),
        .iMEM_WB_Rd(mem_wb_rd),
        .iMEM_WB_RegWrite(mem_wb_regWrite),
        .iEX_MEM_Rs2Addr(ex_mem_rs2),
        .iMEM_WB_DataRead(mem_wb_memtoReg),
        .oForwardA(forwardA),
        .oForwardB(forwardB),
        .oForwardM(forwardM)
    );

    MUX_3_1 #(.WIDTH(32)) mux_fwdA (
        .iData0(id_ex_rs1Data),
        .iData1(wb_to_reg),
        .iData2(ex_mem_aluOut),
        .iSel(forwardA),
        .oData(fwd_rs1)
    );

    MUX_3_1 #(.WIDTH(32)) mux_fwdB (
        .iData0(id_ex_rs2Data),
        .iData1(wb_to_reg),
        .iData2(ex_mem_aluOut),
        .iSel(forwardB),
        .oData(fwd_rs2)
    );

    MUX_2_1 #(.WIDTH(32)) muxA (
        .iData0(fwd_rs1),
        .iData1(id_ex_pc),
        .iSel(id_ex_aluSrc1),
        .oData(aluInA)
    );

    MUX_2_1 #(.WIDTH(32)) muxB (
        .iData0(fwd_rs2),
        .iData1(id_ex_imm),
        .iSel(id_ex_aluSrc2),
        .oData(aluInB)
    );

    ALU_CONTROL alu_control (
        .iAluOp(id_ex_aluOp),
        .iFunct3(id_ex_funct3),
        .iFunct7(id_ex_funct7),
        .oAluCtrl(aluCtrl)
    );

    ALU alu (
        .iDataA(aluInA),
        .iDataB(aluInB),
        .iAluCtrl(aluCtrl),
        .oData(ex_aluOut),
        .oZero(ex_aluZero)
    );

    assign ex_pc_plus4 = id_ex_pc + 32'd4;

    BRANCH_JUMP branch_jump (
        .iBranch(id_ex_branch),
        .iJump(id_ex_jump),
        .iZero(ex_aluZero),
        .iOffset(id_ex_imm),
        .iPc(id_ex_pc),
        .iRs1(fwd_rs1),
        .iRs2(fwd_rs2),        
        .iFunct3(id_ex_funct3), 
        .iPcSrc(id_ex_pcSrc),
        .oPc(ex_nextPC)
    );
    wire branch_taken;
    assign branch_flush = (id_ex_branch & branch_taken) | id_ex_jump;
    assign wNextPC      = branch_flush ? ex_nextPC : pc_plus4;

    EX_MEM ex_mem_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iFlush(1'b0),
        .iStall(cache_freeze),
        .iLui(id_ex_lui),
        .iMemRd(id_ex_memRd),
        .iMemWr(id_ex_memWr),
        .iMemtoReg(id_ex_memtoReg),
        .iRegWrite(id_ex_regWrite),
        .iBranch(id_ex_branch),
        .iJump(id_ex_jump),
        .iPcSrc(id_ex_pcSrc),
        .iAluOut(ex_aluOut),
        .iAluZero(ex_aluZero),
        .iRs2Data(fwd_rs2),
        .iImm(id_ex_imm),
        .iPcPlus4(ex_pc_plus4),
        .iPC(id_ex_pc),
        .iFunct3(id_ex_funct3),
        .iRd(id_ex_rd),
        .iRs2(id_ex_rs2),
        .oLui(ex_mem_lui),
        .oMemRd(ex_mem_memRd),
        .oMemWr(ex_mem_memWr),
        .oMemtoReg(ex_mem_memtoReg),
        .oRegWrite(ex_mem_regWrite),
        .oBranch(ex_mem_branch),
        .oJump(ex_mem_jump),
        .oPcSrc(ex_mem_pcSrc),
        .oAluOut(ex_mem_aluOut),
        .oAluZero(ex_mem_aluZero),
        .oRs2Data(ex_mem_rs2Data),
        .oImm(ex_mem_imm),
        .oPcPlus4(ex_mem_pcPlus4),
        .oPC(ex_mem_pc),
        .oFunct3(ex_mem_funct3),
        .oRd(ex_mem_rd),
        .oRs2(ex_mem_rs2)
    );

    assign ex_mem_fwd_data = (forwardM) ? mem_wb_memReadData : ex_mem_rs2Data;

    MEM_WB mem_wb_reg (
        .iClk(iClk),
        .iRstN(iRstN),
        .iStall(cache_freeze), 
        .iLui(ex_mem_lui),
        .iMemtoReg(ex_mem_memtoReg),
        .iRegWrite(ex_mem_regWrite),
        .iJump(ex_mem_jump),
        .iMemReadData(mem_readData),
        .iAluOut(ex_mem_aluOut),
        .iImm(ex_mem_imm),
        .iPcPlus4(ex_mem_pcPlus4),
        .iRd(ex_mem_rd),
        .oLui(mem_wb_lui),
        .oMemtoReg(mem_wb_memtoReg),
        .oRegWrite(mem_wb_regWrite),
        .oJump(mem_wb_jump),
        .oMemReadData(mem_wb_memReadData),
        .oAluOut(mem_wb_aluOut),
        .oImm(mem_wb_imm),
        .oPcPlus4(mem_wb_pcPlus4),
        .oRd(mem_wb_rd)
    );

    // ==========================================================
    // WB Stage: Writeback muxes
    // ==========================================================
    wire [31:0] wb_mux0_out, wb_final;
    wire        mem_wb_lui, mem_wb_jump;

    MUX_2_1 #(.WIDTH(32)) muxWB0 (
        .iData0(mem_wb_aluOut),
        .iData1(mem_wb_memReadData),
        .iSel(mem_wb_memtoReg),
        .oData(wb_mux0_out)
    );

    MUX_2_1 #(.WIDTH(32)) muxWB1 (
        .iData0(wb_mux0_out),
        .iData1(mem_wb_imm),
        .iSel(mem_wb_lui),
        .oData(wb_final)
    );

    MUX_2_1 #(.WIDTH(32)) muxWB_JUMP (
        .iData0(wb_final),
        .iData1(mem_wb_pcPlus4),
        .iSel(mem_wb_jump),
        .oData(wb_to_reg)
    );

endmodule