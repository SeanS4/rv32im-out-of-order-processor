module free_list
#(
    parameter NUM_PHYS_REGS = 64,
    parameter NUM_ARCH_REGS = 32
)
(
    input  logic clk,
    input  logic rst,
    input  logic flush,
    input  logic enqueue,
    input  logic dequeue,
    input  logic [$clog2(NUM_PHYS_REGS)-1:0] phys_to_free,
    output logic [$clog2(NUM_PHYS_REGS)-1:0] free_phys,
    output logic full,
    output logic empty,
    input  logic [63:0] live_mask
);

localparam PTR_W = $clog2(NUM_PHYS_REGS);

typedef logic [PTR_W-1:0] phys_idx_t;
typedef logic [PTR_W:0]   ptr_t;

phys_idx_t data [NUM_PHYS_REGS];
ptr_t head;
ptr_t tail;

assign full  = (head[PTR_W] != tail[PTR_W]) &&
               (head[PTR_W-1:0] == tail[PTR_W-1:0]);
assign empty = (head == tail);

always_comb begin
    if (empty) begin
        free_phys = '0;
    end else begin
        free_phys = data[head[PTR_W-1:0]];
    end
end

always_ff @(posedge clk) begin
    integer i;
    ptr_t   wr_ptr;

    if (rst) begin
        for (i = 0; i < NUM_PHYS_REGS; i++) begin
            data[phys_idx_t'(i)] <= phys_idx_t'(i);
        end
        head <= ptr_t'(NUM_PHYS_REGS - NUM_ARCH_REGS);
        tail <= ptr_t'(NUM_PHYS_REGS);

    end else if (flush) begin
        wr_ptr = '0;
        for (i = 0; i < NUM_PHYS_REGS; i++) begin
            if (!live_mask[i]) begin
                data[wr_ptr[PTR_W-1:0]] <= phys_idx_t'(i);
                wr_ptr = wr_ptr + 1'b1;
            end
        end
        head <= '0;
        tail <= wr_ptr;

    end else begin
        if (!dequeue && enqueue && !full) begin
            data[tail[PTR_W-1:0]] <= phys_to_free;
            tail <= tail + 1'b1;
        end else if (!enqueue && dequeue && !empty) begin
            head <= head + 1'b1;
        end else if (enqueue && dequeue && !empty) begin
            data[tail[PTR_W-1:0]] <= phys_to_free;
            tail <= tail + 1'b1;
            head <= head + 1'b1;
        end
    end
end

endmodule : free_list