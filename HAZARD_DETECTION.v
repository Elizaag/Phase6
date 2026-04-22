module HAZARD_DETECTION (
    // Load instruction currently in EX stage (ID/EX register)
    input       iID_EX_MemRd,
    input [4:0] iID_EX_Rd,

    // Instruction currently in ID stage (IF/ID register)
    input [4:0] iIF_ID_Rs1,
    input [4:0] iIF_ID_Rs2,

    // Stall/flush control outputs
    output reg  oPCWrite,      // 0 = stall PC (hold current PC)
    output reg  oIF_IDWrite,   // 0 = stall IF/ID register (hold instruction)
    output reg  oID_EX_Flush   // 1 = flush ID/EX (insert bubble)
);

    always @(*) begin
        // Detect load-to-use hazard:
        // If instruction in EX is a load AND its destination
        // matches either source of the instruction in ID → stall
        if (iID_EX_MemRd &&
            (iID_EX_Rd != 5'b0) &&
            ((iID_EX_Rd == iIF_ID_Rs1) || (iID_EX_Rd == iIF_ID_Rs2)))
        begin
            oPCWrite     = 1'b0; // Freeze PC
            oIF_IDWrite  = 1'b0; // Freeze IF/ID
            oID_EX_Flush = 1'b1; // Insert bubble into ID/EX
        end else begin
            oPCWrite     = 1'b1; // Normal operation
            oIF_IDWrite  = 1'b1; // Normal operation
            oID_EX_Flush = 1'b0; // No flush
        end
    end

endmodule
