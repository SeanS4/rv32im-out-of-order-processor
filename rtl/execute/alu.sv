module alu
import rv32i_types::*;
(
    input  logic            clk,
    input  logic            rst_n,
    input  logic            flush,
    input  rob_idx_t        flush_rob_idx,
    input  rob_idx_t        rob_head_idx,
    input  logic            start,
    input  logic [31:0]     rs1_v,
    input  logic [31:0]     operand2_v,
    input  logic [3:0]      alu_op,
    input  issue_exec_reg_t issue_exec_reg,
    input  logic            output_accepted,
    input  logic [31:0]     rs2_v,

    output logic            busy,
    output logic            result_valid,
    output logic            input_ready,
    output fsu_reg_t        alu_reg
);

    logic [31:0] aluout;
    logic        current_valid;
    logic        flush_kills_current;

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

    // One-entry output buffer: accept when empty or when the current
    // result is consumed in this cycle.
    assign input_ready = !result_valid || output_accepted;


    assign current_valid = busy || result_valid || alu_reg.issue_exec_reg.rs_entry_out.valid;

    assign flush_kills_current =
        flush &&
        current_valid &&
        rob_younger_than_flush(
            alu_reg.issue_exec_reg.rs_entry_out.rob_idx,
            flush_rob_idx,
            rob_head_idx
        );

    always_comb begin
        aluout = 32'd0;

        unique case (alu_op)
            alu_op_add   : aluout = rs1_v + operand2_v;
            alu_op_sll   : aluout = rs1_v << operand2_v[4:0];
            alu_op_sra   : aluout = unsigned'(signed'(rs1_v) >>> operand2_v[4:0]);
            alu_op_sub   : aluout = rs1_v - operand2_v;
            alu_op_xor   : aluout = rs1_v ^ operand2_v;
            alu_op_srl   : aluout = rs1_v >> operand2_v[4:0];
            alu_op_or    : aluout = rs1_v | operand2_v;
            alu_op_and   : aluout = rs1_v & operand2_v;
            alu_op_sltu  : aluout = {31'd0, rs1_v < operand2_v};
            alu_op_slt   : aluout = {31'd0, signed'(rs1_v) < signed'(operand2_v)};
            alu_op_auipc : aluout = issue_exec_reg.rs_entry_out.pc + operand2_v;
            alu_op_lui   : aluout = operand2_v;
            default      : aluout = 32'd0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            result_valid <= 1'b0;
            alu_reg      <= '0;
        end else if (flush_kills_current) begin
            busy         <= 1'b0;
            result_valid <= 1'b0;
            alu_reg      <= '0;

        end else if (input_ready) begin
            // Consume-and-replace: the old result may leave while a new
            // result occupies this register on the same edge.
            if (!flush && start) begin
                busy                   <= 1'b1;
                result_valid           <= 1'b1;
                alu_reg                <= '0;
                alu_reg.rs1_v          <= rs1_v;
                alu_reg.rs2_v          <= rs2_v;
                alu_reg.issue_exec_reg <= issue_exec_reg;
                alu_reg.aluout         <= aluout;
            end else begin
                busy         <= 1'b0;
                result_valid <= 1'b0;
                alu_reg      <= '0;
            end
        end
    end

endmodule : alu