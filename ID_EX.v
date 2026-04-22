module ID_EX (
    input        iClk,
    input        iRstN,
    input        iFlush,
    input        iStall,

    // Control signals in
    input        iLui,
    input        iPcSrc,
    input        iMemRd,
    input        iMemWr,
    input [2:0]  iAluOp,
    input        iMemtoReg,
    input        iAluSrc1,
    input        iAluSrc2,
    input        iRegWrite,
    input        iBranch,
    input        iJump,
    input        iSystem,

    // Data signals in
    input [31:0] iPC,
    input [31:0] iRs1Data,
    input [31:0] iRs2Data,
    input [31:0] iImm,
    input [2:0]  iFunct3,
    input [6:0]  iFunct7,
    input [4:0]  iRs1,
    input [4:0]  iRs2,
    input [4:0]  iRd,

    // Control signals out
    output reg        oLui,
    output reg        oPcSrc,
    output reg        oMemRd,
    output reg        oMemWr,
    output reg [2:0]  oAluOp,
    output reg        oMemtoReg,
    output reg        oAluSrc1,
    output reg        oAluSrc2,
    output reg        oRegWrite,
    output reg        oBranch,
    output reg        oJump,
    output reg        oSystem,

    // Data signals out
    output reg [31:0] oPC,
    output reg [31:0] oRs1Data,
    output reg [31:0] oRs2Data,
    output reg [31:0] oImm,
    output reg [2:0]  oFunct3,
    output reg [6:0]  oFunct7,
    output reg [4:0]  oRs1,
    output reg [4:0]  oRs2,
    output reg [4:0]  oRd
);

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN || iFlush) begin
            // Flush: insert a bubble (zero out all control signals)
            oLui      <= 1'b0;
            oPcSrc    <= 1'b0;
            oMemRd    <= 1'b0;
            oMemWr    <= 1'b0;
            oAluOp    <= 3'b0;
            oMemtoReg <= 1'b0;
            oAluSrc1  <= 1'b0;
            oAluSrc2  <= 1'b0;
            oRegWrite <= 1'b0;
            oBranch   <= 1'b0;
            oJump     <= 1'b0;
            oSystem   <= 1'b0;
            oPC       <= 32'b0;
            oRs1Data  <= 32'b0;
            oRs2Data  <= 32'b0;
            oImm      <= 32'b0;
            oFunct3   <= 3'b0;
            oFunct7   <= 7'b0;
            oRs1      <= 5'b0;
            oRs2      <= 5'b0;
            oRd       <= 5'b0;
        end else if (!iStall) begin
            oLui      <= iLui;
            oPcSrc    <= iPcSrc;
            oMemRd    <= iMemRd;
            oMemWr    <= iMemWr;
            oAluOp    <= iAluOp;
            oMemtoReg <= iMemtoReg;
            oAluSrc1  <= iAluSrc1;
            oAluSrc2  <= iAluSrc2;
            oRegWrite <= iRegWrite;
            oBranch   <= iBranch;
            oJump     <= iJump;
            oSystem   <= iSystem;
            oPC       <= iPC;
            oRs1Data  <= iRs1Data;
            oRs2Data  <= iRs2Data;
            oImm      <= iImm;
            oFunct3   <= iFunct3;
            oFunct7   <= iFunct7;
            oRs1      <= iRs1;
            oRs2      <= iRs2;
            oRd       <= iRd;
        end
    end

endmodule
