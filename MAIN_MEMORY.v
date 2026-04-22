module MAIN_MEMORY #(
    parameter [31:0] TEXT_BASE   = 32'h0040_0000,
    parameter [31:0] DATA_BASE   = 32'h1001_0000,
    parameter [31:0] HEAP_BASE   = 32'h1004_0000,
    parameter integer TEXT_BYTES = 4096,
    parameter integer DATA_BYTES = 4096,
    parameter integer HEAP_BYTES = 4096,
    parameter integer BLOCK_BYTES = 16
) (
    input                        iClk,
    input                        iRstN,
    input      [31:0]            iInstrReadAddr,
    output reg [(BLOCK_BYTES*8)-1:0] oInstrReadBlock,
    input      [31:0]            iInstrPrefetchAddr,
    output reg [(BLOCK_BYTES*8)-1:0] oInstrPrefetchBlock,
    input      [31:0]            iDataReadAddr,
    output reg [(BLOCK_BYTES*8)-1:0] oDataReadBlock,
    input      [31:0]            iDataPrefetchAddr,
    output reg [(BLOCK_BYTES*8)-1:0] oDataPrefetchBlock,
    input                        iDataWriteBlockEn,
    input      [31:0]            iDataWriteAddr,
    input      [(BLOCK_BYTES*8)-1:0] iDataWriteBlock
);

    localparam integer DATA_OFFSET = TEXT_BYTES;
    localparam integer HEAP_OFFSET = TEXT_BYTES + DATA_BYTES;
    localparam integer MEM_BYTES   = TEXT_BYTES + DATA_BYTES + HEAP_BYTES;

    reg [7:0] rMainMem [0:MEM_BYTES-1];

    integer idx;
    integer byte_idx;
    integer instr_base;
    integer instr_pref_base;
    integer data_base;
    integer data_pref_base;
    integer write_base;

    function integer map_addr;
        input [31:0] addr;
        begin
            if (addr >= HEAP_BASE)
                map_addr = HEAP_OFFSET + (addr - HEAP_BASE);
            else if (addr >= DATA_BASE)
                map_addr = DATA_OFFSET + (addr - DATA_BASE);
            else
                map_addr = addr - TEXT_BASE;
        end
    endfunction

    initial begin
        for (idx = 0; idx < MEM_BYTES; idx = idx + 1)
            rMainMem[idx] = 8'h00;

        $readmemh("instr.txt", rMainMem, 0, TEXT_BYTES - 1);
        $readmemh("data.txt", rMainMem, DATA_OFFSET, DATA_OFFSET + DATA_BYTES - 1);
    end

    always @(*) begin
        oInstrReadBlock     = {(BLOCK_BYTES*8){1'b0}};
        oInstrPrefetchBlock = {(BLOCK_BYTES*8){1'b0}};
        oDataReadBlock      = {(BLOCK_BYTES*8){1'b0}};
        oDataPrefetchBlock  = {(BLOCK_BYTES*8){1'b0}};

        instr_base     = map_addr(iInstrReadAddr);
        instr_pref_base = map_addr(iInstrPrefetchAddr);
        data_base      = map_addr(iDataReadAddr);
        data_pref_base = map_addr(iDataPrefetchAddr);

        for (byte_idx = 0; byte_idx < BLOCK_BYTES; byte_idx = byte_idx + 1) begin
            if ((instr_base + byte_idx) >= 0 && (instr_base + byte_idx) < MEM_BYTES)
                oInstrReadBlock[(byte_idx * 8) +: 8] = rMainMem[instr_base + byte_idx];
            if ((instr_pref_base + byte_idx) >= 0 && (instr_pref_base + byte_idx) < MEM_BYTES)
                oInstrPrefetchBlock[(byte_idx * 8) +: 8] = rMainMem[instr_pref_base + byte_idx];
            if ((data_base + byte_idx) >= 0 && (data_base + byte_idx) < MEM_BYTES)
                oDataReadBlock[(byte_idx * 8) +: 8] = rMainMem[data_base + byte_idx];
            if ((data_pref_base + byte_idx) >= 0 && (data_pref_base + byte_idx) < MEM_BYTES)
                oDataPrefetchBlock[(byte_idx * 8) +: 8] = rMainMem[data_pref_base + byte_idx];
        end
    end

    always @(posedge iClk) begin
        if (iDataWriteBlockEn) begin
            write_base = map_addr(iDataWriteAddr);
            for (byte_idx = 0; byte_idx < BLOCK_BYTES; byte_idx = byte_idx + 1)
                if ((write_base + byte_idx) >= 0 && (write_base + byte_idx) < MEM_BYTES)
                    rMainMem[write_base + byte_idx] <= iDataWriteBlock[(byte_idx * 8) +: 8];
        end
    end

endmodule
