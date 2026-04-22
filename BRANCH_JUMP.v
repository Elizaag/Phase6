module BRANCH_JUMP (
    input        iBranch,
    input        iJump,
    input        iZero,
    input [31:0] iOffset,
    input [31:0] iPc,
    input [31:0] iRs1,
    input [31:0] iRs2,        
    input [2:0]  iFunct3,         
    input        iPcSrc,
    output [31:0] oPc,
    output branch_taken
);

    reg [31:0] pc_next;

    reg branch_taken;
    
    always @(*) begin
        case (iFunct3)
        3'b000: branch_taken = iZero;           // BEQ
        3'b001: branch_taken = !iZero;          // BNE
        3'b100: branch_taken = $signed(iRs1) < $signed(iRs2);  // BLT
        3'b101: branch_taken = $signed(iRs1) >= $signed(iRs2); // BGE
        3'b110: branch_taken = iRs1 < iRs2;    // BLTU
        3'b111: branch_taken = iRs1 >= iRs2;   // BGEU
        default: branch_taken = 1'b0;
    endcase

        if (iJump) begin
            if (iPcSrc)
                // JALR: (rs1 + offset) with LSB cleared
                pc_next = (iRs1 + iOffset) & 32'hFFFFFFFE;
            else
                // JAL: PC + offset
                pc_next = iPc + iOffset;
        end
        else if (iBranch && iZero) begin
            // Taken branch
            pc_next = iPc + iOffset;
        end
        else begin
            // Default: next sequential instruction
            pc_next = iPc + 32'd4;
        end
    end

    assign oPc = pc_next;

endmodule