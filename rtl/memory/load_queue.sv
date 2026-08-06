module load_queue
import rv32i_types::*;
#(
    parameter DEPTH = 16
)
(
    input   logic               clk,
    input   logic               rst,
    input   logic               flush,

    input   logic               alloc,
    input   rob_idx_t           rob_idx,
    input   logic [2:0]         load_op,
    input   logic [5:0]         rd_phys,
    output  logic [3:0]         lq_idx,
    output  logic               full,

    input   logic               addr_valid,
    input   logic [3:0]         addr_lq_idx,
    input   logic [31:0]        addr,
    input   logic [3:0]         rmask,
    input   issue_exec_reg_t    addr_issue_exec_reg,

    output  logic               req_valid,
    output  logic [31:0]        req_addr,
    output  logic [3:0]         req_rmask,
    output  rob_idx_t           req_rob_idx,
    input   logic               req_granted,

    input   logic               resp,
    input   logic [31:0]        resp_data,
    output  logic               load_queue_pending_resp,

    output  logic               cdb_valid,
    output  logic [5:0]         cdb_rd_phys,
    output  rob_idx_t           cdb_rob_idx,
    output  logic [31:0]        cdb_data,
    output  logic [31:0]        cdb_addr,
    output  logic [3:0]         cdb_rmask,
    output  logic [31:0]        cdb_raw_rdata,
    output  issue_exec_reg_t    cdb_issue_exec_reg,

    input   rob_idx_t           flush_rob_idx,
    input   rob_idx_t           rob_head_idx,

    input   logic [4:0]         rd_arch_in
);

localparam IDX_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
localparam COUNT_W = $clog2(DEPTH + 1);

typedef logic [IDX_W-1:0]   idx_t;
typedef logic [COUNT_W-1:0] count_t;

localparam count_t DEPTH_COUNT = count_t'(DEPTH);

load_queue_entry_t lq [DEPTH];

// These names are retained so existing profiler/testbench hierarchy remains
// useful.  The queue is no longer physically circular:
//   head = oldest valid entry by ROB age
//   tail = first free physical slot
idx_t   head;
idx_t   tail;
idx_t   pending_idx;
count_t count;

logic empty;
logic alloc_found;
logic req_found;

idx_t alloc_idx;
idx_t req_idx;

rob_idx_t oldest_age;
rob_idx_t req_best_age;
rob_idx_t scan_age;

logic pending_stale;

function automatic logic rob_younger_than_flush(
    input rob_idx_t entry_rob_idx,
    input rob_idx_t branch_rob_idx,
    input rob_idx_t head_rob_idx
);
    rob_idx_t entry_age;
    rob_idx_t branch_age;
begin
    entry_age  = entry_rob_idx  - head_rob_idx;
    branch_age = branch_rob_idx - head_rob_idx;
    rob_younger_than_flush = (entry_age > branch_age);
end
endfunction

function automatic logic [31:0] format_load_data(
    input logic [31:0] raw_data,
    input logic [1:0]  address_low,
    input logic [2:0]  operation
);
    logic [7:0]  byte_value;
    logic [15:0] half_value;
