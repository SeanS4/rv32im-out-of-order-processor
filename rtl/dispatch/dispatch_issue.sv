module dispatch_issue
import rv32i_types::*;
(
    input  rs_entry rs_entry_in,
    input  logic clk,
    input  logic rst,
    input  logic flush,
    input  logic cdb_valid,
    input  logic [5:0] rd_s, // source physical register being broadcast as ready
    input  logic issue_slot_ready,
    input  logic alu_can_issue,
    input  logic mul_can_issue,
    input  logic div_can_issue,
    input  logic lq_cdb_valid,
    input  logic [63:0] prf_ready,

    output logic    issue_fire,
    output rs_entry rs_entry_out,
    output logic    rs_full,
    output logic    issue_valid,
    output logic    no_pending_stores_out,
    output logic    rs_empty,

    input  rob_idx_t flush_rob_idx,
    input  rob_idx_t rob_head_idx
);

rs u_rs(
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .cdb_valid(cdb_valid),
    .lq_cdb_valid(lq_cdb_valid),
    .issue_valid(issue_valid),
    .full(rs_full),
    .empty(rs_empty),
    .rs_entry_out(rs_entry_out),
    .rs_entry_in(rs_entry_in),
    .rd_s(rd_s),
    .no_pending_stores_out(no_pending_stores_out),
    .issue_slot_ready(issue_slot_ready),
    .alu_can_issue(alu_can_issue),
    .mul_can_issue(mul_can_issue),
    .div_can_issue(div_can_issue),
    .issue_fire(issue_fire),
    .flush_rob_idx(flush_rob_idx),
    .rob_head_idx(rob_head_idx),
    .prf_ready(prf_ready)
);

endmodule : dispatch_issue