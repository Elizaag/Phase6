module EX_MEM (
    input        iClk,
    input        iRstN,
    input        iFlush,
    input        iStall,

    // Control signals in
    input        iLui,
    input        iMemRd,
    input        iMemWr,
    input        iMemtoReg,
    input        iRegWrite,
    input        iBranch,
    input        iJump,
    input        iPcSrc,
    input        iSystem,

    // Data signals in
    input [31:0] iAluOut,
    input        iAluZero,
    input [31:0] iRs2Data,
    input [31:0] iImm,
    input [31:0] iPcPlus4,
    input [31:0] iPC,
    input [2:0]  iFunct3,
    input [4:0]  iRd,
    input [4:0]  iRs2,

    // Control signals out
    output reg        oLui,
    output reg        oMemRd,
    output reg        oMemWr,
    output reg        oMemtoReg,
    output reg        oRegWrite,
    output reg        oBranch,
    output reg        oJump,
    output reg        oPcSrc,
    output reg        oSystem,

    // Data signals out
    output reg [31:0] oAluOut,
    output reg        oAluZero,
    output reg [31:0] oRs2Data,
    output reg [31:0] oImm,
    output reg [31:0] oPcPlus4,
    output reg [31:0] oPC,
    output reg [2:0]  oFunct3,
    output reg [4:0]  oRd,
    output reg [4:0]  oRs2
);

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN || iFlush) begin
            oLui      <= 1'b0;
            oMemRd    <= 1'b0;
            oMemWr    <= 1'b0;
            oMemtoReg <= 1'b0;
            oRegWrite <= 1'b0;
            oBranch   <= 1'b0;
            oJump     <= 1'b0;
            oPcSrc    <= 1'b0;
            oSystem   <= 1'b0;
            oAluOut   <= 32'b0;
            oAluZero  <= 1'b0;
            oRs2Data  <= 32'b0;
            oImm      <= 32'b0;
            oPcPlus4  <= 32'b0;
            oPC       <= 32'b0;
            oFunct3   <= 3'b0;
            oRd       <= 5'b0;
            oRs2      <= 5'b0;
        end else if (!iStall) begin
            oLui      <= iLui;
            oMemRd    <= iMemRd;
            oMemWr    <= iMemWr;
            oMemtoReg <= iMemtoReg;
            oRegWrite <= iRegWrite;
            oBranch   <= iBranch;
            oJump     <= iJump;
            oPcSrc    <= iPcSrc;
            oSystem   <= iSystem;
            oAluOut   <= iAluOut;
            oAluZero  <= iAluZero;
            oRs2Data  <= iRs2Data;
            oImm      <= iImm;
            oPcPlus4  <= iPcPlus4;
            oPC       <= iPC;
            oFunct3   <= iFunct3;
            oRd       <= iRd;
            oRs2      <= iRs2;
        end
    end

endmodule
