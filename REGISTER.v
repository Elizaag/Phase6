module REGISTER (
    input        iClk,
    input        iRstN,
    input        iWriteEn,
    input  [4:0] iRdAddr,
    input  [4:0] iRs1Addr,
    input  [4:0] iRs2Addr,
    input  [31:0] iWriteData,
    output [31:0] oRs1Data,
    output [31:0] oRs2Data
);

    reg [31:0] registers [0:31];
    integer i;

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else if (iWriteEn && iRdAddr != 0) begin
            registers[iRdAddr] <= iWriteData;
        end
    end

    // Write-first forwarding: if WB is writing to the same register
    // being read in ID this cycle, return the new write data directly.
    // This avoids a one-cycle stale read when WB and ID overlap.
    assign oRs1Data = (iRs1Addr == 5'b0)                          ? 32'b0 :
                      (iWriteEn && iRdAddr == iRs1Addr)            ? iWriteData :
                                                                     registers[iRs1Addr];

    assign oRs2Data = (iRs2Addr == 5'b0)                          ? 32'b0 :
                      (iWriteEn && iRdAddr == iRs2Addr)            ? iWriteData :
                                                                     registers[iRs2Addr];

endmodule
