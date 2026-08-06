module cpu
import rv32i_types::*;
import tage_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      dram_addr,
    output  logic               dram_read,
    output  logic               dram_write,
    output  logic   [63:0]      dram_wdata,
    input   logic               dram_ready,

    input   logic   [31:0]      dram_raddr,
    input   logic   [63:0]      dram_rdata,
    input   logic               dram_rvalid
);   

    logic lq_alloc;
    logic [3:0] lq_idx;
    logic lq_full;
    logic lq_addr_valid;
    logic [3:0] lq_addr_idx;
    logic [31:0] lq_addr;
    logic [3:0] lq_rmask;
    logic lq_req_valid;
    logic [31:0] lq_req_addr;
    logic [3:0] lq_req_rmask;
    logic lq_req_granted;
    logic lq_cdb_valid;
    logic [5:0] lq_cdb_rd_phys;
    logic [31:0] lq_cdb_data;

    logic sq_alloc;
    logic [3:0] sq_idx;
    logic sq_full;
    logic sq_addr_valid;
    logic [3:0] sq_addr_idx;
    logic [31:0] sq_addr;
    logic [3:0] sq_wmask;
    logic sq_data_valid;
    logic [3:0] sq_data_idx;
    logic [31:0] sq_data;
    logic sq_commit;
    logic [3:0] sq_commit_idx;
    logic sq_req_valid;
    logic [31:0] sq_req_addr;
    logic [31:0] sq_req_data;
    logic [3:0] sq_req_wmask;
    logic sq_req_granted;

    logic [31:0] sq_fwd_data, sq_fwd_data_q;
    logic        sq_fwd_full;
    logic        sq_fwd_conflict;

    logic combined_cdb_valid;
    logic [5:0] combined_cdb_rd_phys;
    logic [31:0] combined_cdb_data;
    logic combined_cdb_bypass_en;

    logic [31:0] temp;
    assign temp = dram_raddr;
    
    logic [31:0] i_ufp_addr, i_ufp_rdata, i_ufp_wdata;
    logic [3:0] i_ufp_rmask, i_ufp_wmask;
    logic i_ufp_resp;

    logic [255:0] i_dfp_rdata, i_dfp_wdata;
    logic [31:0]  i_dfp_addr;
    logic i_dfp_read, i_dfp_write, i_dfp_resp;  

    logic   [31:0]      i_dram_addr;
    logic               i_dram_read;
    logic               i_dram_write;
    logic   [63:0]      i_dram_wdata;

    logic [31:0] d_ufp_addr, d_ufp_rdata, d_ufp_wdata;
    logic [3:0] d_ufp_rmask, d_ufp_wmask;
    logic d_ufp_resp;

    logic [255:0] d_dfp_rdata, d_dfp_wdata;
    logic [31:0]  d_dfp_addr;
    logic d_dfp_read, d_dfp_write, d_dfp_resp;  
    logic d_ufp_advance_ok, i_ufp_advance_ok;
    logic   [31:0]      d_dram_addr;
    logic               d_dram_read;
    logic               d_dram_write;
    logic   [63:0]      d_dram_wdata;

    logic [31:0] pc_redirect;
    logic fetch_stall, dequeue, iq_empty;
    logic iq_package_valid;
    logic ufp_advance_ok;
    iq_package iq_package_out;

    assign fetch_stall = 1'b0;

    assign i_ufp_wmask = 4'b0000;
    assign i_ufp_wdata = 32'b0;


    if_id_reg_t if_id_reg;
    id_rename_reg_t id_rename_reg;
    dispatch_issue_reg_t dispatch_issue_reg;
    issue_exec_reg_t issue_exec_reg;
    writeback_reg_t writeback_reg;

    decode_package decode_package_out;
    logic decode_uses_rs2;

    logic stall_decode;
    logic stall_rename;
    logic rob_full;
    logic rob_blocked;
    logic free_list_full;
    logic stall_dispatch;
    logic free_list_empty;

    // Rename should only be blocked by resources required by the instruction
    // currently in the rename stage.  A full ROB may also accept a new entry
    // when its head commits on the same cycle.
    logic needs_phys;
    logic needs_lq;
    logic needs_sq;

    tage_meta_t bp_predict_meta;
    logic       bp_predict_taken;

    logic [31:0] btb_target [256];
    logic        btb_valid  [256];
    logic [31:0] btb_pred_target;
    logic        btb_hit;

    logic        bp_redirect;
    logic [31:0] bp_target;

    logic flush;

    logic [63:0] order;
    logic [31:0] in_pc;

    logic[5:0] rs1_phys;
    logic[5:0] rs2_phys;
    logic[5:0] rd_phys;

    logic rs_full;
    logic rs_empty;
    logic issue_valid;
    logic issue_fire;
    logic [5:0] cdb_rs;
    logic rs_no_pending_stores;
    rs_entry rs_entry_out;

    logic [63:0] prf_ready;
    logic [31:0] rs1_v;
    logic [31:0] rs2_v;

    //execute outputs
    logic [5:0] rs1_s;
    logic [5:0] rs2_s;
    fsu_reg_t fsu_reg_out;
    logic can_accept_issue;
    logic div_busy;
    logic mul_busy;
    logic alu_busy;
    logic alu_can_issue;
    logic mul_can_issue;
    logic div_can_issue;
    logic alu_input_ready;
    logic issue_exec_ready;

    commit_entry_t flush_commit_data;
    logic          flush_regf_we;
    logic [31:0]   flush_rd_v;

    rob_idx_t rob_head_idx;

    rob_entry_t rob_entry_out;


    logic       selected_complete_valid;
