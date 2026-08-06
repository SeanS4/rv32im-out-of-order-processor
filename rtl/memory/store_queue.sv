module store_queue
import rv32i_types::*;
#(
    parameter DEPTH = 8
)
(
    input   logic               clk,
    input   logic               rst,
    input   logic               flush,

    input   logic               alloc,
    input   rob_idx_t           rob_idx,
    input   logic [2:0]         store_op,
    output  logic [3:0]         sq_idx,
    output  logic               full,

    input   logic               addr_valid,
    input   logic [3:0]         addr_sq_idx,
    input   logic [31:0]        addr,
    input   logic [3:0]         wmask,

    input   logic               data_valid,
    input   logic [3:0]         data_sq_idx,
    input   logic [31:0]        data,

    input   logic               commit,
    input   logic [3:0]         commit_sq_idx,

    output  logic               req_valid,
    output  logic [31:0]        req_addr,
    output  logic [31:0]        req_data,
    output  logic [3:0]         req_wmask,
    input   logic               req_granted,
    input   logic               resp,
    output  logic               store_queue_pending_resp,
    output  logic               store_commited_empty,

    input   logic [3:0]         meta_sq_idx,
    output  logic [31:0]        meta_addr,
    output  logic [31:0]        meta_data,
    output  logic [3:0]         meta_wmask,

    input   logic [31:0]        fwd_load_addr,
    input   logic [3:0]         fwd_load_rmask,
    input   rob_idx_t           fwd_load_rob_idx,
    input   rob_idx_t           flush_rob_idx,
    input   rob_idx_t           rob_head_idx,

    output  logic [31:0]        fwd_data,
    output  logic               fwd_full,
    output  logic               fwd_conflict
);

localparam IDX_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
localparam COUNT_W = $clog2(DEPTH + 1);

typedef logic [IDX_W-1:0]   idx_t;
typedef logic [COUNT_W-1:0] count_t;

localparam count_t DEPTH_COUNT = count_t'(DEPTH);

store_queue_entry_t sq [DEPTH];

idx_t   head;
idx_t   tail;
idx_t   pending_idx;
count_t count;
logic   empty;

