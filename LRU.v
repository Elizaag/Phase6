module LRU #(
    parameter NUM_SETS = 4,
    parameter NUM_WAYS = 4,
    parameter WAY_IDX = $clog2(NUM_WAYS),
    parameter NUM_LINES = NUM_SETS * NUM_WAYS,
    parameter SET_IDX_BITS = $clog2(NUM_SETS),
    parameter CACHE_IDX = SET_IDX_BITS + WAY_IDX
) (
    input i_clk,
    input i_rstn,
    input i_update,
    input i_evict,
    input i_op,
    input [NUM_LINES-1:0] i_cache_valid,
    input [CACHE_IDX-1:0] i_cache_idx,
    output [NUM_SETS*WAY_IDX-1:0] o_evict_way
);

//Counter per cache line to keep track of LRU order.
    localparam SET_IDX_BITS_MIN = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1;
    // LRU order: [0] = MRU, [NUM_WAYS-1] = LRU, per set, flattened
    reg [WAY_IDX-1:0] r_lru_order [0:NUM_LINES-1];
    integer i, j;

    reg [WAY_IDX-1:0] r_evict_arr [0:NUM_SETS-1];

    wire [SET_IDX_BITS_MIN-1:0] w_set_idx;
    reg  [SET_IDX_BITS_MIN-1:0] r_set_idx;

    wire w_invalid;
    generate
        if(NUM_SETS > 1) begin
            wire [NUM_WAYS-1:0] w_cache_set_valid;
            wire [NUM_LINES-1:0] w_cache_valid_flat;
//Extracts which set is being accessed from the cache index.
            assign w_set_idx = i_cache_idx[CACHE_IDX-1:WAY_IDX];
            assign w_cache_valid_flat = i_cache_valid >> (w_set_idx * NUM_WAYS);
            //AND reduction; true if all ways are set to valid.
            assign w_cache_set_valid = w_cache_valid_flat[NUM_WAYS-1:0];
            //true if any way in the set is still invalid, no eviction since empty, ust fill the empty spot
            assign w_invalid = ~(&w_cache_set_valid);
        end else begin
            assign w_set_idx = 0;
        end
    endgenerate
    
    wire [WAY_IDX-1:0] way_idx;

// Reset or initialize LRU order for all sets
    //Scans all the ways to look for invalid ways and LRU way. 
    //Invalid wasy are more preferred since they are empty and we don't have to evict anything.
    always @(posedge i_clk or negedge i_rstn) begin
        r_set_idx <= w_set_idx;
        if (!i_rstn) begin
            for (j = 0; j < NUM_LINES; j = j + 1) begin
                r_lru_order[j] <= 0;
            end
        end else if (i_update) begin
            if(!i_op) begin
                integer base;
                base = w_set_idx * NUM_WAYS;
                if (i_op == 1'b0) begin
                    for (i = 0; i < NUM_WAYS; i = i + 1) begin
                        if (r_lru_order[base + i] <= r_lru_order[i_cache_idx])
                            r_lru_order[base + i] <= (r_lru_order[base + i] == {WAY_IDX{1'b1}}) ? r_lru_order[base + i] : r_lru_order[base + i] + 1;
                    end

                    r_lru_order[i_cache_idx] <= 0;
                end
            end else begin
                r_lru_order[i_cache_idx] <= {WAY_IDX{1'b1}};
            end
        end
    end


    //
    integer base_evict;
    integer idx_evict;
    reg [WAY_IDX-1:0] r_evict_way, r_invalid_way;
    integer found_invalid, found_evict;
    always@(*) begin
        if(1'b1) begin
            base_evict = r_set_idx * NUM_WAYS;
            r_evict_way = 0;
            r_invalid_way = 0;
            found_invalid = 0;
            found_evict = 0;

            for(i = 0; i < NUM_WAYS; i = i + 1) begin
                idx_evict = base_evict + i;
                if(!i_cache_valid[idx_evict] && !(found_invalid[0])) begin
                    r_invalid_way = idx_evict[WAY_IDX-1:0];
                    found_invalid = 1;
                end
                if(r_lru_order[idx_evict] >= r_evict_way && !(found_evict[0])) begin
                    if(r_lru_order[idx_evict] == {WAY_IDX{1'b1}}) begin
                        found_evict = 1;
                    end
                    r_evict_way = idx_evict[WAY_IDX-1:0];
                end
            end
        end
    end

    always @(*) begin
        if (!i_rstn) begin
            for (j = 0; j < NUM_SETS; j = j + 1) begin
                r_evict_arr[j] = 0;
            end
        end else if (1'b1) begin
            r_evict_arr[r_set_idx] = (found_invalid == 1) ? r_invalid_way : r_evict_way;
        end
    end
//Packs the eviction way into 1 output - more concatenation. 
    genvar gset;
    generate
        for (gset = 0; gset < NUM_SETS; gset = gset + 1) begin : gen_evict_way
            assign o_evict_way[(gset+1)*WAY_IDX-1 : gset*WAY_IDX] = r_evict_arr[gset];
        end
    endgenerate

endmodule