rob_idx_t selected_complete_rob_idx;
rob_idx_t lq_cdb_rob_idx;
issue_exec_reg_t execute_load_issue_exec_reg;
logic [31:0]     lq_cdb_addr;
logic [3:0]      lq_cdb_rmask;
logic [31:0] lq_cdb_raw_rdata;

logic [31:0] sq_meta_addr;
logic [31:0] sq_meta_data;
logic [3:0]  sq_meta_wmask;

logic       store_complete;
rob_idx_t flush_rob_idx;
rob_idx_t lq_req_rob_idx;


logic [31:0] exec_raw_rs1_v;

rob_idx_t lq_cdb_age;
rob_idx_t lq_flush_age;
logic       lq_cdb_younger_than_flush;
logic       lq_cdb_valid_safe;

assign lq_cdb_age   = lq_cdb_rob_idx - rob_head_idx;
assign lq_flush_age = flush_rob_idx  - rob_head_idx;
assign lq_cdb_younger_than_flush = flush && (lq_cdb_age > lq_flush_age);
assign lq_cdb_valid_safe = lq_cdb_valid && !lq_cdb_younger_than_flush;

logic lq_cdb_survives_flush;
assign lq_cdb_survives_flush = lq_cdb_valid && !(lq_cdb_age > lq_flush_age);

commit_entry_t store_commit_data;

assign issue_exec_ready =
    !issue_exec_reg.issue_valid || can_accept_issue;

assign alu_can_issue =
    issue_exec_ready &&
    alu_input_ready;

assign mul_can_issue =
    issue_exec_ready &&
    !mul_busy &&
    !(issue_exec_reg.issue_valid &&
      (issue_exec_reg.rs_entry_out.decode_package_out.fsu == mul));

assign div_can_issue =
    issue_exec_ready &&
    !div_busy &&
    !(issue_exec_reg.issue_valid &&
      ((issue_exec_reg.rs_entry_out.decode_package_out.fsu == div) ||
       (issue_exec_reg.rs_entry_out.decode_package_out.fsu == rem)));

 
    fsu_reg_t wb_out;
    logic wb_empty, wb_full;

    logic        branch_resolved;
    logic [31:0] branch_resolved_pc;
    logic        branch_resolved_taken;

    
logic wb_result_present;
logic wb_regf_valid;
logic wb_pop;
    

    logic           regf_we;
    logic [31:0]    rd_v;

    rob_idx_t rob_idx;
    logic rob_commit;
    logic alloc_we;

      logic           flush_rob_pending_q;
rob_idx_t     flush_rob_pending_idx_q;
commit_entry_t  flush_rob_pending_data_q;
// physical register for the link register
    logic [5:0] flush_restore_map [32];

assign wb_result_present = !wb_empty;

assign wb_regf_valid = wb_result_present && regf_we;

