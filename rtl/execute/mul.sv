module mul
import rv32i_types::*;
#(
    parameter integer MUL_STAGES = 4
)
(
    input  logic            clk,
    input  logic            rst_n,
    input  logic            flush,
    input  rob_idx_t        flush_rob_idx,
    input  rob_idx_t        rob_head_idx,
    input  logic            hold,
    input  logic            start,
    input  logic [32:0]     a,
    input  logic [32:0]     b,
    input  issue_exec_reg_t issue_exec_reg,
    input  logic            output_accepted,
    input  logic [31:0]     rs1_v,
    input  logic [31:0]     rs2_v,

    output logic            busy,
    output logic            result_valid,
    output logic            complete,
    output logic            output_stage_occupied,
    output fsu_reg_t        mul_reg
);

    localparam integer META_DEPTH = MUL_STAGES - 1;

    logic [65:0] product;

    fsu_reg_t pipe_meta [META_DEPTH];
    fsu_reg_t start_meta;

    logic [META_DEPTH-1:0] stage_valid;
    logic [META_DEPTH-1:0] flush_kill_stage;

    rob_idx_t branch_age;
    rob_idx_t entry_age [META_DEPTH];

    logic output_stage_valid;
    logic output_blocked;
    logic pipe_can_advance;
    logic accept_start;

    integer comb_i;
    integer seq_i;

    always_comb begin
        start_meta = '0;
        start_meta.rs1_v = rs1_v;
        start_meta.rs2_v = rs2_v;
        start_meta.issue_exec_reg = issue_exec_reg;
    end

    always_comb begin
        branch_age = flush_rob_idx - rob_head_idx;

        for (comb_i = 0; comb_i < META_DEPTH; comb_i = comb_i + 1) begin
            stage_valid[comb_i] =
                pipe_meta[comb_i].issue_exec_reg.rs_entry_out.valid;

            entry_age[comb_i] =
                pipe_meta[comb_i].issue_exec_reg.rs_entry_out.rob_idx
                - rob_head_idx;

            flush_kill_stage[comb_i] =
                flush &&
                stage_valid[comb_i] &&
                (entry_age[comb_i] > branch_age);
        end
    end

    assign output_stage_valid =
        stage_valid[META_DEPTH-1] &&
       !flush_kill_stage[META_DEPTH-1];

    assign output_stage_occupied = stage_valid[META_DEPTH-1];
    //assign output_stage_occupied = output_stage_valid;

    assign output_blocked =
        output_stage_occupied &&
       !output_accepted;

    assign pipe_can_advance =
       !hold &&
       !output_blocked;

    assign accept_start =
        start &&
       !flush &&
        pipe_can_advance;

    assign busy = !pipe_can_advance;

    assign result_valid = output_stage_valid;
    assign complete     = result_valid;

    always_comb begin
        mul_reg         = pipe_meta[META_DEPTH-1];
        mul_reg.product = product;
    end

    DW_mult_pipe #(33, 33, MUL_STAGES, 1, 1, 0) u_mult (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pipe_can_advance),
        .tc      (1'b1),
        .a       (a),
        .b       (b),
        .product (product)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (seq_i = 0; seq_i < META_DEPTH; seq_i = seq_i + 1) begin
                pipe_meta[seq_i] <= '0;
            end
        end else begin
            if (pipe_can_advance) begin
                for (seq_i = META_DEPTH-1; seq_i > 0; seq_i = seq_i - 1) begin
                    if (flush_kill_stage[seq_i-1]) begin
                        pipe_meta[seq_i] <= '0;
                    end else begin
                        pipe_meta[seq_i] <= pipe_meta[seq_i-1];
                    end
                end

                if (accept_start) begin
                    pipe_meta[0] <= start_meta;
                end else begin
                    pipe_meta[0] <= '0;
                end
            end else begin
                for (seq_i = 0; seq_i < META_DEPTH; seq_i = seq_i + 1) begin
                    if (flush_kill_stage[seq_i]) begin
                        pipe_meta[seq_i] <= '0;
                    end
                end
            end
        end
    end

endmodule : mul