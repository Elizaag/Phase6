module INSTRUCTION_MEMORY (
    input  [31:0] iRdAddr,
    output [31:0] oInstr
);

    localparam B = 8;
    localparam K = 1024;

    reg [B-1:0] rInstrMem [0:K-1];

    wire [9:0] addr = iRdAddr[9:0];  // <<< FIX

    initial begin
        $readmemh("instr.txt", rInstrMem);
    end

    assign oInstr = {
        rInstrMem[addr + 3],
        rInstrMem[addr + 2],
        rInstrMem[addr + 1],
        rInstrMem[addr]
    };

endmodule