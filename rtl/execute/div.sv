module div
import rv32i_types::*;
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
    output fsu_reg_t        div_reg
);

    logic        dw_complete;
    logic        dw_divide_by_0;
    logic [32:0] dw_quotient;
    logic [32:0] dw_remainder;

    logic [31:0] quotient_final;
    logic [31:0] remainder_final;
    logic        divide_by_0_final;
    logic        signed_op_reg;
    logic        overflow_case;
    logic [32:0] a_reg;
    logic [32:0] b_reg;

    logic        current_valid;
    logic        flush_kills_current;
    logic        dw_rst_n;

    function automatic logic rob_younger_than_flush(
        input rob_idx_t entry_rob_idx,
        input rob_idx_t branch_rob_idx,
        input rob_idx_t head_rob_idx
    );
        rob_idx_t entry_age;
        rob_idx_t branch_age;
        begin
            entry_age  = entry_rob_idx  - head_rob_idx;
            branch_age = branch_rob_idx - head_rob_idx;
            rob_younger_than_flush = (entry_age > branch_age);
        end
    endfunction

    assign current_valid = busy || result_valid || div_reg.issue_exec_reg.rs_entry_out.valid;

    assign flush_kills_current =
        flush &&
        current_valid &&
        rob_younger_than_flush(
            div_reg.issue_exec_reg.rs_entry_out.rob_idx,
            flush_rob_idx,
            rob_head_idx
        );

    logic dw_start;

    always_ff @(posedge clk) begin
        if (!rst_n || flush_kills_current) begin
            dw_start <= 1'b0;
        end else begin
            dw_start <= (!flush && start && !busy);
        end
    end

    logic div_active;

    assign div_active = busy || dw_start;
    assign dw_rst_n   = rst_n && !flush_kills_current && div_active;

    assign overflow_case =
        signed_op_reg &&
        (a_reg[31:0] == 32'h8000_0000) &&
        (b_reg[31:0] == 32'hffff_ffff);

    DW_div_seq #(33, 33, 1, 10, 1, 0, 1, 0) u_div (
        .clk         (clk),
        .rst_n       (dw_rst_n),
        .hold        (hold),
        .start       (dw_start && !flush),
        .a           (a_reg),
        .b           (b_reg),
        .complete    (dw_complete),
        .divide_by_0 (dw_divide_by_0),
        .quotient    (dw_quotient),
        .remainder   (dw_remainder)
    );

    always_comb begin
        divide_by_0_final = 1'b0;
        quotient_final    = dw_quotient[31:0];
        remainder_final   = dw_remainder[31:0];

        if (b_reg == 33'd0) begin
            divide_by_0_final = 1'b1;
            quotient_final    = 32'hffff_ffff;
            remainder_final   = a_reg[31:0];
        end else if (overflow_case) begin
            quotient_final  = 32'h8000_0000;
            remainder_final = 32'h0000_0000;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            busy          <= 1'b0;
            result_valid  <= 1'b0;
            complete      <= 1'b0;
            div_reg       <= '0;
            a_reg         <= '0;
            b_reg         <= '0;
            signed_op_reg <= 1'b0;
        end else begin
            complete <= 1'b0;

            if (flush_kills_current) begin
                busy          <= 1'b0;
                result_valid  <= 1'b0;
                complete      <= 1'b0;
                div_reg       <= '0;
                a_reg         <= '0;
                b_reg         <= '0;
                signed_op_reg <= 1'b0;
            end else begin
                if (output_accepted && result_valid) begin
                    busy         <= 1'b0;
                    result_valid <= 1'b0;
                    div_reg      <= '0;
                end else if (dw_complete && busy && !result_valid) begin
                    result_valid        <= 1'b1;
                    complete            <= 1'b1;
                    div_reg.quotient    <= quotient_final;
                    div_reg.remainder   <= remainder_final;
                    div_reg.divide_by_0 <= divide_by_0_final;
                end

                if (!flush && start && !busy) begin
                    div_reg                <= '0;
                    div_reg.rs1_v          <= rs1_v;
                    div_reg.rs2_v          <= rs2_v;
                    div_reg.issue_exec_reg <= issue_exec_reg;
                    a_reg                  <= a;
                    b_reg                  <= b;
                    signed_op_reg          <= (issue_exec_reg.rs_entry_out.decode_package_out.sign == 2'b11);
                    busy                   <= 1'b1;
                    result_valid           <= 1'b0;
                end
            end
        end
    end

endmodule : div