// Pop the WB/result-queue head only when normal writeback actually owns the
// single ROB completion port.  A pending flush completion has priority over
// writeback, so the WB entry must remain queued until that pending completion
// is delivered.
assign wb_pop =
    wb_result_present &&
    !lq_cdb_valid_safe &&
    !store_complete &&
    !flush_rob_pending_q &&
    !flush;


    assign rob_blocked = rob_full && !rob_commit;

    assign needs_phys =
        id_rename_reg.valid &&
        (id_rename_reg.decode_package_out.rd_arch != 5'd0);

    assign needs_lq =
        id_rename_reg.valid &&
        id_rename_reg.decode_package_out.load;

    assign needs_sq =
        id_rename_reg.valid &&
        id_rename_reg.decode_package_out.store;

    assign stall_rename =
        rs_full ||
        rob_blocked ||
        (free_list_empty && needs_phys) ||
        (lq_full && needs_lq) ||
        (sq_full && needs_sq);

    assign stall_decode   = stall_rename;
    assign stall_dispatch = rs_full;

    // Downstream-ready signal for fetch.  It must not depend on i_ufp_resp:
    // fetch handles resident-IQ dequeue versus empty-IQ response bypass
    // internally, which avoids a combinational timing loop.
    assign dequeue =
        !flush &&
        !stall_rename;


    assign sq_commit = rob_commit && rob_entry_out.is_store;
    assign sq_commit_idx = rob_entry_out.sq_idx;

    logic [31:0] branch_resolved_target;

      issue_exec_reg_t lq_cdb_issue_exec_reg;

commit_entry_t exec_commit_data;
commit_entry_t load_commit_data;
commit_entry_t selected_commit_data;

always_comb begin
    store_commit_data           = '0;
    store_commit_data.pc        = issue_exec_reg.rs_entry_out.pc;
    store_commit_data.inst      = issue_exec_reg.rs_entry_out.inst;
    store_commit_data.pc_wdata  = issue_exec_reg.rs_entry_out.pc + 32'd4;
    store_commit_data.regf_we   = 1'b0;
    store_commit_data.rs1_addr  = issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch;
    store_commit_data.rs1_rdata = (issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch != 5'd0)
                                  ? rs1_v : 32'd0;
    store_commit_data.rs2_addr  = issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch;
    store_commit_data.rs2_rdata = (issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch != 5'd0)
                                  ? rs2_v : 32'd0;
    store_commit_data.mem_addr  = sq_addr;
    store_commit_data.mem_wmask = sq_wmask;
    store_commit_data.mem_wdata = sq_data;
end

always_comb begin
    load_commit_data               = '0;
    load_commit_data.pc            = lq_cdb_issue_exec_reg.rs_entry_out.pc;
    load_commit_data.inst          = lq_cdb_issue_exec_reg.rs_entry_out.inst;
    load_commit_data.regf_we       = 1'b1;
    load_commit_data.rd_wdata      = lq_cdb_data;
    load_commit_data.mem_addr      = lq_cdb_addr;
    load_commit_data.mem_rmask     = lq_cdb_rmask;
    load_commit_data.mem_rdata = lq_cdb_raw_rdata;

    exec_commit_data               = '0;
    exec_commit_data.pc            = wb_out.issue_exec_reg.rs_entry_out.pc;
    exec_commit_data.inst          = wb_out.issue_exec_reg.rs_entry_out.inst;
    exec_commit_data.regf_we       = wb_out.issue_exec_reg.rs_entry_out.decode_package_out.load ||
                                     (!wb_out.issue_exec_reg.rs_entry_out.decode_package_out.store &&
                                      (wb_out.issue_exec_reg.rs_entry_out.inst[11:7] != 5'd0));
    exec_commit_data.rd_wdata      = rd_v;
        exec_commit_data.mem_addr  = wb_out.issue_exec_reg.rs_entry_out.is_store
                                 ? sq_meta_addr  : 32'd0;
    exec_commit_data.mem_wmask = wb_out.issue_exec_reg.rs_entry_out.is_store
                                 ? sq_meta_wmask : 4'd0;
    exec_commit_data.mem_wdata = wb_out.issue_exec_reg.rs_entry_out.is_store
                                 ? sq_meta_data  : 32'd0;

    load_commit_data.pc_wdata = lq_cdb_issue_exec_reg.rs_entry_out.pc + 32'd4;
    exec_commit_data.pc_wdata = wb_out.pc_wdata;

    load_commit_data.rs1_rdata =
    (lq_cdb_issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch != 5'd0)
    ? lq_cdb_issue_exec_reg.rs1_v : 32'd0;

load_commit_data.rs2_rdata =
    (lq_cdb_issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch != 5'd0)
    ? lq_cdb_issue_exec_reg.rs2_v : 32'd0;

    load_commit_data.rs1_addr =
        lq_cdb_issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch;

    load_commit_data.rs2_addr =
        lq_cdb_issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch;

    exec_commit_data.rs1_addr =
        wb_out.issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch;

    // The architectural source operands must remain associated with the
    // specific instruction through execute and writeback.  Do not select the
    // shared exec_raw_rs1_v register here: a younger branch/JALR can overwrite
    // that register before an older instruction reaches WB.
    exec_commit_data.rs1_rdata =
        (wb_out.issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch != 5'd0)
        ? wb_out.issue_exec_reg.rs1_v
        : 32'd0;

    exec_commit_data.rs2_rdata =
        (wb_out.issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch != 5'd0)
        ? wb_out.issue_exec_reg.rs2_v
        : 32'd0;

    exec_commit_data.rs2_addr =
        wb_out.issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch;
end

logic [31:0] lq_pending_addr;
logic [3:0]  lq_pending_rmask;
logic load_queue_pending_resp, store_queue_pending_resp, store_commited_empty;

logic [31:0] lq_resp_data;
logic        lq_fwd_resp;

always_ff @(posedge clk) begin
    if (rst || flush)
        lq_fwd_resp <= 1'b0;
    else if (lq_req_granted && lq_req_valid && sq_fwd_full)
        lq_fwd_resp <= 1'b1;
    else
        lq_fwd_resp <= 1'b0;
end

assign lq_resp_data = lq_fwd_resp ? sq_fwd_data_q : d_ufp_rdata;

always_ff @(posedge clk) begin
    if (rst || flush) begin
        sq_fwd_data_q <= '0;
    end else if (lq_req_granted && lq_req_valid && sq_fwd_full)
        sq_fwd_data_q <= sq_fwd_data;
end

logic lq_resp;
assign lq_resp = (load_queue_pending_resp && !store_queue_pending_resp && d_ufp_resp)
                 || lq_fwd_resp;

logic sq_resp;
assign sq_resp = store_queue_pending_resp && !load_queue_pending_resp && d_ufp_resp;

always_ff @(posedge clk) begin
    if (rst || (flush && !load_queue_pending_resp)) begin
        lq_pending_addr  <= '0;
        lq_pending_rmask <= '0;
    end else if (lq_req_granted && lq_req_valid) begin
        lq_pending_addr  <= lq_req_addr;
        lq_pending_rmask <= lq_req_rmask;
    end
end




logic [31:0] sq_pending_addr;
logic [31:0] sq_pending_data;
logic [3:0]  sq_pending_wmask;

always_ff @(posedge clk) begin
    if (rst || (flush && !store_queue_pending_resp)) begin
        sq_pending_addr  <= '0;
        sq_pending_data  <= '0;
        sq_pending_wmask <= '0;
    end else if (sq_req_granted && sq_req_valid) begin
        sq_pending_addr  <= sq_req_addr;
        sq_pending_data  <= sq_req_data;
        sq_pending_wmask <= sq_req_wmask;
    end
end


    always_comb begin
    d_ufp_addr     = '0;
    d_ufp_wdata    = '0;
    d_ufp_wmask    = '0;
    d_ufp_rmask    = '0;
    sq_req_granted = 1'b0;
    lq_req_granted = 1'b0;

    if (store_queue_pending_resp) begin
        // in-flight store owns the port until response
        d_ufp_addr  = sq_pending_addr;
        d_ufp_wdata = sq_pending_data;
        d_ufp_wmask = d_ufp_resp ? 4'b0000 : sq_pending_wmask;
        d_ufp_rmask = 4'b0000;
    end else if (load_queue_pending_resp) begin
        // in-flight load owns the port until response
        d_ufp_addr  = lq_pending_addr;
        d_ufp_wdata = 32'b0;
        d_ufp_wmask = 4'b0000;
        d_ufp_rmask = lq_fwd_resp ? 4'b0000 : lq_pending_rmask;
    end else if (!flush && sq_req_valid && d_ufp_advance_ok) begin
        // new store if dcache can accept
        d_ufp_addr     = sq_req_addr;
        d_ufp_wdata    = sq_req_data;
        d_ufp_wmask    = sq_req_wmask;
        d_ufp_rmask    = 4'b0000;
        sq_req_granted = 1'b1;
    end else if (!flush && lq_req_valid && sq_fwd_full) begin
        // full store-to-load forward, bypassing cache entirely
        lq_req_granted = 1'b1;
    end else if (!flush && lq_req_valid && !sq_fwd_conflict && d_ufp_advance_ok) begin
        // new load if dcache can accept
        d_ufp_addr     = lq_req_addr;
        d_ufp_wdata    = 32'b0;
        d_ufp_wmask    = 4'b0000;
        d_ufp_rmask    = lq_req_rmask;
        lq_req_granted = 1'b1;
    end
end
    logic [31:0] fetch_pc;

    tage_bp u_tage_bp (
        .clk          (clk),
        .rst          (rst),
        .predict_pc   (fetch_pc),
        .predict_taken(bp_predict_taken),
        .predict_meta (bp_predict_meta),
        .update_valid (branch_resolved),
        .update_pc    (branch_resolved_pc),
        .update_taken (branch_resolved_taken),
        .update_meta(issue_exec_reg.rs_entry_out.bp_meta)
    );


    logic [5:0] btb_tag [256];
    assign bp_redirect = bp_predict_taken && btb_hit && !flush;
    assign bp_target   = btb_pred_target;

    assign btb_hit = btb_valid[fetch_pc[9:2]] && (btb_tag[fetch_pc[9:2]] == fetch_pc[15:10]);
    assign btb_pred_target = btb_target[fetch_pc[9:2]];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < 256; i++) begin
                btb_valid[i]  <= 1'b0;
                btb_target[i] <= '0;
                btb_tag[i]    <= '0;
            end
        end else if (branch_resolved && branch_resolved_taken) begin
            btb_target[branch_resolved_pc[9:2]] <= branch_resolved_target;
            btb_valid [branch_resolved_pc[9:2]] <= 1'b1;
            btb_tag   [branch_resolved_pc[9:2]] <= branch_resolved_pc[15:10];
        end
    end


    memory_arbitor mem
    (
        .clk(clk),
        .rst(rst),

        .d_ufp_addr(d_ufp_addr),
        .d_ufp_rmask(d_ufp_rmask),
        .d_ufp_wmask(d_ufp_wmask),
        .d_ufp_rdata(d_ufp_rdata),
        .d_ufp_wdata(d_ufp_wdata),
        .d_ufp_resp(d_ufp_resp),
        .d_ufp_advance_ok(d_ufp_advance_ok),

        .i_ufp_addr(i_ufp_addr),
        .i_ufp_rmask(i_ufp_rmask),
        .i_ufp_wmask(i_ufp_wmask),
        .i_ufp_rdata(i_ufp_rdata),
        .i_ufp_wdata(i_ufp_wdata),
        .i_ufp_resp(i_ufp_resp),
        .i_ufp_advance_ok(i_ufp_advance_ok),

        .dram_addr(dram_addr),
        .dram_read(dram_read),
        .dram_write(dram_write),
        .dram_wdata(dram_wdata),
        .dram_ready(dram_ready),

        .dram_rdata(dram_rdata),
        .dram_rvalid(dram_rvalid)
    );



    logic full;
    fetch u_fetch
    (
        .clk(clk),
        .rst(rst),
        .stall(fetch_stall),
        .flush(flush), 
        .ufp_resp(i_ufp_resp),
        .ufp_rdata(i_ufp_rdata),
        .ufp_rmask(i_ufp_rmask),
        .pc_redirect(pc_redirect), 
        .dequeue(dequeue),
        .ufp_advance_ok(i_ufp_advance_ok),
        .package_out(iq_package_out),
        .ufp_addr(i_ufp_addr),
        .empty(iq_empty),
        .package_valid(iq_package_valid),
        .bp_predict_taken(bp_predict_taken),
        .btb_hit         (btb_hit),
        .btb_pred_target (btb_pred_target),
        .fetch_pc(fetch_pc),
        .bp_predict_meta(bp_predict_meta)
    );

    decode u_decode
    (
        .instr(if_id_reg.inst),
        
        .decode_package_out(decode_package_out)
    );

load_queue #(
    .DEPTH(8)
) u_load_queue (
    .clk(clk),
    .rst(rst),
    .flush(flush),

    .alloc(lq_alloc),
    .rob_idx(rob_idx),
    .load_op(id_rename_reg.decode_package_out.load_op),
    .rd_arch_in(id_rename_reg.decode_package_out.rd_arch),
    .rd_phys(rd_phys),
    .lq_idx(lq_idx),
    .full(lq_full),

    .addr_valid(lq_addr_valid),
    .addr_lq_idx(lq_addr_idx),
    .addr(lq_addr),
    .rmask(lq_rmask),
    .addr_issue_exec_reg(execute_load_issue_exec_reg),

    .req_valid(lq_req_valid),
    .req_addr(lq_req_addr),
    .req_rmask(lq_req_rmask),
    .req_rob_idx(lq_req_rob_idx),
    .req_granted(lq_req_granted),

    .resp(lq_resp),
    .resp_data(lq_resp_data),
    .load_queue_pending_resp(load_queue_pending_resp),

    .cdb_valid(lq_cdb_valid),
    .cdb_rd_phys(lq_cdb_rd_phys),
    .cdb_rob_idx(lq_cdb_rob_idx),
    .cdb_data(lq_cdb_data),
    .cdb_addr(lq_cdb_addr),
    .cdb_rmask(lq_cdb_rmask),
    .cdb_issue_exec_reg(lq_cdb_issue_exec_reg),
    .cdb_raw_rdata(lq_cdb_raw_rdata),
    .flush_rob_idx(flush_rob_idx),
    .rob_head_idx (rob_head_idx)
);

store_queue #(
    .DEPTH(8)
) u_store_queue (
    .clk(clk),
    .rst(rst),
    .flush(flush),

    .alloc(sq_alloc),
    .rob_idx(rob_idx),
    .store_op(id_rename_reg.decode_package_out.store_op),
    .sq_idx(sq_idx),
    .full(sq_full),
    .store_commited_empty(store_commited_empty),

    .addr_valid(sq_addr_valid),
    .addr_sq_idx(sq_addr_idx),
    .addr(sq_addr),
    .wmask(sq_wmask),

    .data_valid(sq_data_valid),
    .data_sq_idx(sq_data_idx),
    .data(sq_data),

    .commit(sq_commit),
    .commit_sq_idx(sq_commit_idx),

    .req_valid(sq_req_valid),
    .req_addr(sq_req_addr),
    .req_data(sq_req_data),
    .req_wmask(sq_req_wmask),
    .fwd_load_rob_idx(lq_req_rob_idx),
    .req_granted(sq_req_granted),
    .resp(sq_resp),
    .store_queue_pending_resp(store_queue_pending_resp),

    .meta_sq_idx(wb_out.issue_exec_reg.rs_entry_out.sq_idx),
    .meta_addr(sq_meta_addr),
    .meta_data(sq_meta_data),
    .meta_wmask(sq_meta_wmask),

    .fwd_load_addr  (lq_req_addr),
    .fwd_load_rmask (lq_req_rmask),
    .fwd_data       (sq_fwd_data),
    .fwd_full       (sq_fwd_full),
    .fwd_conflict   (sq_fwd_conflict),

    .flush_rob_idx(flush_rob_idx),
    .rob_head_idx (rob_head_idx)
);

     assign selected_complete_valid =
        lq_cdb_valid   ? 1'b1 :
        store_complete ? 1'b1 :
        wb_result_present;

    assign selected_complete_rob_idx =
        lq_cdb_valid   ? lq_cdb_rob_idx :
        store_complete ? issue_exec_reg.rs_entry_out.rob_idx :
        wb_out.issue_exec_reg.rs_entry_out.rob_idx;

    assign selected_commit_data =
        lq_cdb_valid   ? load_commit_data  :
        store_complete ? store_commit_data :
        exec_commit_data;

    logic [5:0] rrat_map [32];
    logic rrat_commit_en;
    logic [4:0] rrat_rd_arch;
    logic [5:0] rrat_commit_phys;

    assign rrat_commit_en   = rob_commit && rob_entry_out.valid && (rob_entry_out.rd_arch != 5'd0);
    assign rrat_rd_arch     = rob_entry_out.rd_arch;
    assign rrat_commit_phys = rob_entry_out.new_rd_phys;
    
    rrat u_rrat(
    .clk(clk),
    .rst(rst),
    .commit_en(rrat_commit_en),
    .rd_arch(rrat_rd_arch),
    .commit_phys(rrat_commit_phys),
    .map_table_out(rrat_map)
);


    logic        final_complete_valid;
    rob_idx_t  final_complete_rob_idx;
    commit_entry_t final_commit_data;


always_ff @(posedge clk) begin
    if (rst) begin
        flush_rob_pending_q      <= 1'b0;
        flush_rob_pending_idx_q  <= '0;
        flush_rob_pending_data_q <= '0;
    end else begin
        if (flush && (lq_cdb_valid_safe || store_complete)) begin
            flush_rob_pending_q      <= 1'b1;
            flush_rob_pending_idx_q  <= flush_rob_idx;
            flush_rob_pending_data_q <= flush_commit_data;
        end
        else if (flush_rob_pending_q && !lq_cdb_valid && !store_complete) begin
            flush_rob_pending_q <= 1'b0;
        end
    end
end

assign final_complete_valid =
    lq_cdb_valid_safe        ? 1'b1 :
    store_complete      ? 1'b1 :
    flush_rob_pending_q ? 1'b1 :
    flush               ? 1'b1 :
    wb_result_present;

assign final_complete_rob_idx =
    lq_cdb_valid_safe        ? lq_cdb_rob_idx :
    store_complete      ? issue_exec_reg.rs_entry_out.rob_idx :
    flush_rob_pending_q ? flush_rob_pending_idx_q :
    flush               ? flush_rob_idx :
    wb_out.issue_exec_reg.rs_entry_out.rob_idx;

assign final_commit_data =
    lq_cdb_valid_safe        ? load_commit_data :
    store_complete      ? store_commit_data :
    flush_rob_pending_q ? flush_rob_pending_data_q :
    flush               ? flush_commit_data :
    exec_commit_data;

    

    always_comb begin
    flush_restore_map = rrat_map;
    if (flush && lq_cdb_survives_flush &&
        lq_cdb_issue_exec_reg.rs_entry_out.decode_package_out.rd_arch != 5'd0) begin
        flush_restore_map[lq_cdb_issue_exec_reg.rs_entry_out.decode_package_out.rd_arch] =
            lq_cdb_rd_phys;
    end
    // JALR/branch rd mapping overrides
    if (flush && flush_regf_we) begin
        flush_restore_map[issue_exec_reg.rs_entry_out.decode_package_out.rd_arch] =
            issue_exec_reg.rs_entry_out.rd_phys;
    end

    if (flush && rob_commit && rob_entry_out.valid &&
        (rob_entry_out.rd_arch != 5'd0)) begin
        flush_restore_map[rob_entry_out.rd_arch] = rob_entry_out.new_rd_phys;
    end
end

    rename_dispatch u_rename_dispatch 
    (
        .rs1_arch(id_rename_reg.decode_package_out.rs1_arch),
        .rs2_arch(id_rename_reg.decode_package_out.rs2_arch),
        .rd_arch(id_rename_reg.decode_package_out.rd_arch),
        .clk(clk),
        .rst(rst),
        .pc(id_rename_reg.pc),
        .inst(id_rename_reg.inst),
        .restore_map(flush_restore_map),
        .valid(id_rename_reg.valid),
        .flush(flush),
        .stall_rename(stall_rename),
        .rob_ready_write_ena (final_complete_valid),
        .rob_ready_write_data(1'b1),
        .rob_ready_write_idx (final_complete_rob_idx),
        .commit_data         (final_commit_data),
    
        .rs1_phys(rs1_phys), 
        .rs2_phys(rs2_phys), 
        .rd_phys(rd_phys),
        .free_list_full(free_list_full),
        .free_list_empty(free_list_empty),
        .rob_full(rob_full),
        .rob_idx(rob_idx),
        .rob_entry_out(rob_entry_out),
        .rob_commit(rob_commit),
        .alloc_we(alloc_we),

        .is_store(id_rename_reg.decode_package_out.store),
        .sq_idx(sq_idx),
        .rob_head_idx(rob_head_idx),
        .flush_rob_idx(flush_rob_idx),

        .bp_meta_in(id_rename_reg.bp_meta)
    );

    dispatch_issue u_dispatch_issue(
    .rs_entry_in(dispatch_issue_reg.rs_entry_in),
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .prf_ready(prf_ready),
    .issue_slot_ready(issue_exec_ready),
    
    .cdb_valid(combined_cdb_valid),
    .lq_cdb_valid(lq_resp),
    .rd_s(combined_cdb_rd_phys),
    
    .rs_entry_out(rs_entry_out),
    .rs_full(rs_full),
    .issue_valid(issue_valid),
    .rs_empty(rs_empty),
    .no_pending_stores_out(rs_no_pending_stores),

    .issue_fire(issue_fire),
    .alu_can_issue(alu_can_issue),
    .mul_can_issue(mul_can_issue),
    .div_can_issue(div_can_issue),
    .flush_rob_idx(flush_rob_idx),
    .rob_head_idx(rob_head_idx)
);

     execute u_execute (
        .clk              (clk),
        .rst              (rst),
        .issue_valid      (issue_exec_reg.issue_valid),
        .issue_exec_reg   (issue_exec_reg),
        .rs1_v            (rs1_v),
        .rs2_v            (rs2_v),

        .fsu_reg_out      (fsu_reg_out),
        .rs1_s            (rs1_s),
        .rs2_s            (rs2_s),
        .can_accept_issue (can_accept_issue),
        .alu_busy         (alu_busy),
        .mul_busy         (mul_busy),
        .div_busy         (div_busy),
        .alu_input_ready  (alu_input_ready),

        .flush            (flush),
        .pc_redirect      (pc_redirect),

        .lq_issue_exec_reg(execute_load_issue_exec_reg),
        .lq_addr_valid    (lq_addr_valid),
        .lq_addr_idx      (lq_addr_idx),
        .lq_addr          (lq_addr),
        .lq_rmask         (lq_rmask),
        .sq_addr_valid    (sq_addr_valid),
        .sq_addr_idx      (sq_addr_idx),
        .sq_addr          (sq_addr),
        .sq_wmask         (sq_wmask),
        .sq_data_valid    (sq_data_valid),
        .sq_data_idx      (sq_data_idx),
        .sq_data          (sq_data),
        .store_complete         (store_complete),
        .flush_rob_idx (flush_rob_idx),
        .rob_head_idx     (rob_head_idx),

        .flush_commit_data(flush_commit_data),
        .flush_regf_we    (flush_regf_we),
        .flush_rd_v       (flush_rd_v),

        .branch_resolved      (branch_resolved),
        .branch_resolved_pc   (branch_resolved_pc),
        .branch_resolved_taken(branch_resolved_taken),
        .branch_resolved_target(branch_resolved_target),
        .exec_raw_rs1_v(exec_raw_rs1_v),
        .fsu_full      (wb_full)
    );

    fsu_queue #(
        .length(4),
        .width(fsu_reg_t)
    ) u_result_queue (
        .clk        (clk),
        .rst        (rst),
        .flush      (flush),
        .flush_rob_idx   (flush_rob_idx),
        .rob_head_idx    (rob_head_idx),
        .enqueue    (fsu_reg_out.issue_exec_reg.rs_entry_out.valid),
        .dequeue    (wb_pop),
        .package_in (fsu_reg_out),
        .package_out(wb_out),
        .full       (wb_full),
        .empty      (wb_empty)
    );

    writeback u_writeback(
        .writeback_reg(wb_out),
        .regf_we(regf_we),
        .rd_v(rd_v)
    );

   prf u_prf(
    .clk(clk),
    .rst(rst),
    .flush(flush),                       
    .restore_map(flush_restore_map),      
    .regf_we(combined_cdb_valid),
    .bypass_en(combined_cdb_bypass_en),
    .flush_bypass_we   (flush && flush_regf_we),
    .flush_bypass_rd_s (issue_exec_reg.rs_entry_out.rd_phys),
    .flush_bypass_rd_v (flush_rd_v),
    .rs1_s(rs1_s),
    .rs2_s(rs2_s),
    .rd_s(combined_cdb_rd_phys),
    .alloc_we(alloc_we),
    .alloc_phys(rd_phys),
    .rs1_v(rs1_v),
    .rs2_v(rs2_v),
    .ready(prf_ready),
    .rd_v(combined_cdb_data),
    .lq_bypass_we(flush && lq_cdb_valid && (lq_cdb_age <= lq_flush_age)),
    .lq_bypass_rd_s (lq_cdb_rd_phys),
    .lq_bypass_rd_v (lq_cdb_data),

    .free_we  (!flush && rob_commit && rob_entry_out.valid && (rob_entry_out.rd_arch != 5'd0)),
    .free_phys(rob_entry_out.old_rd_phys)

);
    

    always_ff @(posedge clk) begin
        if(rst || flush) begin
            if_id_reg <= '0;
        end else if(!stall_decode) begin
            // iq_package_valid also covers an I-cache response bypassing an
            // empty IQ in this cycle.
            if(iq_package_valid && (iq_package_out.inst != '0)) begin
                if_id_reg.pc           <= iq_package_out.pc;
                if_id_reg.inst         <= iq_package_out.inst;
                if_id_reg.predicted_pc <= iq_package_out.predicted_pc;
                if_id_reg.bp_meta      <= iq_package_out.bp_meta;
                if_id_reg.valid        <= 1'b1;
            end else begin
                if_id_reg.valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk)begin
        if(rst || flush) begin
            id_rename_reg <= '0;
        end else if(!flush && !stall_rename) begin
            id_rename_reg.pc <= if_id_reg.pc;
            id_rename_reg.inst <= if_id_reg.inst;
            id_rename_reg.predicted_pc <= if_id_reg.predicted_pc;
            id_rename_reg.bp_meta <= if_id_reg.bp_meta;
            id_rename_reg.valid <= (if_id_reg.valid);
            id_rename_reg.decode_package_out <= decode_package_out;
        end 
    end

    always_comb begin
    combined_cdb_valid     = 1'b0;
    combined_cdb_rd_phys   = '0;
    combined_cdb_data      = '0;
    combined_cdb_bypass_en = 1'b0;

    if (lq_cdb_valid) begin
        combined_cdb_valid     = 1'b1;
        combined_cdb_rd_phys   = lq_cdb_rd_phys;
        combined_cdb_data      = lq_cdb_data;
        combined_cdb_bypass_en = 1'b1;
    end else if (regf_we) begin
        combined_cdb_valid     = 1'b1;
        combined_cdb_rd_phys   = wb_out.issue_exec_reg.rs_entry_out.rd_phys;
        combined_cdb_data      = rd_v;
        combined_cdb_bypass_en = 1'b1;
    end
end


    assign decode_uses_rs2 =
           id_rename_reg.decode_package_out.branch ||
           id_rename_reg.decode_package_out.store  ||
          !id_rename_reg.decode_package_out.imm_instr;

    // The dispatch buffer and reservation station need their own consume
    // handshake.  stall_rename can be asserted by the ROB, free list, LQ, or
    // SQ even while the RS still has room.  In that case the buffered entry
    // must enter the RS exactly once and then become invalid.
    logic dispatch_to_rs_fire;

    assign dispatch_to_rs_fire =
        dispatch_issue_reg.rs_entry_in.valid &&
        !rs_full &&
        !flush;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            dispatch_issue_reg <= '0;

        end else if (!stall_rename) begin
            // Normal one-in/one-out operation:
            // the old dispatch entry is consumed by the RS while the next
            // renamed instruction replaces it in this register.
            dispatch_issue_reg.rs_entry_in.valid <= id_rename_reg.valid;
            dispatch_issue_reg.rs_entry_in.decode_package_out
                <= id_rename_reg.decode_package_out;
            dispatch_issue_reg.rs_entry_in.pc
                <= id_rename_reg.pc;
            dispatch_issue_reg.rs_entry_in.inst
                <= id_rename_reg.inst;
            // Preserve the predicted next PC generated at fetch so execute
            // compares against the prediction belonging to this instruction.
            dispatch_issue_reg.rs_entry_in.predicted_pc
                <= id_rename_reg.predicted_pc;
            dispatch_issue_reg.rs_entry_in.rs1_phys
                <= rs1_phys;
            dispatch_issue_reg.rs_entry_in.rs2_phys
                <= rs2_phys;
            dispatch_issue_reg.rs_entry_in.rd_phys
                <= rd_phys;
            dispatch_issue_reg.rs_entry_in.lq_idx
                <= lq_idx;
            dispatch_issue_reg.rs_entry_in.sq_idx
                <= sq_idx;
            dispatch_issue_reg.rs_entry_in.is_load
                <= id_rename_reg.decode_package_out.load;
            dispatch_issue_reg.rs_entry_in.is_store
                <= id_rename_reg.decode_package_out.store;
            dispatch_issue_reg.rs_entry_in.rs1_ready <=
                prf_ready[rs1_phys] ||
                (combined_cdb_valid &&
                 (rs1_phys != 6'd0) &&
                 (rs1_phys == combined_cdb_rd_phys));
            dispatch_issue_reg.rs_entry_in.operand2_ready <=
                !decode_uses_rs2 ||
                prf_ready[rs2_phys] ||
                (combined_cdb_valid &&
                 (rs2_phys != 6'd0) &&
                 (rs2_phys == combined_cdb_rd_phys));
            dispatch_issue_reg.rs_entry_in.rob_idx
                <= rob_idx;
            dispatch_issue_reg.valid
                <= id_rename_reg.valid;

        end else begin
            // The buffered instruction is being held because rename is
            // stalled.  Its sources may become ready while it waits, so
            // refresh the cached readiness bits every cycle from the PRF and
            // the current CDB broadcast.
            if (dispatch_issue_reg.rs_entry_in.valid) begin
                if (!dispatch_issue_reg.rs_entry_in.rs1_ready) begin
                    dispatch_issue_reg.rs_entry_in.rs1_ready <=
                        prf_ready[
                            dispatch_issue_reg.rs_entry_in.rs1_phys
                        ] ||
                        (combined_cdb_valid &&
                         (dispatch_issue_reg.rs_entry_in.rs1_phys != 6'd0) &&
                         (dispatch_issue_reg.rs_entry_in.rs1_phys ==
                          combined_cdb_rd_phys));
                end

                if (!dispatch_issue_reg.rs_entry_in.operand2_ready) begin
                    dispatch_issue_reg.rs_entry_in.operand2_ready <=
                        prf_ready[
                            dispatch_issue_reg.rs_entry_in.rs2_phys
                        ] ||
                        (combined_cdb_valid &&
                         (dispatch_issue_reg.rs_entry_in.rs2_phys != 6'd0) &&
                         (dispatch_issue_reg.rs_entry_in.rs2_phys ==
                          combined_cdb_rd_phys));
                end
            end

            if (dispatch_to_rs_fire) begin
                // A non-RS resource is still blocking rename, but the RS
                // consumed the already-allocated buffered instruction.
                dispatch_issue_reg.rs_entry_in.valid <= 1'b0;
                dispatch_issue_reg.valid             <= 1'b0;
            end
        end
    end


    always_comb begin
        lq_alloc = 1'b0;
        sq_alloc = 1'b0;
        
        if (id_rename_reg.valid && !stall_rename) begin
            lq_alloc = id_rename_reg.decode_package_out.load;
            sq_alloc = id_rename_reg.decode_package_out.store;
        end
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            issue_exec_reg <= '0;

        end else if (issue_exec_ready) begin
            // Empty or consumed: refill from the RS on this same edge.
            issue_exec_reg.issue_valid <= 1'b0;

            if (issue_fire) begin
                issue_exec_reg.rs_entry_out <= rs_entry_out;
                issue_exec_reg.issue_valid  <= 1'b1;

                // rs1_v/rs2_v are currently addressed by the instruction
                // already in issue_exec_reg.  During a same-cycle
                // consume-and-refill they do not belong to rs_entry_out.
                // execute.sv stamps the correct live PRF values into the
                // per-instruction package when this new entry is accepted.
                issue_exec_reg.rs1_v        <= 32'd0;
                issue_exec_reg.rs2_v        <= 32'd0;
                issue_exec_reg.pc_wdata     <= rs_entry_out.pc + 32'd4;
            end
        end
        // Otherwise hold the complete entry until execute accepts it.
    end



 // MONITOR INTERFACE
    logic commit;
    logic monitor_valid;
    logic [63:0] monitor_order;
    logic [31:0] monitor_inst;
    logic [4:0] monitor_rs1_addr;
    logic [4:0] monitor_rs2_addr;
    logic [31:0] monitor_rs1_rdata;
    logic [31:0] monitor_rs2_rdata;
    logic monitor_regf_we;
    logic [4:0] monitor_rd_addr;
    logic [31:0] monitor_rd_wdata;
    logic [31:0] monitor_pc_rdata;
    logic [31:0] monitor_pc_wdata;
    logic [31:0] monitor_mem_addr;
    logic [3:0] monitor_mem_rmask;
    logic [3:0] monitor_mem_wmask;
    logic [31:0] monitor_mem_rdata;
    logic [31:0] monitor_mem_wdata;

    logic [63:0] rvfi_order_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            rvfi_order_q <= 64'd0;
        end else if (commit) begin
            rvfi_order_q <= rvfi_order_q + 64'd1;
        end
    end

    assign commit = rob_commit;

    assign monitor_valid = commit;
    assign monitor_order = rvfi_order_q;
    assign monitor_inst = rob_entry_out.commit_data.inst;

    // operand info captured for this instruction
    assign monitor_rs1_addr = rob_entry_out.commit_data.rs1_addr;
    assign monitor_rs2_addr = rob_entry_out.commit_data.rs2_addr;
    assign monitor_rs1_rdata = rob_entry_out.commit_data.rs1_rdata;
    assign monitor_rs2_rdata = rob_entry_out.commit_data.rs2_rdata;

    // writeback
    assign monitor_regf_we = rob_entry_out.commit_data.regf_we;
    assign monitor_rd_addr = rob_entry_out.rd_arch;
    assign monitor_rd_wdata = rob_entry_out.commit_data.rd_wdata;

    // pc
    assign monitor_pc_rdata = rob_entry_out.commit_data.pc;
    assign monitor_pc_wdata = rob_entry_out.commit_data.pc_wdata;

    // memory info for the retired instruction
    assign monitor_mem_addr  = rob_entry_out.commit_data.mem_addr;
    assign monitor_mem_rmask = rob_entry_out.commit_data.mem_rmask;
    assign monitor_mem_wmask = rob_entry_out.commit_data.mem_wmask;
    assign monitor_mem_rdata = rob_entry_out.commit_data.mem_rdata;
    assign monitor_mem_wdata = rob_entry_out.commit_data.mem_wdata;



endmodule : cpu