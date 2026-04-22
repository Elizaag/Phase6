module MUX_3_1 #(
    parameter WIDTH = 32
) (
    input [WIDTH-1:0] iData0,  // 2'b00 - register file value
    input [WIDTH-1:0] iData1,  // 2'b01 - forward from MEM/WB
    input [WIDTH-1:0] iData2,  // 2'b10 - forward from EX/MEM
    input [1:0]       iSel,
    output [WIDTH-1:0] oData
);

    assign oData = (iSel == 2'b10) ? iData2 :
                   (iSel == 2'b01) ? iData1 :
                                     iData0;

endmodule
