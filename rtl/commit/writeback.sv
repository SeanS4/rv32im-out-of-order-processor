module writeback
import rv32i_types::*;
(
    input  writeback_reg_t writeback_reg,

    output logic        regf_we,
    output logic [31:0] rd_v
    
);

    instr_t      instr;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic        valid;

    logic [65:0] product;
    logic [31:0] aluout;
    logic [31:0] quotient;
    logic [31:0] remainder;
    logic        divide_by_0;

    logic        mul_h;
    logic [1:0]  fsu_sel;

    // pull from pipeline
    assign instr        = writeback_reg.reg_out.issue_exec_reg.rs_entry_out.inst;
    assign opcode       = instr.i_type.opcode;
    assign funct3       = instr.i_type.funct3;
    assign valid        = writeback_reg.reg_out.issue_exec_reg.rs_entry_out.valid;

    assign product      = writeback_reg.reg_out.product;
    assign aluout       = writeback_reg.reg_out.aluout;
    assign quotient     = writeback_reg.reg_out.quotient;
    assign remainder    = writeback_reg.reg_out.remainder;
    assign divide_by_0  = writeback_reg.reg_out.divide_by_0;

    assign mul_h        = writeback_reg.reg_out.issue_exec_reg.rs_entry_out.decode_package_out.mul_h;
    assign fsu_sel      = writeback_reg.reg_out.issue_exec_reg.rs_entry_out.decode_package_out.fsu;

    always_comb begin
        regf_we = 1'b0;
        rd_v    = 32'd0;

        if (valid) begin
            unique case (opcode)

                op_b_reg: begin
                    regf_we = 1'b1;

                    unique case (fsu_sel)
                        alu: begin
                            rd_v = aluout;
                        end

                        mul: begin
                            if (mul_h) begin
                                rd_v = product[63:32];
                            end else begin
                                rd_v = product[31:0];
                            end
                        end

                        div: begin
                            if (divide_by_0) begin
                                rd_v = 32'hFFFF_FFFF;
                            end else begin
                                rd_v = quotient;
                            end
                        end

                        rem: begin
                            if (divide_by_0) begin
                                
                                rd_v = remainder;
                            end else begin
                                rd_v = remainder;
                            end
                        end

                        default: begin
                            regf_we = 1'b0;
                            rd_v    = 32'd0;
                        end
                    endcase
                end

                op_b_imm,
                op_b_lui,
                op_b_auipc,
                op_b_jal,
                op_b_jalr: begin
                    regf_we = 1'b1;
                    rd_v    = aluout;
                end

                op_b_load: begin
                    regf_we = 1'b0;
                    rd_v    = 32'd0;
                end

                default: begin
                    regf_we = 1'b0;
                    rd_v    = 32'd0;
                end
            endcase
        end
    end

endmodule : writeback