module rename_dispatch
import rv32i_types::*;
import tage_types::*;
(
    input  logic [4:0]  rs1_arch,
    input  logic [4:0]  rs2_arch,
    input  logic [4:0]  rd_arch,
    input  logic [31:0] pc,
    input  logic [31:0] inst,
    input  logic        clk,
    input  logic        rst,
    input  logic        valid,
    input  logic        flush,
    input  logic [5:0]  restore_map [32],
    input  logic        rob_ready_write_ena,
    input  logic        rob_ready_write_data,
    input  rob_idx_t  rob_ready_write_idx,
    input  logic        stall_rename,
    input  commit_entry_t commit_data,

    output logic [5:0]  rs1_phys,
    output logic [5:0]  rs2_phys,
    output logic [5:0]  rd_phys,
    output logic        free_list_full,
    output logic        rob_full,
    output rob_idx_t  rob_idx,
    output logic        rob_commit,
    output logic        alloc_we,
    output rob_entry_t  rob_entry_out,
    output logic        free_list_empty,

    input  logic        is_store,
    input  logic [3:0]  sq_idx,
    output rob_idx_t  rob_head_idx,
    input  rob_idx_t  flush_rob_idx,


    input tage_meta_t bp_meta_in 
);

rob_entry_t rob_entry_in;

logic rob_empty;
logic enqueue_rob;

logic [5:0] old_rd_phys_from_rat;

logic enqueue_free_list;
logic dequeue_free_list;
logic [5:0] new_rd_phys;
logic rename_has_dest;
logic commit_frees_dest;

logic [5:0] flush_map [32];

logic [63:0] flush_live_mask;

assign rename_has_dest   = valid && !stall_rename && !flush && (rd_arch != 5'd0);
assign commit_frees_dest = rob_commit && rob_entry_out.valid && (rob_entry_out.rd_arch != 5'd0);

assign enqueue_free_list = !flush && commit_frees_dest;
assign dequeue_free_list = rename_has_dest;
assign alloc_we          = rename_has_dest;

assign enqueue_rob = valid && !stall_rename && !flush;
assign rd_phys     = (rd_arch == 5'd0) ? 6'd0 : new_rd_phys;

always_comb begin
    rob_entry_in = '0;

    rob_entry_in.rd_arch     = rd_arch;
    rob_entry_in.new_rd_phys = rd_phys;
    rob_entry_in.old_rd_phys = old_rd_phys_from_rat;
    rob_entry_in.valid       = valid && !stall_rename && !flush;
    rob_entry_in.ready       = 1'b0;

    rob_entry_in.is_store    = is_store;
    rob_entry_in.sq_idx      = sq_idx;

    rob_entry_in.commit_data.pc        = pc;
    rob_entry_in.commit_data.pc_wdata  = pc + 32'd4;
    rob_entry_in.commit_data.inst      = inst;

    rob_entry_in.commit_data.rs1_addr  = rs1_arch;
    rob_entry_in.commit_data.rs2_addr  = rs2_arch;

    rob_entry_in.bp_meta = bp_meta_in;

    rob_entry_in.commit_data.rs1_rdata = 32'd0;
    rob_entry_in.commit_data.rs2_rdata = 32'd0;

    rob_entry_in.commit_data.regf_we   = 1'b0;
    rob_entry_in.commit_data.rd_wdata  = 32'd0;

    rob_entry_in.commit_data.mem_addr  = 32'd0;
    rob_entry_in.commit_data.mem_rmask = 4'd0;
    rob_entry_in.commit_data.mem_wmask = 4'd0;
    rob_entry_in.commit_data.mem_rdata = 32'd0;
    rob_entry_in.commit_data.mem_wdata = 32'd0;
end

rat u_rat(
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .restore_map(flush_map),
    .rs1_arch(rs1_arch),
    .rs2_arch(rs2_arch),
    .rs2_phys(rs2_phys),
    .rs1_phys(rs1_phys),
    .old_rd_phys(old_rd_phys_from_rat),
    .rename(valid && !stall_rename && !flush),
    .rd_arch(rd_arch),
    .new_rd_phys(rob_entry_in.new_rd_phys)
);

free_list u_free_list(
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .enqueue(enqueue_free_list),
    .dequeue(dequeue_free_list),
    .phys_to_free(rob_entry_out.old_rd_phys),
    .free_phys(new_rd_phys),
    .full(free_list_full),
    .empty(free_list_empty),
    .live_mask(flush_live_mask)
);

rob #(
    .length(ROB_DEPTH)
) u_rob (
    .clk(clk),
    .rst(rst),
    .full(rob_full),
    .empty(rob_empty),
    .flush(flush),
    .flush_rob_idx(flush_rob_idx),
    .restore_map(restore_map),
    .flush_map(flush_map),
    .enqueue(enqueue_rob),
    .rob_entry_out(rob_entry_out),
    .rob_entry_in(rob_entry_in),
    .ready_write_ena(rob_ready_write_ena),
    .ready_write_data(rob_ready_write_data),
    .ready_write_idx(rob_ready_write_idx),
    .tail_idx(rob_idx),
    .head_idx(rob_head_idx),
    .commit(rob_commit),
    .commit_data(commit_data),
    .flush_live_mask(flush_live_mask)
);

endmodule : rename_dispatch