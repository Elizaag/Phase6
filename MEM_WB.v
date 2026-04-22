module MEM_WB (
    input        iClk,
    input        iRstN,
    input        iStall,

    // Control signals in
    input        iLui,
    input        iMemtoReg,
    input        iRegWrite,
    input        iJump,
    input        iSystem,

    // Data signals in
    input [31:0] iMemReadData,
    input [31:0] iAluOut,
    input [31:0] iImm,
    input [31:0] iPcPlus4,
    input [4:0]  iRd,

    // Control signals out
    output reg        oLui,
    output reg        oMemtoReg,
    output reg        oRegWrite,
    output reg        oJump,
    output reg        oSystem,

    // Data signals out
    output reg [31:0] oMemReadData,
    output reg [31:0] oAluOut,
    output reg [31:0] oImm,
    output reg [31:0] oPcPlus4,
    output reg [4:0]  oRd
);

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            oLui         <= 1'b0;
            oMemtoReg    <= 1'b0;
            oRegWrite    <= 1'b0;
            oJump        <= 1'b0;
            oSystem      <= 1'b0;
            oMemReadData <= 32'b0;
            oAluOut      <= 32'b0;
            oImm         <= 32'b0;
            oPcPlus4     <= 32'b0;
            oRd          <= 5'b0;
        end else if (!iStall) begin
            oLui         <= iLui;
            oMemtoReg    <= iMemtoReg;
            oRegWrite    <= iRegWrite;
            oJump        <= iJump;
            oSystem      <= iSystem;
            oMemReadData <= iMemReadData;
            oAluOut      <= iAluOut;
            oImm         <= iImm;
            oPcPlus4     <= iPcPlus4;
            oRd          <= iRd;
        end
    end

endmodule
