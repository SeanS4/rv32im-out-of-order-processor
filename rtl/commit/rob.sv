module rob
import rv32i_types::*;
#(
    parameter length = ROB_DEPTH,
    parameter type width = rob_entry_t
)
(
    input   logic                       clk,
    input   logic                       rst,
    output  logic                       full,
    output  logic                       empty,
 
    input   logic                       flush,
    input   logic [$clog2(length)-1:0]  flush_rob_idx,
    input   logic [5:0]                 restore_map [32],
    output  logic [5:0]                 flush_map [32],
 
    input   logic                       enqueue,
    input   width                       rob_entry_in,
    output  width                       rob_entry_out,
 
    input   logic                       ready_write_ena,
    input   logic [$clog2(length)-1:0]  ready_write_idx,
    input   logic                       ready_write_data,
    input   commit_entry_t              commit_data,
 
    output  logic                       commit,
    output  logic [$clog2(length)-1:0]  tail_idx,
    output  logic [$clog2(length)-1:0]  head_idx,
    output logic [63:0] flush_live_mask
);
 
localparam ht_width = $clog2(length);
localparam [ht_width:0] length_c = length;
 
typedef logic [ht_width:0]   ptr_t;
typedef logic [ht_width-1:0] idx_t;
width data [length];
 
ptr_t head;
ptr_t tail;
 
logic dequeue;
 
assign tail_idx = tail[ht_width-1:0];
assign head_idx = head[ht_width-1:0];
 
assign empty = (head == tail);
 
assign full = (head[ht_width] != tail[ht_width]) &&
              (head[ht_width-1:0] == tail[ht_width-1:0]);
 
assign dequeue = !empty &&
                 (data[head[ht_width-1:0]].ready == 1'b1) &&
                 (data[head[ht_width-1:0]].valid == 1'b1);
 
assign commit = dequeue;
 
always_comb begin : flush_live_mask_comb
    integer              age_l;
    logic [ht_width-1:0] age_flush_l;
    logic [ht_width:0]   age_flush_full_l;
    logic [ht_width:0]   in_flight_l;
    logic [ht_width-1:0] scan_idx_l;
    integer              arch_l;
 
    flush_live_mask = '0;
 
    for (arch_l = 0; arch_l < 32; arch_l = arch_l + 1) begin
        flush_live_mask[restore_map[arch_l]] = 1'b1;
    end
 
    age_flush_l      = flush_rob_idx - head[ht_width-1:0];
    in_flight_l      = tail - head;
    age_flush_full_l = {1'b0, age_flush_l};
 
    for (age_l = 0; age_l < length; age_l++) begin
        scan_idx_l = head[ht_width-1:0] + idx_t'($unsigned(age_l));
 
        if ((age_flush_full_l < in_flight_l) &&
            (idx_t'($unsigned(age_l)) <= age_flush_l) &&
            data[scan_idx_l].valid &&
            (data[scan_idx_l].rd_arch != 5'd0)) begin
            flush_live_mask[data[scan_idx_l].new_rd_phys] = 1'b1;
        end
    end
 
    for (age_l = 0; age_l < length; age_l++) begin
        scan_idx_l = head[ht_width-1:0] + idx_t'($unsigned(age_l));
 
        if ((age_flush_full_l < in_flight_l) &&
            (idx_t'($unsigned(age_l)) <= age_flush_l) &&
            data[scan_idx_l].valid &&
            (data[scan_idx_l].old_rd_phys != 6'd0)) begin
            flush_live_mask[data[scan_idx_l].old_rd_phys] = 1'b1;
        end
    end
 
    flush_live_mask[0] = 1'b1;
end
 
always_comb begin
    if (empty) begin
        rob_entry_out = '0;
    end else begin
        rob_entry_out = data[head[ht_width-1:0]];
    end
end
 
always_comb begin : flush_map_comb
    integer              arch_c;
    integer              age_c;
    logic [ht_width-1:0] age_flush_c;
    logic [ht_width:0]   age_flush_full_c;
    logic [ht_width:0]   in_flight_c;
    logic [ht_width-1:0] scan_idx_c;
 
    for (arch_c = 0; arch_c < 32; arch_c++) begin
        flush_map[arch_c] = restore_map[arch_c];
    end
 
    age_flush_c      = flush_rob_idx - head[ht_width-1:0];
    in_flight_c      = tail - head;
    age_flush_full_c = {1'b0, age_flush_c};
 
    if (flush && (age_flush_full_c < in_flight_c)) begin
        for (age_c = 0; age_c < length; age_c++) begin
            scan_idx_c = head[ht_width-1:0] + idx_t'($unsigned(age_c));
 
            if ((idx_t'($unsigned(age_c)) <= age_flush_c) &&
                data[scan_idx_c].valid &&
                (data[scan_idx_c].rd_arch != 5'd0)) begin
                flush_map[data[scan_idx_c].rd_arch] = data[scan_idx_c].new_rd_phys;
            end
        end
    end
 
    flush_map[0] = 6'd0;
end
 
always_ff @(posedge clk) begin : rob_seq
    integer              i;
    ptr_t                new_head;
    ptr_t                new_tail;
    logic [ht_width-1:0] branch_dist;
    logic [ht_width-1:0] entry_dist;
    logic                keep_entry;
 
    if (rst) begin
        head <= '0;
        tail <= '0;
 
        for (i = 0; i < length; i++) begin
            data[i] <= '0;
        end
 
    end else if (flush) begin
        new_head = head;
 
        if (dequeue) begin
            new_head = head + 1'b1;
        end
 
        if (flush_rob_idx >= new_head[ht_width-1:0]) begin
            new_tail = {new_head[ht_width], flush_rob_idx} + 1'b1;
        end else begin
            new_tail = {~new_head[ht_width], flush_rob_idx} + 1'b1;
        end
 
        branch_dist = flush_rob_idx - new_head[ht_width-1:0];
 
        for (i = 0; i < length; i++) begin
            entry_dist = idx_t'($unsigned(i)) - new_head[ht_width-1:0];
 
            keep_entry = data[i].valid &&
                         (entry_dist <= branch_dist);
 
            if (keep_entry) begin
                if (ready_write_ena &&
                    (ready_write_idx == idx_t'($unsigned(i)))) begin
                    data[i].ready       <= ready_write_data;
                    data[i].commit_data <= commit_data;
                end
            end else begin
                data[i] <= '0;
            end
        end
 
        head <= new_head;
        tail <= new_tail;
 
    end else begin
        if (ready_write_ena) begin
            data[ready_write_idx].ready       <= ready_write_data;
            data[ready_write_idx].commit_data <= commit_data;
        end
 
        if (enqueue && !dequeue && !full) begin
            data[tail[ht_width-1:0]] <= rob_entry_in;
            tail <= tail + 1'b1;
 
        end else if (!enqueue && dequeue && !empty) begin
            data[head[ht_width-1:0]].valid <= 1'b0;
            head <= head + 1'b1;
 
        end else if (enqueue && dequeue && !empty) begin
            data[head[ht_width-1:0]].valid <= 1'b0;
            data[tail[ht_width-1:0]] <= rob_entry_in;
            tail <= tail + 1'b1;
            head <= head + 1'b1;
        end
    end
end
 
endmodule : rob

