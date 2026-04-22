module DATA_MEMORY (
    input        iClk,
    input        iRstN,
    input [31:0] iAddress,
    input [31:0] iWriteData,
    input [2:0]  iFunct3,
    input        iMemWrite,
    input        iMemRead,
    output [31:0] oReadData
);

    localparam B = 8;
    localparam K = 1024;

    // 4KB data memory, byte-addressable
    reg [B-1:0] rDataMem [0:(K*4)-1];

    // Use lower 12 bits for 4KB byte addressing
    wire [11:0] addr = iAddress[11:0];

    initial begin
        $readmemh("data.txt", rDataMem);
    end

    // --------------------
    // Write logic (sync)
    // --------------------
    always @(posedge iClk) begin
        if (iMemWrite) begin
            case (iFunct3)
                3'b000: begin // SB
                    rDataMem[addr] <= iWriteData[7:0];
                end

                3'b001: begin // SH
                    rDataMem[addr]     <= iWriteData[7:0];
                    rDataMem[addr + 1] <= iWriteData[15:8];
                end

                3'b010: begin // SW
                    rDataMem[addr]     <= iWriteData[7:0];
                    rDataMem[addr + 1] <= iWriteData[15:8];
                    rDataMem[addr + 2] <= iWriteData[23:16];
                    rDataMem[addr + 3] <= iWriteData[31:24];
                end

                default: begin
                    // no write
                end
            endcase
        end
    end

    // --------------------
    // Read logic (async)
    // --------------------
    reg [31:0] read_data_r;

    always @(*) begin
        if (iMemRead) begin
            case (iFunct3)

                3'b000: begin // LB (sign-extend)
                    read_data_r = {{24{rDataMem[addr][7]}}, rDataMem[addr]};
                end

                3'b001: begin // LH (sign-extend)
                    read_data_r = {{16{rDataMem[addr + 1][7]}},
                                   rDataMem[addr + 1],
                                   rDataMem[addr]};
                end

                3'b010: begin // LW
                    read_data_r = {rDataMem[addr + 3],
                                   rDataMem[addr + 2],
                                   rDataMem[addr + 1],
                                   rDataMem[addr]};
                end

                3'b100: begin // LBU
                    read_data_r = {24'b0, rDataMem[addr]};
                end

                3'b101: begin // LHU
                    read_data_r = {16'b0,
                                   rDataMem[addr + 1],
                                   rDataMem[addr]};
                end

                default: read_data_r = 32'b0;
            endcase
        end else begin
            read_data_r = 32'b0;
        end
    end

    assign oReadData = read_data_r;

endmodule