begin
    unique case (address_low)
        2'b00:   byte_value = raw_data[7:0];
        2'b01:   byte_value = raw_data[15:8];
        2'b10:   byte_value = raw_data[23:16];
        default: byte_value = raw_data[31:24];
    endcase

    half_value = address_low[1]
               ? raw_data[31:16]
               : raw_data[15:0];

    unique case (operation)
        load_f3_lb:  format_load_data = {{24{byte_value[7]}}, byte_value};
        load_f3_lh:  format_load_data = {{16{half_value[15]}}, half_value};
        load_f3_lw:  format_load_data = raw_data;
        load_f3_lbu: format_load_data = {24'b0, byte_value};
        load_f3_lhu: format_load_data = {16'b0, half_value};
        default:     format_load_data = raw_data;
    endcase
end
endfunction

// -------------------------------------------------------------------------
// Occupancy, allocation-slot selection, oldest-entry observation, and
// oldest-address-ready request selection.
//
// A valid-bit allocation scheme permits a load response to free any slot.
// There is no requirement that responses complete in physical queue order.
// -------------------------------------------------------------------------
always_comb begin
    count        = '0;
    alloc_found  = 1'b0;
    alloc_idx    = '0;

    head         = '0;
    oldest_age   = '1;

    req_found    = 1'b0;
    req_idx      = '0;
    req_best_age = '1;
    scan_age     = '0;

    for (integer i = 0; i < DEPTH; i++) begin
        if (lq[idx_t'(i)].valid) begin
            count    = count + 1'b1;
            scan_age = lq[idx_t'(i)].rob_idx - rob_head_idx;

            // Keep an observational "head" equal to the oldest valid load.
            if (scan_age < oldest_age) begin
                oldest_age = scan_age;
                head       = idx_t'(i);
            end

            // Select the oldest load whose address is known and which has
            // not already been sent to the cache/forwarding path.
            if (!load_queue_pending_resp &&
                lq[idx_t'(i)].addr_ready &&
                !lq[idx_t'(i)].issued &&
                (!req_found || (scan_age < req_best_age))) begin

                req_found    = 1'b1;
                req_idx      = idx_t'(i);
                req_best_age = scan_age;
            end
        end else if (!alloc_found) begin
            alloc_found = 1'b1;
            alloc_idx   = idx_t'(i);
        end
    end

    // Retain "tail" as a first-free-slot observation for old testbenches.
    tail  = alloc_idx;
    empty = (count == '0);
    full  = (count == DEPTH_COUNT);

    lq_idx = '0;
    lq_idx[IDX_W-1:0] = alloc_idx;

    req_valid   = req_found && !flush;
    req_addr    = '0;
    req_rmask   = '0;
    req_rob_idx = '0;

    if (req_valid) begin
        req_addr    = lq[req_idx].addr;
        req_rmask   = lq[req_idx].rmask;
        req_rob_idx = lq[req_idx].rob_idx;
    end
end

// -------------------------------------------------------------------------
// Queue state.
//
// Only one cache/forwarding transaction may remain outstanding, matching the
// existing CPU interface.  pending_idx records the physical slot selected by
// the oldest-ready scan.
//
// On a flush, all younger non-pending entries are removed immediately.  A
// younger request already sent to memory cannot be cancelled, so its slot is
// retained with pending_stale=1 until the response arrives; that response is
// then discarded rather than broadcast on the CDB.
// -------------------------------------------------------------------------
always_ff @(posedge clk) begin : load_queue_seq
    logic pending_killed_now;
    idx_t widx;

    if (rst) begin
        pending_idx             <= '0;
        pending_stale           <= 1'b0;
        load_queue_pending_resp <= 1'b0;

        cdb_valid               <= 1'b0;
        cdb_rd_phys             <= '0;
        cdb_rob_idx             <= '0;
        cdb_data                <= '0;
        cdb_addr                <= '0;
        cdb_rmask               <= '0;
        cdb_raw_rdata           <= '0;
        cdb_issue_exec_reg      <= '0;

        for (integer i = 0; i < DEPTH; i++) begin
            lq[idx_t'(i)] <= '0;
        end

    end else begin
        // Completion outputs are pulses.
        cdb_valid          <= 1'b0;
        cdb_rd_phys        <= '0;
        cdb_rob_idx        <= '0;
        cdb_data           <= '0;
        cdb_addr           <= '0;
        cdb_rmask          <= '0;
        cdb_raw_rdata      <= '0;
        cdb_issue_exec_reg <= '0;

        if (flush) begin
            pending_killed_now = pending_stale;

            if (load_queue_pending_resp &&
                lq[pending_idx].valid &&
                rob_younger_than_flush(
                    lq[pending_idx].rob_idx,
                    flush_rob_idx,
                    rob_head_idx
                )) begin
                pending_killed_now = 1'b1;
            end

            // Remove every younger entry except an outstanding request,
            // which must remain until its external response returns.
            for (integer i = 0; i < DEPTH; i++) begin
                if (lq[idx_t'(i)].valid &&
                    !(load_queue_pending_resp &&
                      (idx_t'(i) == pending_idx)) &&
                    rob_younger_than_flush(
                        lq[idx_t'(i)].rob_idx,
                        flush_rob_idx,
                        rob_head_idx
                    )) begin
                    lq[idx_t'(i)] <= '0;
                end
            end

            if (load_queue_pending_resp) begin
                if (resp) begin
                    // Broadcast only when the outstanding load survives the
                    // flush.  A killed request is consumed silently.
                    if (!pending_killed_now &&
                        lq[pending_idx].valid) begin
                        cdb_valid          <= 1'b1;
                        cdb_rd_phys        <= lq[pending_idx].rd_phys;
                        cdb_rob_idx        <= lq[pending_idx].rob_idx;
                        cdb_data           <= format_load_data(
                            resp_data,
                            lq[pending_idx].addr[1:0],
                            lq[pending_idx].load_op
                        );
                        cdb_addr           <= lq[pending_idx].addr;
                        cdb_rmask          <= lq[pending_idx].rmask;
                        cdb_raw_rdata      <= resp_data;
                        cdb_issue_exec_reg <= lq[pending_idx].issue_exec_reg;
                    end

                    lq[pending_idx]         <= '0;
                    load_queue_pending_resp <= 1'b0;
                    pending_stale           <= 1'b0;
                end else begin
                    load_queue_pending_resp <= 1'b1;
                    pending_stale           <= pending_killed_now;
                end
            end else begin
                load_queue_pending_resp <= 1'b0;
                pending_stale           <= 1'b0;
            end

        end else begin
            // Allocate into the first invalid physical slot.
            if (alloc && !full && alloc_found) begin
                lq[alloc_idx]                <= '0;
                lq[alloc_idx].valid          <= 1'b1;
                lq[alloc_idx].addr_ready     <= 1'b0;
                lq[alloc_idx].issued         <= 1'b0;
                lq[alloc_idx].rd_phys        <= rd_phys;
                lq[alloc_idx].rd_arch        <= rd_arch_in;
                lq[alloc_idx].rob_idx        <= rob_idx;
                lq[alloc_idx].load_op        <= load_op;
                lq[alloc_idx].issue_exec_reg <= '0;
            end

            // Execute supplies the address and the instruction-associated
            // metadata using the physical slot allocated at rename.
            if (addr_valid) begin
                widx = idx_t'(addr_lq_idx[IDX_W-1:0]);

                if (lq[widx].valid) begin
                    lq[widx].addr           <= addr;
                    lq[widx].rmask          <= rmask;
                    lq[widx].addr_ready     <= 1'b1;
                    lq[widx].issue_exec_reg <= addr_issue_exec_reg;
                end
            end

            // Remember the exact slot chosen by the oldest-ready scan.
            if (req_granted && req_valid) begin
                lq[req_idx].issued          <= 1'b1;
                pending_idx                 <= req_idx;
                load_queue_pending_resp     <= 1'b1;
                pending_stale               <= 1'b0;
            end

            // A response may complete any physical slot because pending_idx
            // no longer has to equal the oldest allocated slot.
            if (resp && load_queue_pending_resp) begin
                if (!pending_stale &&
                    lq[pending_idx].valid) begin
                    cdb_valid          <= 1'b1;
                    cdb_rd_phys        <= lq[pending_idx].rd_phys;
                    cdb_rob_idx        <= lq[pending_idx].rob_idx;
                    cdb_data           <= format_load_data(
                        resp_data,
                        lq[pending_idx].addr[1:0],
                        lq[pending_idx].load_op
                    );
                    cdb_addr           <= lq[pending_idx].addr;
                    cdb_rmask          <= lq[pending_idx].rmask;
                    cdb_raw_rdata      <= resp_data;
                    cdb_issue_exec_reg <= lq[pending_idx].issue_exec_reg;
                end

                lq[pending_idx]         <= '0;
                load_queue_pending_resp <= 1'b0;
                pending_stale           <= 1'b0;
            end
        end
    end
end

endmodule : load_queue
