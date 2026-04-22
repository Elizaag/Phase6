module ALU_CONTROL (
    input  [2:0] iAluOp,
    input  [2:0] iFunct3,
    input  [6:0] iFunct7,
    output [3:0] oAluCtrl
);

    // =========================
    // ALU operation encodings
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

    // Branch comparisons
    localparam BEQ  = 4'b1000;
    localparam BNE  = 4'b1100;
    localparam BLT  = 4'b1010;
    localparam BGE  = 4'b1110;
    localparam BLTU = 4'b1011;
    localparam BGEU = 4'b1111;

    reg [3:0] alu_ctrl_r;

    always @(*) begin
        case (iAluOp)

            // ======================================================
            // CHANGE #1:
            // AluOp = 000 → FORCE ADD
            // Used for:
            //  - Loads
            //  - Stores
            //  - AUIPC
            //  - JAL / JALR address calc
            // ======================================================
            3'b000: begin
                alu_ctrl_r = ADD;
            end

            // ======================================================
            // Branch instructions
            // ======================================================
            3'b001: begin
                case (iFunct3)
                    3'b000: alu_ctrl_r = BEQ;
                    3'b001: alu_ctrl_r = BNE;
                    3'b100: alu_ctrl_r = BLT;
                    3'b101: alu_ctrl_r = BGE;
                    3'b110: alu_ctrl_r = BLTU;
                    3'b111: alu_ctrl_r = BGEU;
                    default: alu_ctrl_r = ADD;
                endcase
            end

            // ======================================================
            // R-type instructions
            // ======================================================
            3'b010: begin
                case (iFunct3)
                    3'b000: alu_ctrl_r = (iFunct7[5] ? SUB : ADD);
                    3'b001: alu_ctrl_r = SLL;
                    3'b010: alu_ctrl_r = SLT;
                    3'b011: alu_ctrl_r = SLTU;
                    3'b100: alu_ctrl_r = XOR;
                    3'b101: alu_ctrl_r = (iFunct7[5] ? SRA : SRL);
                    3'b110: alu_ctrl_r = OR;
                    3'b111: alu_ctrl_r = AND;
                    default: alu_ctrl_r = ADD;
                endcase
            end

            // ======================================================
            // CHANGE #2:
            // AluOp = 011 → I-type ALU decode
            // Used ONLY for:
            //  - ADDI, ANDI, ORI, XORI
            //  - SLLI, SRLI, SRAI
            //  - SLTI, SLTIU
            // ======================================================
            3'b011: begin
                case (iFunct3)
                    3'b000: alu_ctrl_r = ADD;   // ADDI
                    3'b001: alu_ctrl_r = SLL;   // SLLI
                    3'b010: alu_ctrl_r = SLT;   // SLTI
                    3'b011: alu_ctrl_r = SLTU;  // SLTIU
                    3'b100: alu_ctrl_r = XOR;   // XORI
                    3'b101: alu_ctrl_r = (iFunct7[5] ? SRA : SRL); // SRLI/SRAI
                    3'b110: alu_ctrl_r = OR;    // ORI
                    3'b111: alu_ctrl_r = AND;   // ANDI
                    default: alu_ctrl_r = ADD;
                endcase
            end

            // ======================================================
            // Default safety
            // ======================================================
            default: alu_ctrl_r = ADD;
        endcase
    end

    assign oAluCtrl = alu_ctrl_r;

endmodule