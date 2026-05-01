module CACHE #(
    parameter EVICT_POLICY = 0, // 0 = LRU, 1 = PLRU
    parameter NUM_WAYS = 1,
    parameter CACHE_SIZE = 4, // KB
    parameter BLOCK_SIZE = 64, // B
    parameter BLOCK_WIDTH = BLOCK_SIZE * 8
) (
    input i_clk,
    input i_rstn,
    // CPU interface inputs
    input i_read,
    input i_write,
    input [1:0] i_funct,
    input [31:0] i_addr,
    input [31:0] i_cpu_data,
    // MEM interface inputs
    input i_mem_ready,
    input i_mem_valid,
    input [BLOCK_WIDTH-1:0] i_mem_rd_data,

    // CPU interface outputs
    output reg o_hit,
    output reg o_miss,
    output reg [31:0] o_cpu_data,
    // MEM interface outputs
    output reg o_mem_rd,
    output reg o_mem_wr,
    output reg [31:0] o_mem_rd_addr,
    output reg [31:0] o_mem_wr_addr,
    output reg [BLOCK_WIDTH-1:0] o_mem_wr_data
);
    //region Cache parameters
    localparam NUM_BLOCKS = (CACHE_SIZE * 1024) / BLOCK_SIZE;
    localparam NUM_SETS = NUM_BLOCKS / NUM_WAYS;
    localparam NUM_LINES = NUM_SETS * NUM_WAYS;

    // Address bitfields
    localparam SET_IDX_BITS = $clog2(NUM_SETS);
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam SET_BITS = SET_IDX_BITS + OFFSET_BITS;
    localparam TAG_BITS = 32 - SET_IDX_BITS - OFFSET_BITS;
    localparam WAY_IDX = $clog2(NUM_WAYS);
    localparam WAY_IDX_MIN = (WAY_IDX <= 0) ? 1 : WAY_IDX;
    localparam CACHE_IDX = SET_IDX_BITS + WAY_IDX;

    // Function masks
    localparam BYTE_MASK = 32'hFF, HALF_MASK = 32'hFFFF, WORD_MASK = 32'hFFFFFFFF;

    // State definitions
    localparam CPU = 2'd0, WAIT = 2'd1, PF_WAIT = 2'd2;
    //endregion

    //W = wire
    //R = register

    //region Internal logic and variables
    // Variables
    integer i;
    genvar gi, gj;

    // State registers
    reg [1:0] r_state;
    reg r_wait;
    reg [1:0] r_rqst;

    // Cache storage
    reg [TAG_BITS-1:0]    r_cache_tags  [0:NUM_LINES-1];
    reg                   r_cache_valid [0:NUM_LINES-1];
    reg                   r_cache_dirty [0:NUM_LINES-1];
    reg [BLOCK_WIDTH-1:0] r_cache_data  [0:NUM_LINES-1];

    // Hit/miss
    wire                 w_access;
    wire                 w_hit, w_miss;
    wire [CACHE_IDX-1:0] w_hit_idx;

    // Address decode
    wire [TAG_BITS-1:0]     w_cpu_tag, w_mem_tag;
    wire [OFFSET_BITS-1:0]  w_cpu_offset, w_mem_offset;
    wire [CACHE_IDX-1:0]    w_cpu_idx;
    reg  [TAG_BITS-1:0]     r_mem_tag;

    // Read/write wires
    wire                   w_wr_dirty;
    wire [31:0]            w_rd_data;
    wire [BLOCK_WIDTH-1:0] w_wr_line;
    reg  [31:0]            r_cpu_data;
    
    // Mem request wires
    wire [31:0] w_rqst_addr, w_pf_rqst_addr;
    wire [31:0] w_mem_wr_addr;

    // Replacement policy
    wire                            w_update, w_op;
    wire [CACHE_IDX-1:0]            w_update_idx, w_evict_idx;
    wire [NUM_LINES-1:0]            w_cache_valid_flat;
    wire [NUM_SETS*WAY_IDX_MIN-1:0] w_evicts;
    reg  [CACHE_IDX-1:0]            r_evict_idx;
    //endregion

    //region Address decoding
    assign w_cpu_tag    = i_addr[31:SET_IDX_BITS+OFFSET_BITS];
    assign w_cpu_offset = i_addr[OFFSET_BITS-1:0];
    assign w_mem_tag    = o_mem_rd_addr[31:SET_IDX_BITS+OFFSET_BITS];
    assign w_mem_offset = o_mem_rd_addr[OFFSET_BITS-1:0];
    //endregion

    //update state using a ternary operator 
    //Setting update value equal to w_hit if the current state equals CPU state, otherwise w_update will get value of i_mem_valid. 
    //This means that we will only update the cache on a hit when we are in the CPU state, 
    //and we will update the cache on a memory valid signal when we are not in the CPU state (i.e., when we are waiting for a memory response). 
    assign w_update     = r_state == CPU ? w_hit : i_mem_valid;
    //Setting operation value to 1 if the register state is equal to prefetch wait state, if not,
    //the value of operation is 0. 
    //This means the operation is going to be active when we are waiting for the prefetch to go to cache.
    assign w_op         = (r_state == PF_WAIT) ? 1 : 0;
    //we set the update index value to the index of the hit if the state is equal to an active CPU,
    //else the updated index will qual the index of the evict index. 
    //So if we are in the CPU state, we want to update the cache line that we hit, if not in the CPU state,
    //we want to update the cache line that we are evicting from memory. 
    assign w_update_idx = r_state == CPU ? w_hit_idx :
                          r_evict_idx;



    //Combinational logic - Updates on immediateley (= (blocking)) - When we need to have the values ready for the next clock cycle.
    //Sequential logic - Updates on clock edge (= (non-blocking)) - When we want to update the values at the same time on the clock edge (like waiting something to be calculated then written)
    //When we read logic, we want it to be ready for the next clock cycle, so it is combinational logic.
    //when we write logic, we want it updated at the clock cycle, after all values are updated, so it is sequential. 

    //                      
    generate
        for (gi = 0; gi < NUM_LINES; gi = gi + 1) begin : gen_valid_flat
            assign w_cache_valid_flat[gi] = r_cache_valid[gi];
        end
            
       // Evication policy based on Ways/lines in a cache 
       //if NUM_WAYS == 1, the 1 way cache is Direct mapped with 1 line, so there is no eviction to make since it will always go to one spot.
       //if NUM_WAYS > 1, we need an eviction policy to determine which line to evict when we have a miss and need to bring in a new line.
        if (NUM_WAYS != 1) begin
            if (EVICT_POLICY == 0) begin
                LRU #(
                    .NUM_SETS(NUM_SETS),
                    .NUM_WAYS(NUM_WAYS)
                ) lru_inst (
                    .i_clk(i_clk),
                    .i_rstn(i_rstn),
                    .i_update(w_update),
                    .i_evict(r_wait),
                    .i_op(w_op),
                    .i_cache_valid(w_cache_valid_flat),
                    .i_cache_idx(w_update_idx),
                    .o_evict_way(w_evicts)
                );
            end
        end
    endgenerate

    // Grab evict index by set and way
    //Set and way combined into 1 index due to the way that verilog is only 1 dimensional instead of 
    //checking every way and every set, we have it as once variable cand can find what we need through indexing

    generate
        if(NUM_SETS > 1 && NUM_WAYS > 1) begin
            wire [SET_IDX_BITS-1:0] w_mem_set_idx;
            wire [NUM_SETS*WAY_IDX_MIN-1:0] w_evict_shifted;

    //region Replacement policy
    //Extract the set index from the memory address, bits sitting between offset and tag bits.
    //Shift w_evicts to find the eviction way for the specific set. w_evicts is a flat array holding the info for all sets,
    //so we shift by set_index * WAY_IDX_MIN to get the right sets position.
            assign w_mem_set_idx   = o_mem_rd_addr[SET_IDX_BITS+OFFSET_BITS-1:OFFSET_BITS];
            assign w_evict_shifted = w_evicts >> (w_mem_set_idx * WAY_IDX_MIN);
    //Combine the set index and way index into a full w_evict_idx using concatenation and splicing. 
    //The set index is the bits from the memory read address that correspond to the set index, and the way index is determined by the eviction policy (LRU or PLRU) and is given by w_evicts.
            assign w_evict_idx     = {w_mem_set_idx, w_evict_shifted[WAY_IDX_MIN-1:0]};

    //If sets is fully associative there is only 1, so the eviction output from LRU/PLRU will be it.
        end else if (NUM_SETS == 1) begin
            assign w_evict_idx = w_evicts;
    //Only one way per set (direct mapped) so we will always evict whatever is in the set that the address maps to. Set index will be the evict index.
        end else if (NUM_WAYS == 1) begin
            assign w_evict_idx = o_mem_rd_addr[SET_IDX_BITS+OFFSET_BITS-1:OFFSET_BITS];
        end
    endgenerate
    //endregion

    //region hit/miss logic
    wire [NUM_WAYS-1:0] w_hit_flat;
    wire [CACHE_IDX*NUM_WAYS-1:0] w_hit_idx_flat;

    //Access is consider reading or writing data 
    assign w_access = i_read || i_write;

    //combinational logic for hit/miss logic. 
    generate
        for(gi = 0; gi < NUM_WAYS; gi = gi + 1) begin : gen_hit_idx
            wire [CACHE_IDX-1:0] w_way_idx, w_way_hit_idx;
            wire w_way_hit;

        //If not fully associative 
       //extract the set index from the address, shift it by the way bits (WAY_IDX), then add gi to get the specific way in the set.
            if (NUM_SETS != 1) begin
                assign w_way_idx = ({{WAY_IDX{1'b0}}, i_addr[SET_BITS-1:OFFSET_BITS]} << WAY_IDX) + gi;
            end else begin
                assign w_way_idx = gi[CACHE_IDX-1:0];
            end

        //region hit/miss logic
        //Cache line will hold valid data
        //making sure the cache line is valid through matching tags. If this is true, output the way index, if false, it it 0.
            assign w_way_hit_idx = (r_cache_valid[w_way_idx] && 
            r_cache_tags[w_way_idx] == w_cpu_tag) ? w_way_idx : 0;

        //Way hit checks read or write AND if cache data is valid AND if the tags are valid. If all true, we have a hit for that way.
            assign w_way_hit     = (i_read || i_write) && r_cache_valid[w_way_idx] && (r_cache_tags[w_way_idx] == w_cpu_tag);

        //Stores the ways hit into slot gi of the flattened away.
            assign w_hit_flat[gi] = w_way_hit;
        //Packs each way's hit index into a specific slice of the array. Place it at the ending position.
            assign w_hit_idx_flat[gi*CACHE_IDX+CACHE_IDX-1 : gi*CACHE_IDX] = w_way_hit_idx;
        end

    //OR reduction to extract the final true hit. 
    //Puts each ways hit index into a bit array, then OR reduces it to get the final hit index. If any way hits, we have a hit for that set.
        for(gi = 0; gi < CACHE_IDX; gi = gi + 1) begin : gen_hit_idx_reduce
            wire [NUM_WAYS-1:0] w_bit_set;
            for(gj = 0; gj < NUM_WAYS; gj = gj + 1) begin : gen_hit_idx_reduce_inner
                assign w_bit_set[gj] = w_hit_idx_flat[gj*CACHE_IDX + gi];
            end
            assign w_hit_idx[gi] = |w_bit_set;
        end
    endgenerate

    //Putting the OR reduction to a single bit variable. 
    assign w_hit = |w_hit_flat;
    //If reading or writing and no hit, then it is a miss.
    assign w_miss = (i_read || i_write) && !w_hit;
    //endregion

    //region Cache read / write logic on hit
    wire [31:0] w_data_mask;
    wire [BLOCK_WIDTH-1:0] w_rd_line, w_wr_mask, w_rd_mask, w_update_line;
    wire [BLOCK_WIDTH-33:0] w_block_extend;

    // Function mask (word, half, byte)
    assign w_block_extend = {(BLOCK_WIDTH-32){1'b0}};
    assign w_data_mask =    (i_funct == 2'b00) ? BYTE_MASK :
                            (i_funct == 2'b01) ? HALF_MASK :
                            (i_funct == 2'b10) ? WORD_MASK : 0;
    
    // Read line from cache and read data to cpu
    //AND the block with the data mask of the same block size.
    //Then we OR the new masked data with the data from the cache line and shift it by the offset to get the right position in the block.
    assign w_rd_line = (w_hit)  ? r_cache_data[w_hit_idx]                                               : 0;
    assign w_rd_mask = (i_read && r_state != CPU) ? (i_mem_rd_data >> (w_cpu_offset * 8)) & {w_block_extend, w_data_mask} :
                       (w_hit)  ? (w_rd_line     >> (w_cpu_offset * 8)) & {w_block_extend, w_data_mask} : 0;
    assign w_rd_data = w_rd_mask[31:0];

    // Update line from cache (line to be updated) and write lane with updated data (with dirty bit)
    //Creating a byte mask for which bytes in the cache we want to write. 
    assign w_wr_mask     = (i_write) ? ({w_block_extend, w_data_mask} << (w_cpu_offset * 8)) : 0;
    //Places the new CPU data in the correct position by shifting it by the offset and extending it to the full cache line.
    assign w_update_line = (i_write)          ? ({w_block_extend, i_cpu_data} << (w_cpu_offset * 8)) & w_wr_mask : 0;
    //Merging updated cache line. Combines new CPU data with the untouched existing bytes.
    assign w_wr_line     = (i_write && r_state != CPU) ? w_update_line | (i_mem_rd_data & ~w_wr_mask) :
                           (i_write && w_hit) ? w_update_line | (w_rd_line & ~w_wr_mask)        : 0;
    //Sets the dirty bit whenever there is a write. 
    assign w_wr_dirty    = i_write;
    //endregion

    //region CPU miss and MEM request logic
    assign w_rqst_addr    = w_miss ? {i_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}} : 0;
    assign w_pf_rqst_addr = w_miss ? w_rqst_addr + BLOCK_SIZE                      : 0;
    //endregion

    //region MEM writeback logic on eviction
    //If set associative or direct mapped.
    //Reconstruct the address by:
    //concatenating the tag stored in the evicted line, the set index that was extracted from the evicted line, and the zero filled.
    generate
        if (NUM_SETS != 1) begin
            assign w_mem_wr_addr = {r_cache_tags[w_evict_idx], w_evict_idx[CACHE_IDX-1:WAY_IDX], {OFFSET_BITS{1'b0}}};
        end else begin
    //If fully associative it is reconstructed by the tag stored in the evicted line and the zero filled offsets. 
            assign w_mem_wr_addr = {r_cache_tags[w_evict_idx], {OFFSET_BITS{1'b0}}};
        end
    endgenerate
    //endregion

    //region Combinational output registers
    //o is the output register 
    //reports hit/miss to CPU and if it is a miss it triggers a memory read and we send the requested address to memory.
    
    always@(*) begin
        if (!i_rstn) begin
            o_hit         = 0;
            o_miss        = 0;
            o_cpu_data    = 0;
            o_mem_rd      = 0;
            o_mem_rd_addr = 0;
        end else begin
            if(r_state == CPU) begin
                o_hit = w_hit;
                o_miss = w_miss;
                o_mem_rd = w_miss;
                o_mem_rd_addr = w_miss ? w_rqst_addr : 0;

    //In wait stage we switch the memory read address to the prefetch address. This is to get ready to read the next line speculatively.
    //In PF_WAIT when memory read is done, we equal it to 0, and miss is resolved, so equal to 0.
            end else if (r_state == WAIT && i_mem_valid && !r_wait) begin
                o_mem_rd_addr = w_pf_rqst_addr;
            end else if (r_state == PF_WAIT && i_mem_valid && !r_wait) begin
                o_mem_rd = 0;
            end else if (r_rqst == 2'd2) begin
                o_miss = 0;   
            end

//Data is given to the CPU in both the CPU state and the WAIT state while reading. 
            if ((r_state == CPU || r_state == WAIT) && i_read) begin
                o_cpu_data = w_rd_data;
            end
        end
    end
    //endregion


    //region Sequential 2d vector reset
    //Resetting every cache line individually on reset. 
    //Verilog cannot do 2d arrays, so we do it one line at a time.
    generate
        for (gi = 0; gi < NUM_LINES; gi = gi + 1) begin : gen_cache_init
            always @(posedge i_clk or negedge i_rstn) begin
                if (!i_rstn) begin
                    r_cache_valid[gi] <= 0;
                    r_cache_dirty[gi] <= 0;
                    r_cache_tags[gi]  <= 0;
                    r_cache_data[gi]  <= 0;
                end
            end
        end
    endgenerate
    //endregion

    //region Sequential state machine and output registers
    always@(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state       <= CPU;
            o_mem_wr      <= 0;
            o_mem_wr_addr <= 0;
            o_mem_wr_data <= 0;
            r_rqst        <= 0;
        end else begin
            r_wait <= i_mem_valid;
            r_evict_idx   <= w_evict_idx;
            r_mem_tag      <= w_mem_tag;
            //Stalling CPU to handle memory response. Ensures that the memory is read correctly and determine the next course of action for cache
            //Such as when the CPU should read yet or wait for next clock cycle.


            //Stay in CPU unless there is a miss, then moves to WAIT
            //On a hit and write it updates the cache line and sets the dirty bit immediately. 
            if (r_state == CPU) begin
                r_state <= w_miss ? WAIT : CPU;
                r_cache_data[w_update_idx]  <= (w_hit && i_write) ? w_wr_line : r_cache_data[w_update_idx];
                r_cache_dirty[w_update_idx] <= (w_hit && i_write) ? w_wr_dirty : r_cache_dirty[w_update_idx];
                o_mem_wr <= 0;
                o_mem_wr_addr <= 0;
                o_mem_wr_data <= 0;
                r_rqst <= 0;

        //On a miss, evict the dirty line. If the line that is evicted is both valid and dirty, it should write back to memory before being thrown out.
            if (w_miss) begin
                    o_mem_wr      <= (r_cache_valid[w_evict_idx] && r_cache_dirty[w_evict_idx]) ? 1                         : 0;
                    o_mem_wr_addr <= (r_cache_valid[w_evict_idx] && r_cache_dirty[w_evict_idx]) ? w_mem_wr_addr             : 0;
                    o_mem_wr_data <= (r_cache_valid[w_evict_idx] && r_cache_dirty[w_evict_idx]) ? r_cache_data[w_evict_idx] : 0;
                end

            //In wait and prefetch wait, we fill the lines with new data from memory.
            //we mark the data as valid if it is.
            //Set dirty if it is a write miss, store the tag, and store the raw data on read and updated(merged) data on write.
            end else if (r_state == WAIT || r_state == PF_WAIT) begin
                r_state <= (i_mem_valid && r_state == WAIT) ? PF_WAIT :
                           (i_mem_valid && r_state == PF_WAIT) ? CPU : r_state;
                r_rqst <= r_rqst + {1'b0, i_mem_valid};
                o_mem_wr <= 0;
                o_mem_wr_addr <= 0;
                o_mem_wr_data <= 0;
                if(i_mem_valid) begin
                    if(r_state == WAIT) begin
                        o_mem_wr      <= (r_cache_valid[w_evict_idx] && r_cache_dirty[w_evict_idx]) ? 1                         : 0;
                        o_mem_wr_addr <= (r_cache_valid[w_evict_idx] && r_cache_dirty[w_evict_idx]) ? w_mem_wr_addr             : 0;
                        o_mem_wr_data <= (r_cache_valid[w_evict_idx] && r_cache_dirty[w_evict_idx]) ? r_cache_data[w_evict_idx] : 0;
                    end

                    r_cache_valid[w_update_idx] <= 1'b1;
                    r_cache_dirty[w_update_idx] <= (r_state == WAIT) ? i_write : 0;
                    r_cache_tags[w_update_idx]  <= r_mem_tag;
                    r_cache_data[w_update_idx]  <= i_read || r_state == PF_WAIT ? i_mem_rd_data : w_wr_line;
                end
            end
        end
    end
    //endregion
endmodule