module ALU (
    input  [31:0] iDataA,
    input  [31:0] iDataB,
    input  [3:0]  iAluCtrl,
    output [31:0] oData,
    output        oZero
);

    // =========================
    // ALU control codes
    // =========================
    localparam ADD  = 4'b0000;
    localparam SUB  = 4'b1000;

    localparam SLL  = 4'b0001;
    localparam SRL  = 4'b1001;
    localparam SRA  = 4'b1101;

    localparam SLT  = 4'b0010;
    localparam SLTU = 4'b0011;

    localparam XOR  = 4'b0100;
    localparam OR   = 4'b0110;
    localparam AND  = 4'b0111;

    // Branch operations (share encodings, but handled separately)
    localparam BEQ  = 4'b1000;
    localparam BNE  = 4'b1100;
    localparam BLT  = 4'b1010;
    localparam BGE  = 4'b1110;
    localparam BLTU = 4'b1011;
    localparam BGEU = 4'b1111;

    reg [31:0] result;
    reg        zero_flag;

    always @(*) begin
        // -------------------------
        // Defaults
        // -------------------------
        result    = 32'b0;
        zero_flag = 1'b0;

        // ==================================================
        // Arithmetic / logical operations (produce result)
        // ==================================================
        case (iAluCtrl)
            ADD:  result = iDataA + iDataB;
            SUB:  result = iDataA - iDataB;

            SLL:  result = iDataA <<  iDataB[4:0];
            SRL:  result = iDataA >>  iDataB[4:0];
            SRA:  result = $signed(iDataA) >>> iDataB[4:0];

            SLT:  result = ($signed(iDataA) <  $signed(iDataB)) ? 32'd1 : 32'd0;
            SLTU: result = ($unsigned(iDataA) < $unsigned(iDataB)) ? 32'd1 : 32'd0;

            XOR:  result = iDataA ^ iDataB;
            OR:   result = iDataA | iDataB;
            AND:  result = iDataA & iDataB;

            default: result = 32'b0;
        endcase

        // ==================================================
        // Branch condition evaluation (sets zero_flag only)
        // ==================================================
        case (iAluCtrl)
            BEQ:  zero_flag = (iDataA == iDataB);
            BNE:  zero_flag = (iDataA != iDataB);
            BLT:  zero_flag = ($signed(iDataA) <  $signed(iDataB));
            BGE:  zero_flag = ($signed(iDataA) >= $signed(iDataB));
            BLTU: zero_flag = ($unsigned(iDataA) <  $unsigned(iDataB));
            BGEU: zero_flag = ($unsigned(iDataA) >= $unsigned(iDataB));
            default: zero_flag = (result == 32'b0);
        endcase
    end

    assign oData = result;
    assign oZero = zero_flag;

endmodule
