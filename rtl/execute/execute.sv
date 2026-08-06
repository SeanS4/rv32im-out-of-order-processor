module execute
import rv32i_types::*;
(
    input  logic            clk,
    input  logic            rst,
    input  logic            issue_valid,
    input  issue_exec_reg_t issue_exec_reg,
    input  logic [31:0]     rs1_v,
    input  logic [31:0]     rs2_v,

    output fsu_reg_t        fsu_reg_out,
    output logic [5:0]      rs1_s,
    output logic [5:0]      rs2_s,
    output logic            can_accept_issue,
    output logic            alu_busy,
    output logic            mul_busy,
    output logic            div_busy,
    output logic            alu_input_ready,

    output logic            flush,
    output logic [31:0]     pc_redirect,

    // store and load queue
    output logic            lq_addr_valid,
    output logic [3:0]      lq_addr_idx,
    output logic [31:0]     lq_addr,
    output logic [3:0]      lq_rmask,
    output issue_exec_reg_t lq_issue_exec_reg,

    output logic            sq_addr_valid,
    output logic [3:0]      sq_addr_idx,
    output logic [31:0]     sq_addr,
    output logic [3:0]      sq_wmask,
    output logic            sq_data_valid,
    output logic [3:0]      sq_data_idx,
    output logic [31:0]     sq_data,
    output logic            store_complete,
    output rob_idx_t        flush_rob_idx,
    input  rob_idx_t        rob_head_idx,
    output commit_entry_t   flush_commit_data,
    output logic            flush_regf_we,
    output logic [31:0]     flush_rd_v,

    output logic        branch_resolved,
    output logic [31:0] branch_resolved_pc,
    output logic        branch_resolved_taken,

    input  logic            fsu_full,

    output logic [31:0] branch_resolved_target,
    output logic [31:0] exec_raw_rs1_v
);

    logic is_load, is_store;
    logic is_branch, is_jal, is_jalr;
    logic branch_taken;
    logic [2:0] branch_funct3;

    logic [31:0] mem_addr;
    logic [1:0]  addr_low;

    logic [31:0] operand1_v;
    logic [31:0] operand2_v;

    logic [31:0] div_pc_q;
    logic [31:0] mul_pc_q;

    logic [6:0] inst_opcode;
    logic [2:0] inst_funct3;

    assign inst_opcode = issue_exec_reg.rs_entry_out.inst[6:0];
    assign inst_funct3 = issue_exec_reg.rs_entry_out.inst[14:12];

    logic rst_n;
    assign rst_n = ~rst;

    logic issue_fire;

    logic alu_start;
    logic mul_start;
    logic div_start;

    logic [32:0] mul_a;
    logic [32:0] mul_b;
    logic [32:0] div_a;
    logic [32:0] div_b;

    logic alu_result_valid;
    logic mul_result_valid;
    logic div_result_valid;

    logic alu_output_accepted;
    logic mul_output_accepted;
    logic div_output_accepted;

    logic mul_complete;
    logic div_complete;

    logic mul_output_occupied;

    fsu_reg_t alu_reg;
    fsu_reg_t mul_reg;
    fsu_reg_t div_reg;

    logic alu_pending_stale;
    logic mul_pending_stale;
    logic div_pending_stale;

    rob_idx_t alu_in_flight_rob_idx;
    rob_idx_t mul_in_flight_rob_idx;
    rob_idx_t div_in_flight_rob_idx;

    rob_idx_t alu_pending_age;
    rob_idx_t mul_pending_age;
    rob_idx_t div_pending_age;
    rob_idx_t pending_flush_age;

    logic alu_result_is_stale;
    logic mul_result_is_stale;
    logic div_result_is_stale;

    assign alu_pending_age   = alu_in_flight_rob_idx - rob_head_idx;
    assign mul_pending_age   = mul_in_flight_rob_idx - rob_head_idx;
    assign div_pending_age   = div_in_flight_rob_idx - rob_head_idx;
    assign pending_flush_age = flush_rob_idx - rob_head_idx;

    assign alu_result_is_stale = alu_pending_stale;
    assign mul_result_is_stale = mul_pending_stale;
    assign div_result_is_stale = div_pending_stale;

    assign is_load   = issue_exec_reg.rs_entry_out.is_load;
    assign is_store  = issue_exec_reg.rs_entry_out.is_store;
    assign is_branch = (inst_opcode == op_b_br);
    assign is_jal    = (inst_opcode == op_b_jal);
    assign is_jalr   = (inst_opcode == op_b_jalr);

    assign branch_funct3 = inst_funct3;

    assign mem_addr = rs1_v + issue_exec_reg.rs_entry_out.decode_package_out.imm;
    assign addr_low = mem_addr[1:0];

    logic [31:0] actual_pc_q;

    issue_exec_reg_t issue_exec_reg_with_values;

    always_comb begin
        issue_exec_reg_with_values = issue_exec_reg;

        issue_exec_reg_with_values.rs1_v =
            (issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch != 5'd0)
            ? rs1_v
            : 32'd0;

        issue_exec_reg_with_values.rs2_v =
            (issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch != 5'd0)
            ? rs2_v
            : 32'd0;

        lq_issue_exec_reg = issue_exec_reg_with_values;

        store_complete = issue_fire && is_store;
        flush_rob_idx  = issue_exec_reg.rs_entry_out.rob_idx;
    end

    assign branch_resolved       = issue_fire && (is_branch || is_jal || is_jalr);
    assign branch_resolved_pc    = issue_exec_reg.rs_entry_out.pc;
    assign branch_resolved_taken = is_jal || is_jalr || (is_branch && branch_taken);

    always_comb begin
        if (issue_exec_reg.rs_entry_out.decode_package_out.alu_src1_is_pc) begin
            operand1_v = issue_exec_reg.rs_entry_out.pc;
        end else begin
            operand1_v = rs1_v;
        end

        if (issue_exec_reg.rs_entry_out.decode_package_out.alu_src2_is_4) begin
            operand2_v = 32'd4;
        end else if (issue_exec_reg.rs_entry_out.decode_package_out.imm_instr) begin
            operand2_v = issue_exec_reg.rs_entry_out.decode_package_out.imm;
        end else begin
            operand2_v = rs2_v;
        end
    end

    assign mul_a = {issue_exec_reg.rs_entry_out.decode_package_out.sign[1] & operand1_v[31], operand1_v};
    assign mul_b = {issue_exec_reg.rs_entry_out.decode_package_out.sign[0] & operand2_v[31], operand2_v};

    assign div_a = mul_a;
    assign div_b = mul_b;

    assign rs1_s = issue_exec_reg.rs_entry_out.rs1_phys;
    assign rs2_s = issue_exec_reg.rs_entry_out.rs2_phys;

    always_comb begin
        branch_taken = 1'b0;

        unique case (branch_funct3)
            branch_f3_beq  : branch_taken = (rs1_v == rs2_v);
            branch_f3_bne  : branch_taken = (rs1_v != rs2_v);
            branch_f3_blt  : branch_taken = (signed'(rs1_v) <  signed'(rs2_v));
            branch_f3_bge  : branch_taken = (signed'(rs1_v) >= signed'(rs2_v));
            branch_f3_bltu : branch_taken = (rs1_v <  rs2_v);
            branch_f3_bgeu : branch_taken = (rs1_v >= rs2_v);
            default        : branch_taken = 1'b0;
        endcase
    end

    logic [31:0] actual_pc;
    logic [31:0] branch_target;

    logic [31:0] raw_rs1_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            actual_pc_q <= '0;
            raw_rs1_q   <= '0;
        end else if (issue_fire && (is_branch || is_jal || is_jalr)) begin
            actual_pc_q <= actual_pc;
            raw_rs1_q   <= rs1_v;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            div_pc_q <= '0;
            mul_pc_q <= '0;
        end else begin
            if (div_start)
                div_pc_q <= issue_exec_reg.rs_entry_out.pc;
            if (mul_start)
                mul_pc_q <= issue_exec_reg.rs_entry_out.pc;
        end
    end

    always_comb begin
        can_accept_issue = 1'b0;

        if (is_load || is_store) begin
            can_accept_issue = 1'b1;
        end else if (is_branch || is_jal || is_jalr) begin
            // Avoid a combinational loop through same-cycle flush handling.
            can_accept_issue = !alu_busy;
        end else begin
            unique case (issue_exec_reg.rs_entry_out.decode_package_out.fsu)
                alu: can_accept_issue = alu_input_ready;
                mul: can_accept_issue = !mul_busy;
                div: can_accept_issue = !div_busy;
                rem: can_accept_issue = !div_busy;
                default: can_accept_issue = 1'b0;
            endcase
        end
    end

    assign branch_resolved_target = actual_pc;
    assign exec_raw_rs1_v         = raw_rs1_q;
    assign issue_fire             = issue_valid && can_accept_issue;

    always_ff @(posedge clk) begin
        if (rst) begin
            alu_pending_stale     <= 1'b0;
            mul_pending_stale     <= 1'b0;
            div_pending_stale     <= 1'b0;

            alu_in_flight_rob_idx <= '0;
            mul_in_flight_rob_idx <= '0;
            div_in_flight_rob_idx <= '0;
        end else begin
            if (alu_start) begin
                alu_in_flight_rob_idx <= issue_exec_reg.rs_entry_out.rob_idx;
                alu_pending_stale     <= 1'b0;
            end else if (flush && alu_busy) begin
                if (alu_pending_age > pending_flush_age) begin
                    alu_pending_stale <= 1'b1;
                end
            end else if (alu_result_valid && alu_output_accepted) begin
                alu_pending_stale <= 1'b0;
            end

            if (mul_start) begin
                mul_in_flight_rob_idx <= issue_exec_reg.rs_entry_out.rob_idx;
                mul_pending_stale     <= 1'b0;
            end else if (flush && mul_busy) begin
                if (mul_pending_age > pending_flush_age) begin
                    mul_pending_stale <= 1'b1;
                end
            end else if (mul_result_valid && mul_output_accepted) begin
                mul_pending_stale <= 1'b0;
            end

            if (div_start) begin
                div_in_flight_rob_idx <= issue_exec_reg.rs_entry_out.rob_idx;
                div_pending_stale     <= 1'b0;
            end else if (flush && div_busy) begin
                if (div_pending_age > pending_flush_age) begin
                    div_pending_stale <= 1'b1;
                end
            end else if (div_result_valid && div_output_accepted) begin
                div_pending_stale <= 1'b0;
            end
        end
    end

    always_comb begin
        flush_commit_data = '0;
        flush_regf_we     = 1'b0;
        flush_rd_v        = 32'd0;
        actual_pc         = issue_exec_reg.rs_entry_out.pc + 32'd4;

        alu_start = 1'b0;
        mul_start = 1'b0;
        div_start = 1'b0;

        flush       = 1'b0;
        pc_redirect = '0;

        lq_addr_valid = 1'b0;
        lq_addr_idx   = '0;
        lq_addr       = '0;
        lq_rmask      = '0;

        sq_addr_valid = 1'b0;
        sq_addr_idx   = '0;
        sq_addr       = '0;
        sq_wmask      = '0;
        sq_data_valid = 1'b0;
        sq_data_idx   = '0;
        sq_data       = '0;

        if (issue_fire && is_load) begin
            lq_addr_valid = 1'b1;
            lq_addr_idx   = issue_exec_reg.rs_entry_out.lq_idx;
            lq_addr       = mem_addr;

            case (issue_exec_reg.rs_entry_out.decode_package_out.load_op)
                load_f3_lb, load_f3_lbu: begin
                    case (addr_low)
                        2'b00: lq_rmask = 4'b0001;
                        2'b01: lq_rmask = 4'b0010;
                        2'b10: lq_rmask = 4'b0100;
                        2'b11: lq_rmask = 4'b1000;
                    endcase
                end
                load_f3_lh, load_f3_lhu: begin
                    lq_rmask = addr_low[1] ? 4'b1100 : 4'b0011;
                end
                load_f3_lw: begin
                    lq_rmask = 4'b1111;
                end
                default: begin
                    lq_rmask = 4'b0000;
                end
            endcase
        end

        if (issue_fire && is_store) begin
            sq_addr_valid = 1'b1;
            sq_addr_idx   = issue_exec_reg.rs_entry_out.sq_idx;
            sq_addr       = mem_addr;

            case (issue_exec_reg.rs_entry_out.decode_package_out.store_op)
                store_f3_sb: begin
                    case (addr_low)
                        2'b00: sq_wmask = 4'b0001;
                        2'b01: sq_wmask = 4'b0010;
                        2'b10: sq_wmask = 4'b0100;
                        2'b11: sq_wmask = 4'b1000;
                    endcase
                    sq_data = ({24'd0, rs2_v[7:0]} << (8 * addr_low));
                end
                store_f3_sh: begin
                    sq_wmask = addr_low[1] ? 4'b1100 : 4'b0011;
                    sq_data  = addr_low[1] ? {rs2_v[15:0], 16'd0} : {16'd0, rs2_v[15:0]};
                end
                store_f3_sw: begin
                    sq_wmask = 4'b1111;
                    sq_data  = rs2_v;
                end
                default: begin
                    sq_wmask = 4'b0000;
                    sq_data  = '0;
                end
            endcase

            sq_data_valid = 1'b1;
            sq_data_idx   = issue_exec_reg.rs_entry_out.sq_idx;
        end

        if (issue_fire && !is_load && !is_store) begin
            unique case (issue_exec_reg.rs_entry_out.decode_package_out.fsu)
                alu: begin
                    alu_start = 1'b1;
                end
                mul: begin
                    mul_start = 1'b1;
                end
                div, rem: begin
                    div_start = 1'b1;
                end
                default: begin
                    alu_start = 1'b0;
                    mul_start = 1'b0;
                    div_start = 1'b0;
                end
            endcase
        end

        if (issue_fire) begin
            if (is_jal) begin
                actual_pc = issue_exec_reg.rs_entry_out.pc +
                            issue_exec_reg.rs_entry_out.decode_package_out.imm;
                if (actual_pc != issue_exec_reg.rs_entry_out.predicted_pc) begin
                    flush       = 1'b1;
                    pc_redirect = actual_pc;
                end
            end else if (is_jalr) begin
                actual_pc = (rs1_v + issue_exec_reg.rs_entry_out.decode_package_out.imm)
                            & 32'hffff_fffe;
                if (actual_pc != issue_exec_reg.rs_entry_out.predicted_pc) begin
                    flush       = 1'b1;
                    pc_redirect = actual_pc;
                end
            end else if (is_branch) begin
                actual_pc = branch_taken
                            ? issue_exec_reg.rs_entry_out.pc +
                              issue_exec_reg.rs_entry_out.decode_package_out.imm
                            : issue_exec_reg.rs_entry_out.pc + 32'd4;
                if (actual_pc != issue_exec_reg.rs_entry_out.predicted_pc) begin
                    flush       = 1'b1;
                    pc_redirect = actual_pc;
                end
            end else begin
                actual_pc = issue_exec_reg.rs_entry_out.pc + 32'd4;
            end
        end

        fsu_reg_out         = '0;
        alu_output_accepted = 1'b0;
        mul_output_accepted = 1'b0;
        div_output_accepted = 1'b0;

        if (mul_output_occupied && !mul_result_is_stale && !fsu_full) begin
    fsu_reg_out          = mul_reg;
    fsu_reg_out.pc_wdata = mul_reg.issue_exec_reg.rs_entry_out.pc + 32'd4;
    mul_output_accepted  = 1'b1;
end else if (div_result_valid && !div_result_is_stale && !fsu_full) begin
    fsu_reg_out          = div_reg;
    fsu_reg_out.pc_wdata = div_reg.issue_exec_reg.rs_entry_out.pc + 32'd4;
    div_output_accepted  = 1'b1;
end else if (alu_result_valid && !alu_result_is_stale && !fsu_full) begin
    fsu_reg_out = alu_reg;
    if (alu_reg.issue_exec_reg.rs_entry_out.inst[6:0] == 7'b1100011 ||
        alu_reg.issue_exec_reg.rs_entry_out.inst[6:0] == 7'b1101111 ||
        alu_reg.issue_exec_reg.rs_entry_out.inst[6:0] == 7'b1100111)
        fsu_reg_out.pc_wdata = actual_pc_q;
    else
        fsu_reg_out.pc_wdata = alu_reg.issue_exec_reg.rs_entry_out.pc + 32'd4;
    alu_output_accepted = 1'b1;
end

        flush_rd_v    = issue_exec_reg.rs_entry_out.pc + 32'd4;
        flush_regf_we = (is_jal || is_jalr) &&
                        (issue_exec_reg.rs_entry_out.inst[11:7] != 5'd0);

        flush_commit_data.pc        = issue_exec_reg.rs_entry_out.pc;
        flush_commit_data.inst      = issue_exec_reg.rs_entry_out.inst;
        flush_commit_data.pc_wdata  = actual_pc;
        flush_commit_data.regf_we   = flush_regf_we;
        flush_commit_data.rd_wdata  = flush_rd_v;
        flush_commit_data.rs1_addr  = issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch;
        flush_commit_data.rs1_rdata =
            (issue_exec_reg.rs_entry_out.decode_package_out.rs1_arch != 5'd0)
            ? rs1_v : 32'd0;
        flush_commit_data.rs2_addr  = issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch;
        flush_commit_data.rs2_rdata =
            (issue_exec_reg.rs_entry_out.decode_package_out.rs2_arch != 5'd0)
            ? rs2_v : 32'd0;
    end

    alu u_alu (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush),
        .flush_rob_idx   (flush_rob_idx),
        .rob_head_idx    (rob_head_idx),
        .start           (alu_start),
        .rs1_v           (operand1_v),
        .operand2_v      (operand2_v),
        .alu_op          (issue_exec_reg.rs_entry_out.decode_package_out.alu_op),
        .issue_exec_reg  (issue_exec_reg_with_values),
        .output_accepted (alu_output_accepted),
        .busy            (alu_busy),
        .result_valid    (alu_result_valid),
        .input_ready     (alu_input_ready),
        .alu_reg         (alu_reg),
        .rs2_v           (rs2_v)
    );

    mul u_mul (
        .clk                  (clk),
        .rst_n                (rst_n),
        .flush                (flush),
        .flush_rob_idx        (flush_rob_idx),
        .rob_head_idx         (rob_head_idx),
        .hold                 (1'b0),
        .start                (mul_start),
        .a                    (mul_a),
        .b                    (mul_b),
        .issue_exec_reg       (issue_exec_reg_with_values),
        .output_accepted      (mul_output_accepted),
        .busy                 (mul_busy),
        .result_valid         (mul_result_valid),
        .complete             (mul_complete),
        .output_stage_occupied(mul_output_occupied),
        .mul_reg              (mul_reg),
        .rs1_v                (rs1_v),
        .rs2_v                (rs2_v)
    );

    div u_div (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush),
        .flush_rob_idx   (flush_rob_idx),
        .rob_head_idx    (rob_head_idx),
        .hold            (1'b0),
        .start           (div_start),
        .a               (div_a),
        .b               (div_b),
        .issue_exec_reg  (issue_exec_reg_with_values),
        .output_accepted (div_output_accepted),
        .busy            (div_busy),
        .result_valid    (div_result_valid),
        .complete        (div_complete),
        .div_reg         (div_reg),
        .rs1_v           (rs1_v),
        .rs2_v           (rs2_v)
    );

endmodule : execute