assign empty = (count == '0);
assign full  = (count == DEPTH_COUNT);

logic [3:0] covered;
idx_t       scan_idx;
rob_idx_t   fwd_store_age;
rob_idx_t   fwd_load_age;
logic       fwd_store_older;

always_comb begin
    fwd_data        = '0;
    covered         = '0;
    scan_idx        = '0;
    fwd_store_age   = '0;
    fwd_load_age    = fwd_load_rob_idx - rob_head_idx;
    fwd_store_older = 1'b0;
    fwd_full        = 1'b0;
    fwd_conflict    = 1'b0;

    for (integer i = 0; i < DEPTH; i++) begin
        scan_idx        = idx_t'((integer'(head) + i) % DEPTH);
        fwd_store_age   = sq[scan_idx].rob_idx - rob_head_idx;
        fwd_store_older = sq[scan_idx].committed || (fwd_store_age < fwd_load_age);

        if (sq[scan_idx].valid && fwd_store_older) begin
            if (!sq[scan_idx].addr_ready) begin
                fwd_conflict = 1'b1;
            end else if ((sq[scan_idx].addr[31:2] == fwd_load_addr[31:2]) &&
                         ((sq[scan_idx].wmask & fwd_load_rmask) != 4'b0000)) begin
                if (!sq[scan_idx].data_ready) begin
                    fwd_conflict = 1'b1;
                end else begin
                    for (integer b = 0; b < 4; b++) begin
                        if (sq[scan_idx].wmask[b] && fwd_load_rmask[b]) begin
                            fwd_data[b*8 +: 8] = sq[scan_idx].data[b*8 +: 8];
                            covered[b] = 1'b1;
                        end
                    end
                end
            end
        end
    end

    if (((covered & fwd_load_rmask) == fwd_load_rmask) &&
        (fwd_load_rmask != 4'b0000) &&
        !fwd_conflict) begin
        fwd_full = 1'b1;
    end

    if (((covered & fwd_load_rmask) != 4'b0000) &&
        ((covered & fwd_load_rmask) != fwd_load_rmask)) begin
        fwd_conflict = 1'b1;
        fwd_full     = 1'b0;
    end
end

always_comb begin
    store_commited_empty = 1'b1;

    for (integer i = 0; i < DEPTH; i++) begin
        if (sq[idx_t'(i)].valid && sq[idx_t'(i)].committed) begin
            store_commited_empty = 1'b0;
        end
    end
end

always_comb begin
    idx_t meta_idx;

    sq_idx = '0;
    sq_idx[IDX_W-1:0] = tail;

    req_valid = 1'b0;
    req_addr  = '0;
    req_data  = '0;
    req_wmask = '0;

    if (!empty &&
        !store_queue_pending_resp &&
        sq[head].valid &&
        sq[head].addr_ready &&
        sq[head].data_ready &&
        sq[head].committed &&
        !sq[head].issued) begin

        req_valid = 1'b1;
        req_addr  = sq[head].addr;
        req_data  = sq[head].data;
        req_wmask = sq[head].wmask;
    end

    meta_addr  = '0;
    meta_data  = '0;
    meta_wmask = '0;

    meta_idx = idx_t'(meta_sq_idx[IDX_W-1:0]);
    if (sq[meta_idx].valid) begin
        meta_addr  = sq[meta_idx].addr;
        meta_data  = sq[meta_idx].data;
        meta_wmask = sq[meta_idx].wmask;
    end
end

logic   do_alloc;
logic   do_pop;
idx_t   aidx;
idx_t   didx;
idx_t   cidx;
integer reset_i;

rob_idx_t   age_flush_sq;
rob_idx_t   age_entry_sq;
idx_t       new_head_sq;
idx_t       new_tail_sq;
count_t     new_count_sq;
count_t     count_after_pop_sq;
idx_t       sidx;
logic       found_new_head;
logic       flush_pop_sq;

always_ff @(posedge clk) begin
    if (rst) begin
        head                     <= '0;
        tail                     <= '0;
        count                    <= '0;
        pending_idx              <= '0;
        store_queue_pending_resp <= 1'b0;

        for (reset_i = 0; reset_i < DEPTH; reset_i = reset_i + 1) begin
            sq[idx_t'($unsigned(reset_i))] <= '0;
        end

    end else if (flush) begin
        age_flush_sq       = flush_rob_idx - rob_head_idx;
        new_head_sq        = head;
        new_tail_sq        = head;
        new_count_sq       = '0;
        count_after_pop_sq = '0;
        found_new_head     = 1'b0;
        flush_pop_sq       = resp && store_queue_pending_resp;

        for (integer i = 0; i < DEPTH; i++) begin
            sidx = idx_t'((integer'(head) + i) % DEPTH);

            if (sq[sidx].valid) begin
                age_entry_sq = sq[sidx].rob_idx - rob_head_idx;

                if (age_entry_sq > age_flush_sq && !sq[sidx].committed &&
                    !(commit && (idx_t'(commit_sq_idx[IDX_W-1:0]) == sidx))) begin
                    sq[sidx] <= '0;
                end else begin
                    new_tail_sq  = idx_t'((integer'(sidx) + 1) % DEPTH);
                    new_count_sq = new_count_sq + 1'b1;

                    if (!found_new_head && !(flush_pop_sq && (sidx == pending_idx))) begin
                        new_head_sq    = sidx;
                        found_new_head = 1'b1;
                    end

                    if (commit && (idx_t'(commit_sq_idx[IDX_W-1:0]) == sidx)) begin
                        sq[sidx].committed <= 1'b1;
                    end
                end
            end
        end

        if (flush_pop_sq) begin
            sq[pending_idx]          <= '0;
            store_queue_pending_resp <= 1'b0;

            if (new_count_sq != '0) begin
                count_after_pop_sq = new_count_sq - 1'b1;
            end else begin
                count_after_pop_sq = '0;
            end

            head  <= found_new_head ? new_head_sq : new_tail_sq;
            tail  <= new_tail_sq;
            count <= count_after_pop_sq;
        end else begin
            store_queue_pending_resp <= store_queue_pending_resp;
            head  <= found_new_head ? new_head_sq : new_tail_sq;
            tail  <= new_tail_sq;
            count <= new_count_sq;
        end

    end else begin
        do_alloc = alloc && !full;
        do_pop   = resp && store_queue_pending_resp;

        if (do_alloc) begin
            sq[tail]            <= '0;
            sq[tail].valid      <= 1'b1;
            sq[tail].addr_ready <= 1'b0;
            sq[tail].data_ready <= 1'b0;
            sq[tail].committed  <= 1'b0;
            sq[tail].issued     <= 1'b0;
            sq[tail].rob_idx    <= rob_idx;
            sq[tail].store_op   <= store_op;
            tail                <= tail + 1'b1;
        end

        if (addr_valid) begin
            aidx = idx_t'(addr_sq_idx[IDX_W-1:0]);

            if (sq[aidx].valid) begin
                sq[aidx].addr       <= addr;
                sq[aidx].wmask      <= wmask;
                sq[aidx].addr_ready <= 1'b1;
            end
        end

        if (data_valid) begin
            didx = idx_t'(data_sq_idx[IDX_W-1:0]);

            if (sq[didx].valid) begin
                sq[didx].data       <= data;
                sq[didx].data_ready <= 1'b1;
            end
        end

        if (commit) begin
            cidx = idx_t'(commit_sq_idx[IDX_W-1:0]);

            if (sq[cidx].valid) begin
                sq[cidx].committed <= 1'b1;
            end
        end

        if (req_granted && req_valid) begin
            sq[head].issued          <= 1'b1;
            store_queue_pending_resp <= 1'b1;
            pending_idx              <= head;
        end

        if (do_pop) begin
            sq[pending_idx]          <= '0;
            store_queue_pending_resp <= 1'b0;
            head                     <= head + 1'b1;
        end

        unique case ({do_alloc, do_pop})
            2'b10:   count <= count + 1'b1;
            2'b01:   count <= count - 1'b1;
            default: count <= count;
        endcase
    end
end

endmodule : store_queue