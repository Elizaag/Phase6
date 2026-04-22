module CACHE #(
    parameter EVICT_POLICY = 0,    // 0 = LRU
    parameter NUM_WAYS     = 2,
    parameter CACHE_SIZE   = 4,    // KB
    parameter BLOCK_SIZE   = 4,   // bytes
    parameter BLOCK_WIDTH  = BLOCK_SIZE * 8
)(
    input                         i_clk,
    input                         i_rstn,

    input                         i_read,
    input                         i_write,
    input       [1:0]             i_funct,
    input       [31:0]            i_addr,
    input       [31:0]            i_cpu_data,

    input                         i_mem_ready,
    input                         i_mem_valid,
    input       [BLOCK_WIDTH-1:0] i_mem_rd_data,

    output reg                    o_hit,
    output reg                    o_miss,
    output reg  [31:0]            o_cpu_data,

    output reg                    o_mem_rd,
    output reg                    o_mem_wr,
    output reg  [31:0]            o_mem_rd_addr,
    output reg  [31:0]            o_mem_wr_addr,
    output reg  [BLOCK_WIDTH-1:0] o_mem_wr_data
);

    localparam BYTE_OFFSET_BITS = 2;
    localparam WORDS_PER_BLOCK  = BLOCK_SIZE / 4;
    localparam WORD_OFFSET_BITS = $clog2(WORDS_PER_BLOCK);

    localparam NUM_SETS   = (CACHE_SIZE * 1024) / (BLOCK_SIZE * NUM_WAYS);
    localparam INDEX_BITS = $clog2(NUM_SETS);
    localparam TAG_BITS   = 32 - INDEX_BITS - WORD_OFFSET_BITS - BYTE_OFFSET_BITS;

    localparam MISS_CYCLES = 100;
    localparam CNT_BITS    = $clog2(MISS_CYCLES + 1);

    localparam S_IDLE      = 3'd0;
    localparam S_WB        = 3'd1;
    localparam S_READ      = 3'd2;
    localparam S_REFILL    = 3'd3;
    localparam S_PF_READ   = 3'd4;
    localparam S_PF_REFILL = 3'd5;

    reg [2:0] state;

    // ============================================================
    // Cache arrays
    // ============================================================
    reg [TAG_BITS-1:0]    tag_array   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [BLOCK_WIDTH-1:0] data_array  [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                   valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                   dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                   lru         [0:NUM_SETS-1];

    // ============================================================
    // Latched demand request
    // ============================================================
    reg [31:0]                 req_addr;
    reg [31:0]                 req_wdata;
    reg                        req_write;
    reg [1:0]                  req_funct;
    reg [INDEX_BITS-1:0]       req_index;
    reg [TAG_BITS-1:0]         req_tag;
    reg [WORD_OFFSET_BITS-1:0] req_word;
    reg                        req_victim;

    // ============================================================
    // Latched prefetch request
    // ============================================================
    reg                        pf_pending;
    reg [31:0]                 pf_addr;
    reg [INDEX_BITS-1:0]       pf_index;
    reg [TAG_BITS-1:0]         pf_tag;
    reg                        pf_victim;

    // ============================================================
    // Shared miss / prefetch controls
    // ============================================================
    reg                        issued;
    reg [CNT_BITS-1:0]         wait_count;
    reg [BLOCK_WIDTH-1:0]      demand_buf;
    reg [BLOCK_WIDTH-1:0]      pf_buf;

    // ============================================================
    // Current CPU decode
    // ============================================================
    wire [INDEX_BITS-1:0] index =
        i_addr[BYTE_OFFSET_BITS + WORD_OFFSET_BITS + INDEX_BITS - 1 :
               BYTE_OFFSET_BITS + WORD_OFFSET_BITS];

    wire [TAG_BITS-1:0] tag =
        i_addr[31 : BYTE_OFFSET_BITS + WORD_OFFSET_BITS + INDEX_BITS];

    wire [WORD_OFFSET_BITS-1:0] word =
        i_addr[BYTE_OFFSET_BITS + WORD_OFFSET_BITS - 1 : BYTE_OFFSET_BITS];

    // Only allow hits during an actual access
    wire access_valid = i_read || i_write;

    wire hit0 = access_valid && valid_array[index][0] && (tag_array[index][0] == tag);
    wire hit1 = access_valid && valid_array[index][1] && (tag_array[index][1] == tag);
    wire hit  = hit0 | hit1;

    wire hit_way = hit0 ? 1'b0 : 1'b1;

    wire [31:0] read_data =
        hit0 ? data_array[index][0][word*32 +: 32] :
               data_array[index][1][word*32 +: 32];

    wire chosen_victim =
        (!valid_array[index][0]) ? 1'b0 :
        (!valid_array[index][1]) ? 1'b1 :
        lru[index];

    // Current access block base from i_addr
    wire [31:0] access_block_base = {
        i_addr[31 : BYTE_OFFSET_BITS + WORD_OFFSET_BITS],
        {WORD_OFFSET_BITS{1'b0}},
        {BYTE_OFFSET_BITS{1'b0}}
    };

    wire [31:0] access_next_block = access_block_base + BLOCK_SIZE;

    // Latched demand block base from req_addr
    wire [31:0] req_block_base = {
        req_addr[31 : BYTE_OFFSET_BITS + WORD_OFFSET_BITS],
        {WORD_OFFSET_BITS{1'b0}},
        {BYTE_OFFSET_BITS{1'b0}}
    };

    wire [31:0] req_next_block = req_block_base + BLOCK_SIZE;

    wire pf_line_present =
        (valid_array[pf_index][0] && (tag_array[pf_index][0] == pf_tag)) ||
        (valid_array[pf_index][1] && (tag_array[pf_index][1] == pf_tag));

    wire pf_chosen_victim =
        (!valid_array[pf_index][0]) ? 1'b0 :
        (!valid_array[pf_index][1]) ? 1'b1 :
        lru[pf_index];

    wire [31:0] pf_block_base = {
        pf_addr[31 : BYTE_OFFSET_BITS + WORD_OFFSET_BITS],
        {WORD_OFFSET_BITS{1'b0}},
        {BYTE_OFFSET_BITS{1'b0}}
    };

    integer s, w;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                lru[s] <= 1'b0;
                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    valid_array[s][w] <= 1'b0;
                    dirty_array[s][w] <= 1'b0;
                    tag_array[s][w]   <= {TAG_BITS{1'b0}};
                    data_array[s][w]  <= {BLOCK_WIDTH{1'b0}};
                end
            end

            state      <= S_IDLE;

            req_addr   <= 32'b0;
            req_wdata  <= 32'b0;
            req_write  <= 1'b0;
            req_funct  <= 2'b0;
            req_index  <= {INDEX_BITS{1'b0}};
            req_tag    <= {TAG_BITS{1'b0}};
            req_word   <= {WORD_OFFSET_BITS{1'b0}};
            req_victim <= 1'b0;

            pf_pending <= 1'b0;
            pf_addr    <= 32'b0;
            pf_index   <= {INDEX_BITS{1'b0}};
            pf_tag     <= {TAG_BITS{1'b0}};
            pf_victim  <= 1'b0;

            issued     <= 1'b0;
            wait_count <= {CNT_BITS{1'b0}};
            demand_buf <= {BLOCK_WIDTH{1'b0}};
            pf_buf     <= {BLOCK_WIDTH{1'b0}};

            o_hit        <= 1'b0;
            o_miss       <= 1'b0;
            o_cpu_data   <= 32'b0;

            o_mem_rd      <= 1'b0;
            o_mem_wr      <= 1'b0;
            o_mem_rd_addr <= 32'b0;
            o_mem_wr_addr <= 32'b0;
            o_mem_wr_data <= {BLOCK_WIDTH{1'b0}};
        end
        else begin
            o_hit  <= 1'b0;
            o_miss <= 1'b0;

            case (state)

                // ====================================================
                // IDLE
                // ====================================================
                S_IDLE: begin
                    o_mem_rd <= 1'b0;
                    o_mem_wr <= 1'b0;

                    if (i_read || i_write) begin
                        if (hit) begin
                            o_hit      <= 1'b1;
                            o_cpu_data <= i_write ? i_cpu_data : read_data;

                            if (i_write) begin
                                data_array[index][hit_way][word*32 +: 32] <= i_cpu_data;
                                dirty_array[index][hit_way]                <= 1'b1;
                            end

                            lru[index] <= ~hit_way;

                            if (i_read) begin
                                pf_addr    <= access_next_block;
                                pf_index   <= access_next_block[BYTE_OFFSET_BITS + WORD_OFFSET_BITS + INDEX_BITS - 1 :
                                                               BYTE_OFFSET_BITS + WORD_OFFSET_BITS];
                                pf_tag     <= access_next_block[31 : BYTE_OFFSET_BITS + WORD_OFFSET_BITS + INDEX_BITS];
                                pf_pending <= 1'b1;
                            end
                        end
                        else begin
                            req_addr   <= i_addr;
                            req_wdata  <= i_cpu_data;
                            req_write  <= i_write;
                            req_funct  <= i_funct;
                            req_index  <= index;
                            req_tag    <= tag;
                            req_word   <= word;
                            req_victim <= chosen_victim;

                            issued     <= 1'b0;
                            wait_count <= {CNT_BITS{1'b0}};

                            o_miss <= 1'b1;

                            if (valid_array[index][chosen_victim] &&
                                dirty_array[index][chosen_victim])
                                state <= S_WB;
                            else
                                state <= S_READ;
                        end
                    end
                    else if (pf_pending) begin
                        if (pf_line_present) begin
                            pf_pending <= 1'b0;
                        end
                        else if (valid_array[pf_index][pf_chosen_victim] &&
                                 dirty_array[pf_index][pf_chosen_victim]) begin
                            pf_pending <= 1'b0;
                        end
                        else begin
                            pf_victim  <= pf_chosen_victim;
                            issued     <= 1'b0;
                            wait_count <= {CNT_BITS{1'b0}};
                            state      <= S_PF_READ;
                        end
                    end
                end

                // ====================================================
                // Demand writeback
                // ====================================================
                S_WB: begin
                    o_mem_rd <= 1'b0;

                    if (!issued) begin
                        o_mem_wr <= 1'b1;
                        o_mem_wr_addr <= {
                            tag_array[req_index][req_victim],
                            req_index,
                            {WORD_OFFSET_BITS{1'b0}},
                            {BYTE_OFFSET_BITS{1'b0}}
                        };
                        o_mem_wr_data <= data_array[req_index][req_victim];

                        if (i_mem_ready) begin
                            issued   <= 1'b1;
                            o_mem_wr <= 1'b0;
                        end
                    end
                    else begin
                        o_mem_wr <= 1'b0;

                        if (wait_count == MISS_CYCLES-1) begin
                            dirty_array[req_index][req_victim] <= 1'b0;
                            issued     <= 1'b0;
                            wait_count <= {CNT_BITS{1'b0}};
                            state      <= S_READ;
                        end
                        else begin
                            wait_count <= wait_count + 1'b1;
                        end
                    end
                end

                // ====================================================
                // Demand read
                // ====================================================
                S_READ: begin
                    o_mem_wr <= 1'b0;

                    if (!issued) begin
                        o_mem_rd      <= 1'b1;
                        o_mem_rd_addr <= req_block_base;

                        if (i_mem_ready) begin
                            issued   <= 1'b1;
                            o_mem_rd <= 1'b0;
                        end
                    end
                    else begin
                        o_mem_rd <= 1'b0;

                        if (i_mem_valid)
                            demand_buf <= i_mem_rd_data;

                        if (wait_count == MISS_CYCLES-1) begin
                            issued     <= 1'b0;
                            wait_count <= {CNT_BITS{1'b0}};
                            state      <= S_REFILL;
                        end
                        else begin
                            wait_count <= wait_count + 1'b1;
                        end
                    end
                end

                // ====================================================
                // Demand refill
                // ====================================================
                S_REFILL: begin
                    o_mem_rd <= 1'b0;
                    o_mem_wr <= 1'b0;

                    tag_array[req_index][req_victim]   <= req_tag;
                    valid_array[req_index][req_victim] <= 1'b1;
                    data_array[req_index][req_victim]  <= demand_buf;
                    dirty_array[req_index][req_victim] <= req_write;

                    if (req_write)
                        data_array[req_index][req_victim][req_word*32 +: 32] <= req_wdata;

                    /*o_cpu_data <= req_write ? req_wdata :
                                  demand_buf[req_word*32 +: 32];*/
                    o_cpu_data <= demand_buf[req_word*32 +: 32];

                    o_hit <= 1'b1;

                    lru[req_index] <= ~req_victim;

                    if (!req_write) begin
                        pf_addr    <= req_next_block;
                        pf_index   <= req_next_block[BYTE_OFFSET_BITS + WORD_OFFSET_BITS + INDEX_BITS - 1 :
                                                     BYTE_OFFSET_BITS + WORD_OFFSET_BITS];
                        pf_tag     <= req_next_block[31 : BYTE_OFFSET_BITS + WORD_OFFSET_BITS + INDEX_BITS];
                        pf_pending <= 1'b1;
                    end

                    state <= S_IDLE;
                end

                // ====================================================
                // Prefetch read
                // ====================================================
                S_PF_READ: begin
                    o_mem_wr <= 1'b0;

                    if (!issued) begin
                        o_mem_rd      <= 1'b1;
                        o_mem_rd_addr <= pf_block_base;

                        if (i_mem_ready) begin
                            issued   <= 1'b1;
                            o_mem_rd <= 1'b0;
                        end
                    end
                    else begin
                        o_mem_rd <= 1'b0;

                        if (i_mem_valid)
                            pf_buf <= i_mem_rd_data;

                        if (wait_count == MISS_CYCLES-1) begin
                            issued     <= 1'b0;
                            wait_count <= {CNT_BITS{1'b0}};
                            state      <= S_PF_REFILL;
                        end
                        else begin
                            wait_count <= wait_count + 1'b1;
                        end
                    end
                end

                // ====================================================
                // Prefetch refill
                // ====================================================
                S_PF_REFILL: begin
                    o_mem_rd <= 1'b0;
                    o_mem_wr <= 1'b0;

                    tag_array[pf_index][pf_victim]   <= pf_tag;
                    valid_array[pf_index][pf_victim] <= 1'b1;
                    data_array[pf_index][pf_victim]  <= pf_buf;
                    dirty_array[pf_index][pf_victim] <= 1'b0;

                    pf_pending <= 1'b0;
                    state      <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule