module fsu_queue
import rv32i_types::*;
#(
    parameter length = 4,
    parameter type width = fsu_reg_t
)
(
    input   logic               clk,
    input   logic               rst,
    output  logic               full,
    output  logic               empty,
    input   logic               flush,
    input   logic               enqueue,
    input   logic               dequeue,
    output  width               package_out,
    input   width               package_in,
    input   rob_idx_t           flush_rob_idx,
    input   rob_idx_t           rob_head_idx
);

localparam ht_width = $clog2(length);
localparam logic [ht_width:0] LENGTH_EXT = length;

typedef logic [ht_width:0] ptr_t;

width data [length];

logic [ht_width:0] tail;
logic [ht_width:0] head;

assign full  = (head[ht_width] != tail[ht_width]) &&
               (head[ht_width-1:0] == tail[ht_width-1:0]);

assign empty = (head == tail);

always_comb begin
    if (empty) begin
        package_out = '0;
    end else begin
        package_out = data[head[ht_width-1:0]];
    end
end

always_ff @(posedge clk) begin : fsu_queue_seq
    integer unsigned    i;
    integer unsigned    step;
    logic [ht_width:0]  count_before;
    logic [ht_width:0]  kept_tail;
    logic [ht_width:0]  old_ptr;
    logic [ht_width-1:0] old_idx;

    rob_idx_t           flush_age;
    rob_idx_t           entry_age;
    rob_idx_t           package_age;

    logic               keep_slot;
    logic               keep_package;

    if (rst) begin
        tail <= '0;
        head <= '0;

        for (i = 0; i < $unsigned(length); i = i + 1) begin
            data[i] <= '0;
        end

    end else if (flush) begin
        count_before = tail - head;
        kept_tail    = '0;
        flush_age    = flush_rob_idx - rob_head_idx;

        for (i = 0; i < $unsigned(length); i = i + 1) begin
            data[i] <= '0;
        end

        for (step = 0; step < $unsigned(length); step = step + 1) begin
            if (step < count_before) begin
                old_ptr = head + ptr_t'(step);
                old_idx = old_ptr[ht_width-1:0];

                entry_age = data[old_idx].issue_exec_reg.rs_entry_out.rob_idx - rob_head_idx;

                keep_slot = !(dequeue && (step == 0)) &&
                            data[old_idx].issue_exec_reg.issue_valid &&
                            data[old_idx].issue_exec_reg.rs_entry_out.valid &&
                            !(entry_age > flush_age);

                if (keep_slot) begin
                    data[kept_tail[ht_width-1:0]] <= data[old_idx];
                    kept_tail = kept_tail + 1'b1;
                end
            end
        end

        package_age = package_in.issue_exec_reg.rs_entry_out.rob_idx - rob_head_idx;

        keep_package = enqueue &&
                       package_in.issue_exec_reg.issue_valid &&
                       package_in.issue_exec_reg.rs_entry_out.valid &&
                       !(package_age > flush_age) &&
                       (kept_tail < LENGTH_EXT);

        if (keep_package) begin
            data[kept_tail[ht_width-1:0]] <= package_in;
            kept_tail = kept_tail + 1'b1;
        end

        head <= '0;
        tail <= kept_tail;

    end else begin
        if (!dequeue && enqueue && !full) begin
            data[tail[ht_width-1:0]] <= package_in;
            tail <= tail + 1'b1;

        end else if (!enqueue && dequeue && !empty) begin
            head <= head + 1'b1;

        end else if (enqueue && dequeue && !empty) begin
            head <= head + 1'b1;
            data[tail[ht_width-1:0]] <= package_in;
            tail <= tail + 1'b1;
        end
    end
end

endmodule : fsu_queue