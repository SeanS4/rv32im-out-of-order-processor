module rs
import rv32i_types::*;
#(
    parameter integer RS_SIZE = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic flush,

    input  rs_entry rs_entry_in,

    input  logic       cdb_valid,
    input  logic [5:0] rd_s,

    input  logic       issue_slot_ready,
    input  logic       alu_can_issue,
    input  logic       mul_can_issue,
    input  logic       div_can_issue,
    input  logic       lq_cdb_valid,
    input  logic [63:0] prf_ready,

    output logic       issue_fire,
    output rs_entry    rs_entry_out,
    output logic       issue_valid,
    output logic       no_pending_stores_out,
    output logic       full,
    output logic       empty,

    input  rob_idx_t   flush_rob_idx,
    input  rob_idx_t   rob_head_idx
);

    typedef logic [$clog2(RS_SIZE)-1:0] rs_idx_t;

    // The current design uses a 32-entry RS.  The explicit five-level trees
    // below preserve the existing oldest-ready and lowest-free-index policies
    // while avoiding synthesis of 32-decision serial priority chains.
    typedef struct packed {
        logic     valid;
        rob_idx_t age;
        rs_idx_t  idx;
    } issue_candidate_t;

    typedef struct packed {
        logic    valid;
        rs_idx_t idx;
    } slot_candidate_t;

    function automatic issue_candidate_t pick_older(
        input issue_candidate_t left,
        input issue_candidate_t right
    );
        begin
            if (!left.valid) begin
                pick_older = right;
            end else if (!right.valid) begin
                pick_older = left;
            end else if (right.age < left.age) begin
                pick_older = right;
            end else begin
                // Preserve the original loop's tie behavior: the lower
                // physical RS index wins when ROB ages are equal.
                pick_older = left;
            end
        end
    endfunction

    function automatic slot_candidate_t pick_first_slot(
        input slot_candidate_t left,
        input slot_candidate_t right
    );
        begin
            if (left.valid) begin
                pick_first_slot = left;
            end else begin
                pick_first_slot = right;
            end
        end
    endfunction

    rs_entry data [RS_SIZE];
    rs_entry rs_entry_in_wakeup;

    rob_idx_t rs_age_entry;
    rob_idx_t rs_age_flush;

    logic write_en;
    logic found_free;
    logic found_issue;
    logic any_valid;

    logic rs_entry_in_wakeup_uses_rs2;

    // Effective readiness used by the combinational issue selector.  These
    // include both the readiness already stored in the RS entry and a result
    // being broadcast on the CDB in the current cycle.
    logic [RS_SIZE-1:0] entry_uses_rs2;
    logic [RS_SIZE-1:0] rs1_ready_now;
    logic [RS_SIZE-1:0] operand2_ready_now;
    logic [RS_SIZE-1:0] issue_eligible;

    // Balanced 32-to-1 oldest-ready tournament.
    issue_candidate_t issue_l0 [RS_SIZE];
    issue_candidate_t issue_l1 [RS_SIZE/2];
    issue_candidate_t issue_l2 [RS_SIZE/4];
    issue_candidate_t issue_l3 [RS_SIZE/8];
    issue_candidate_t issue_l4 [RS_SIZE/16];
    issue_candidate_t issue_l5 [RS_SIZE/32];

    // Balanced 32-to-1 lowest-free-index tournament.  This also keeps the
    // existing ability to recycle an issuing slot in the same cycle.
    slot_candidate_t free_l0 [RS_SIZE];
    slot_candidate_t free_l1 [RS_SIZE/2];
    slot_candidate_t free_l2 [RS_SIZE/4];
    slot_candidate_t free_l3 [RS_SIZE/8];
    slot_candidate_t free_l4 [RS_SIZE/16];
    slot_candidate_t free_l5 [RS_SIZE/32];

    rs_idx_t free_idx;
    rs_idx_t issue_idx;

    logic rs_has_pending_stores;

    always_comb begin
        rs_has_pending_stores = 1'b0;
        for (integer i = 0; i < RS_SIZE; i++) begin
            if (data[i].valid && data[i].is_store) begin
                rs_has_pending_stores = 1'b1;
            end
        end
    end

    assign no_pending_stores_out = !rs_has_pending_stores;

    assign write_en   = rs_entry_in.valid;
    // Remove an RS entry only when issue_exec_reg can accept it.
    assign issue_fire = issue_valid && issue_slot_ready;

    assign rs_entry_in_wakeup_uses_rs2 =
           rs_entry_in_wakeup.decode_package_out.branch ||
           rs_entry_in_wakeup.decode_package_out.store  ||
          !rs_entry_in_wakeup.decode_package_out.imm_instr;

    always_comb begin
        rs_entry_in_wakeup = rs_entry_in;

        if (cdb_valid && (rd_s != 6'd0) && rs_entry_in.valid) begin
            if (!rs_entry_in_wakeup.rs1_ready &&
                (rs_entry_in_wakeup.rs1_phys != 6'd0) &&
                (rs_entry_in_wakeup.rs1_phys == rd_s)) begin
                rs_entry_in_wakeup.rs1_ready = 1'b1;
            end

            if (!rs_entry_in_wakeup.operand2_ready &&
                rs_entry_in_wakeup_uses_rs2 &&
                (rs_entry_in_wakeup.rs2_phys != 6'd0) &&
                (rs_entry_in_wakeup.rs2_phys == rd_s)) begin
                rs_entry_in_wakeup.operand2_ready = 1'b1;
            end
        end
    end

    // Same-cycle wakeup path.  An entry whose final dependency matches the
    // current CDB destination may participate in issue selection immediately,
    // rather than waiting for its registered ready bit to update next cycle.
    always_comb begin
        for (integer i = 0; i < RS_SIZE; i++) begin
            entry_uses_rs2[i] =
                   data[i].decode_package_out.branch
                || data[i].decode_package_out.store
                || !data[i].decode_package_out.imm_instr;

            rs1_ready_now[i] =
                   data[i].rs1_ready
                || (data[i].rs1_phys == 6'd0)
                || (cdb_valid
                    && (rd_s != 6'd0)
                    && (data[i].rs1_phys == rd_s));

            operand2_ready_now[i] =
                   data[i].operand2_ready
                || !entry_uses_rs2[i]
                || (data[i].rs2_phys == 6'd0)
                || (cdb_valid
                    && (rd_s != 6'd0)
                    && (data[i].rs2_phys == rd_s));
        end
    end

    // Compute per-entry eligibility while preserving same-cycle CDB wakeup.
    // Loads/stores retain their original eligibility behavior; other entries
    // are gated by the availability of their selected functional unit.
    always_comb begin
        for (integer i = 0; i < RS_SIZE; i++) begin
            issue_eligible[i] = 1'b0;

            if (data[i].valid &&
                rs1_ready_now[i] &&
                operand2_ready_now[i] &&
                (!data[i].is_store || !lq_cdb_valid)) begin

                if (data[i].is_load || data[i].is_store) begin
                    issue_eligible[i] = 1'b1;
                end else begin
                    unique case (data[i].decode_package_out.fsu)
                        alu:      issue_eligible[i] = alu_can_issue;
                        mul:      issue_eligible[i] = mul_can_issue;
                        div, rem: issue_eligible[i] = div_can_issue;
                        default:  issue_eligible[i] = 1'b0;
                    endcase
                end
            end
        end
    end

    // Five compare/mux levels replace the old loop-carried age-selection chain.
    always_comb begin
        for (integer i = 0; i < RS_SIZE; i++) begin
            issue_l0[i]       = '0;
            issue_l0[i].valid = issue_eligible[i];
            issue_l0[i].age   = data[i].rob_idx - rob_head_idx;
            issue_l0[i].idx   = rs_idx_t'(i);
        end

        for (integer i = 0; i < RS_SIZE/2; i++) begin
            issue_l1[i] = pick_older(issue_l0[2*i], issue_l0[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/4; i++) begin
            issue_l2[i] = pick_older(issue_l1[2*i], issue_l1[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/8; i++) begin
            issue_l3[i] = pick_older(issue_l2[2*i], issue_l2[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/16; i++) begin
            issue_l4[i] = pick_older(issue_l3[2*i], issue_l3[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/32; i++) begin
            issue_l5[i] = pick_older(issue_l4[2*i], issue_l4[2*i+1]);
        end

        found_issue  = issue_l5[0].valid;
        issue_valid  = issue_l5[0].valid;
        issue_idx    = issue_l5[0].idx;
        rs_entry_out = '0;

        if (issue_l5[0].valid) begin
            rs_entry_out = data[issue_l5[0].idx];
        end
    end

    // Preserve the old lowest-index free-slot policy and same-cycle recycling,
    // but implement it as a balanced priority tree rather than a serial scan.
    always_comb begin
        for (integer i = 0; i < RS_SIZE; i++) begin
            free_l0[i]       = '0;
            free_l0[i].valid =
                !data[i].valid ||
                (issue_fire && (issue_idx == rs_idx_t'(i)));
            free_l0[i].idx   = rs_idx_t'(i);
        end

        for (integer i = 0; i < RS_SIZE/2; i++) begin
            free_l1[i] = pick_first_slot(free_l0[2*i], free_l0[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/4; i++) begin
            free_l2[i] = pick_first_slot(free_l1[2*i], free_l1[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/8; i++) begin
            free_l3[i] = pick_first_slot(free_l2[2*i], free_l2[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/16; i++) begin
            free_l4[i] = pick_first_slot(free_l3[2*i], free_l3[2*i+1]);
        end
        for (integer i = 0; i < RS_SIZE/32; i++) begin
            free_l5[i] = pick_first_slot(free_l4[2*i], free_l4[2*i+1]);
        end

        found_free = free_l5[0].valid;
        free_idx   = free_l5[0].idx;
    end

    assign full = !found_free;

    always_comb begin
        any_valid = 1'b0;

        for (integer i = 0; i < RS_SIZE; i++) begin
            if (data[i].valid) begin
                any_valid = 1'b1;
            end
        end
    end

    assign empty = !any_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < RS_SIZE; i++) begin
                data[i] <= '0;
            end

        end else if (flush) begin
            rs_age_flush = flush_rob_idx - rob_head_idx;

            for (integer i = 0; i < RS_SIZE; i++) begin
                rs_age_entry = data[i].rob_idx - rob_head_idx;

                if (rs_age_entry >= rs_age_flush) begin
                    data[i] <= '0;
                end else if (data[i].valid) begin
                    if (data[i].rs1_phys != 6'd0) begin
                        data[i].rs1_ready <= data[i].rs1_ready
                            || prf_ready[data[i].rs1_phys]
                            || (cdb_valid && (data[i].rs1_phys == rd_s)
                                          && (rd_s != 6'd0));
                    end else begin
                        data[i].rs1_ready <= 1'b1;
                    end

                    if (data[i].decode_package_out.branch ||
                        data[i].decode_package_out.store  ||
                       !data[i].decode_package_out.imm_instr) begin
                        if (data[i].rs2_phys != 6'd0) begin
                            data[i].operand2_ready <= data[i].operand2_ready
                                || prf_ready[data[i].rs2_phys]
                                || (cdb_valid && (data[i].rs2_phys == rd_s)
                                              && (rd_s != 6'd0));
                        end else begin
                            data[i].operand2_ready <= 1'b1;
                        end
                    end
                end
            end

        end else begin
            if (cdb_valid && (rd_s != 6'd0)) begin
                for (integer i = 0; i < RS_SIZE; i++) begin
                    if (data[i].valid) begin
                        if (!data[i].rs1_ready &&
                            (data[i].rs1_phys != 6'd0) &&
                            (data[i].rs1_phys == rd_s)) begin
                            data[i].rs1_ready <= 1'b1;
                        end

                        if (!data[i].operand2_ready &&
                            (data[i].rs2_phys != 6'd0) &&
                            (data[i].rs2_phys == rd_s) &&
                            (data[i].decode_package_out.branch ||
                             data[i].decode_package_out.store  ||
                            !data[i].decode_package_out.imm_instr)) begin
                            data[i].operand2_ready <= 1'b1;
                        end
                    end
                end
            end

            if (issue_fire && write_en && found_free && (free_idx == issue_idx)) begin
                data[issue_idx] <= rs_entry_in_wakeup;
            end else begin
                if (issue_fire) begin
                    data[issue_idx].valid <= 1'b0;
                end

                if (write_en && found_free) begin
                    data[free_idx] <= rs_entry_in_wakeup;
                end
            end
        end
    end

endmodule : rs