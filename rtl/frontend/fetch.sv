module fetch
import rv32i_types::*;
import tage_types::*;
(
    input logic clk,
    input logic rst,
    input logic stall,
    input logic flush,
    input logic ufp_resp,
    input logic [31:0] ufp_rdata,
    input logic [31:0] pc_redirect,
    input logic dequeue,
    input logic ufp_advance_ok,

    input logic        bp_predict_taken,
    input logic        btb_hit,
    input logic [31:0] btb_pred_target,

    output iq_package package_out,
    output logic [31:0] ufp_addr,
    output logic [3:0] ufp_rmask,
    output logic empty,
    output logic package_valid,
    input tage_meta_t bp_predict_meta,
    output logic [31:0] fetch_pc
);

iq_package package_in;
iq_package iq_package_out;

logic enqueue;
logic full;
logic iq_dequeue;
logic bypass_fire;

// 'dequeue' is the downstream-ready signal from the CPU.  Keep the physical
// IQ dequeue independent of the I-cache response.  When the IQ is empty and
// a response arrives while the downstream is ready, route package_in directly
// to package_out and do not enqueue it.
assign iq_dequeue  = dequeue && !empty;
assign bypass_fire = dequeue && empty && ufp_resp && !flush && !stall;

assign package_valid = !empty || bypass_fire;
assign package_out   = bypass_fire ? package_in : iq_package_out;

logic [31:0] pc;
assign fetch_pc = pc;
logic [31:0] pc_next;
instruction_queue iq(
    .clk        (clk),
    .rst        (rst),
    .flush      (flush),
    .enqueue    (enqueue),
    .dequeue    (iq_dequeue),
    .full       (full),
    .empty      (empty),
    .package_in (package_in),
    .package_out(iq_package_out)
);

always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 32'haaaaa000;
        end else begin
            pc <= pc_next;
        end
    end

    always_comb begin
        pc_next = pc;
        ufp_addr = pc;
        ufp_rmask = 4'b0000;
        enqueue = 1'b0;
        package_in = '0;

        if (flush) begin
            pc_next = pc_redirect;
            ufp_addr = pc_redirect;
            ufp_rmask = 4'b0000;
        end else if (!stall) begin
            // keep request asserted whenever fetch can keep going
            ufp_rmask = 4'b1111;

            if (ufp_resp && (!full || iq_dequeue)) begin
                // If bypass_fire is true, the response is consumed directly
                // by IF/ID and must not also be stored in the IQ.
                enqueue                 = !bypass_fire;
                package_in.inst         = ufp_rdata;
                package_in.pc           = pc;
                package_in.predicted_pc = (bp_predict_taken && btb_hit)
                                        ? btb_pred_target
                                        : pc + 32'd4;
                package_in.bp_meta      = bp_predict_meta;
                if (ufp_advance_ok) begin
                    // If predicting taken, jump to target instead of pc+4
                    if (bp_predict_taken && btb_hit) begin
                        ufp_addr = btb_pred_target;
                        pc_next  = btb_pred_target;
                    end else begin
                        ufp_addr = pc + 32'd4;
                        pc_next  = pc + 32'd4;
                    end
                end
            end
        end
    end

endmodule : fetch

