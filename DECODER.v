// DECODER module definition
module DECODER (
    input  [31:0] iInstr,   // 32 bit instruction input
    output [6:0]  oOpcode,  // 7 bit opcode output (all types)
    output [4:0]  oRd,      // 5 bit destination register output (R, I, U, J)
    output [2:0]  oFunct3,  // 3 bit function output (R, I, S, B)
    output [4:0]  oRs1,     // 5 bit source register (R, I, S, B)
    output [4:0]  oRs2,     // 5 bit source register (R, S, B)
    output [6:0]  oFunct7,  // 7 bit function output (R)
    output [31:0] oImm      // 32 bit immediate output (I, S, B, U, J)
);

    // -------------------------
    // Basic bitfield extraction
    // -------------------------
    assign oOpcode = iInstr[6:0];
    assign oRd     = iInstr[11:7];
    assign oFunct3 = iInstr[14:12];
    assign oRs1    = iInstr[19:15];
    assign oRs2    = iInstr[24:20];
    assign oFunct7 = iInstr[31:25];

    // -------------------------
    // Immediate generation
    // -------------------------
    reg [31:0] imm_r;

    always @(*) begin
        case (oOpcode)

            // I-type (ADDI, LW, JALR)
            7'b0010011,
            7'b0000011,
            7'b1100111: begin
                imm_r = {{20{iInstr[31]}}, iInstr[31:20]};
            end

            // S-type (SW)
            7'b0100011: begin
                imm_r = {{20{iInstr[31]}}, iInstr[31:25], iInstr[11:7]};
            end

            // B-type (branches)
            7'b1100011: begin
                imm_r = {{19{iInstr[31]}},
                         iInstr[31],
                         iInstr[7],
                         iInstr[30:25],
                         iInstr[11:8],
                         1'b0};
            end

            // U-type (LUI, AUIPC)
            7'b0110111,
            7'b0010111: begin
                imm_r = {iInstr[31:12], 12'b0};
            end

            // J-type (JAL)
            7'b1101111: begin
                imm_r = {{11{iInstr[31]}},
                         iInstr[31],
                         iInstr[19:12],
                         iInstr[20],
                         iInstr[30:21],
                         1'b0};
            end

            // R-type or unsupported
            default: begin
                imm_r = 32'b0;
            end
        endcase
    end

    assign oImm = imm_r;

endmodule