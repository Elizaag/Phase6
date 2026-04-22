module FORWARDING_UNIT (
    // From ID/EX (current instruction in Execute)
    input [4:0] iID_EX_Rs1,
    input [4:0] iID_EX_Rs2,
    input [4:0] iEX_MEM_Rs2Addr,

    // From EX/MEM (instruction one stage ahead)
    input [4:0] iEX_MEM_Rd,
    input       iEX_MEM_DataWrite,
    input       iEX_MEM_RegWrite,

    // From MEM/WB (instruction two stages ahead)
    input [4:0] iMEM_WB_Rd,
    input       iMEM_WB_RegWrite,
    input       iMEM_WB_DataRead,

    // Forwarding select outputs
    // 2'b00 = no forward (use register file)
    // 2'b10 = forward from EX/MEM (EX->EX)
    // 2'b01 = forward from MEM/WB (MEM->EX)
    output reg [1:0] oForwardA,
    output reg [1:0] oForwardB,
    output reg oForwardM
);

    always @(*) begin
        // --- ForwardA (for Rs1) ---
        if (iEX_MEM_RegWrite && (iEX_MEM_Rd != 5'b0) && (iEX_MEM_Rd == iID_EX_Rs1))
            oForwardA = 2'b10; // EX->EX forwarding
        else if (iMEM_WB_RegWrite && (iMEM_WB_Rd != 5'b0) && (iMEM_WB_Rd == iID_EX_Rs1))
            oForwardA = 2'b01; // MEM->EX forwarding
        else
            oForwardA = 2'b00; // No forwarding

        // --- ForwardB (for Rs2) ---
        if (iEX_MEM_RegWrite && (iEX_MEM_Rd != 5'b0) && (iEX_MEM_Rd == iID_EX_Rs2))
            oForwardB = 2'b10; // EX->EX forwarding
        else if (iMEM_WB_RegWrite && (iMEM_WB_Rd != 5'b0) && (iMEM_WB_Rd == iID_EX_Rs2))
            oForwardB = 2'b01; // MEM->EX forwarding
        else
            oForwardB = 2'b00; // No forwarding

        // --- ForwardM (for MEM) ---
        if (iEX_MEM_DataWrite && iMEM_WB_DataRead && (iMEM_WB_Rd != 5'b0) && (iMEM_WB_Rd == iEX_MEM_Rs2Addr))
            oForwardM = 1'b1; // MEM->MEM forwarding
        else
            oForwardM = 1'b0; // No forwarding
    end

endmodule
