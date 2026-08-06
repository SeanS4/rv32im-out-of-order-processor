module decode
import rv32i_types::*;
(
    input  logic [31:0] instr,
    output decode_package decode_package_out
);

logic [6:0]  opcode;
logic [2:0]  funct3;
logic [6:0]  funct7;

logic [31:0] i_imm;
logic [31:0] s_imm;
logic [31:0] b_imm;
logic [31:0] u_imm;
logic [31:0] j_imm;

instr_t decoded;

assign decoded = instr;
assign opcode  = decoded.i_type.opcode;
assign funct3  = decoded.i_type.funct3;
assign funct7  = decoded.r_type.funct7;

assign i_imm = {{20{instr[31]}}, instr[31:20]};
assign s_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
assign b_imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
assign u_imm = {instr[31:12], 12'h000};
assign j_imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

always_comb begin
    decode_package_out = '0;
    decode_package_out.alu_op = alu_op_add;
    decode_package_out.fsu    = alu;

    unique case (opcode)

        op_b_reg: begin
            decode_package_out.valid    = 1'b1;
            decode_package_out.rs1_arch = decoded.r_type.rs1;
            decode_package_out.rs2_arch = decoded.r_type.rs2;
            decode_package_out.rd_arch  = decoded.r_type.rd;

            if (funct7 == 7'b0000001) begin
                unique case (funct3)
                    mul_default: begin
                        decode_package_out.sign = 2'b11;
                        decode_package_out.fsu  = mul;
                    end

                    mul_high: begin
                        decode_package_out.sign  = 2'b11;
                        decode_package_out.mul_h = 1'b1;
                        decode_package_out.fsu   = mul;
                    end

                    mul_high_s_u: begin
                        decode_package_out.sign  = 2'b10;
                        decode_package_out.mul_h = 1'b1;
                        decode_package_out.fsu   = mul;
                    end

                    mul_high_u: begin
                        decode_package_out.sign  = 2'b00;
                        decode_package_out.mul_h = 1'b1;
                        decode_package_out.fsu   = mul;
                    end

                    div_default: begin
                        decode_package_out.sign = 2'b11;
                        decode_package_out.fsu  = div;
                    end

                    div_u: begin
                        decode_package_out.sign = 2'b00;
                        decode_package_out.fsu  = div;
                    end

                    rem_default: begin
                        decode_package_out.sign = 2'b11;
                        decode_package_out.fsu  = rem;
                    end

                    rem_u: begin
                        decode_package_out.sign = 2'b00;
                        decode_package_out.fsu  = rem;
                    end

                    default: begin
                    end
                endcase
            end else begin
                unique case (funct3)
                    arith_f3_add: begin
                        if (funct7[5]) decode_package_out.alu_op = alu_op_sub;
                        else           decode_package_out.alu_op = alu_op_add;
                    end

                    arith_f3_sll : decode_package_out.alu_op = alu_op_sll;
                    arith_f3_slt : decode_package_out.alu_op = alu_op_slt;
                    arith_f3_sltu: decode_package_out.alu_op = alu_op_sltu;
                    arith_f3_xor : decode_package_out.alu_op = alu_op_xor;

                    arith_f3_sr: begin
                        if (funct7[5]) decode_package_out.alu_op = alu_op_sra;
                        else           decode_package_out.alu_op = alu_op_srl;
                    end

                    arith_f3_or  : decode_package_out.alu_op = alu_op_or;
                    arith_f3_and : decode_package_out.alu_op = alu_op_and;

                    default: begin
                    end
                endcase
            end
        end

        op_b_imm: begin
            decode_package_out.valid     = 1'b1;
            decode_package_out.imm_instr = 1'b1;
            decode_package_out.rs1_arch  = decoded.i_type.rs1;
            decode_package_out.rd_arch   = decoded.i_type.rd;
            decode_package_out.imm       = i_imm;

            unique case (funct3)
                arith_f3_add : decode_package_out.alu_op = alu_op_add;
                arith_f3_sll : decode_package_out.alu_op = alu_op_sll;
                arith_f3_slt : decode_package_out.alu_op = alu_op_slt;
                arith_f3_sltu: decode_package_out.alu_op = alu_op_sltu;
                arith_f3_xor : decode_package_out.alu_op = alu_op_xor;

                arith_f3_sr: begin
                    if (funct7[5]) decode_package_out.alu_op = alu_op_sra;
                    else           decode_package_out.alu_op = alu_op_srl;
                end

                arith_f3_or  : decode_package_out.alu_op = alu_op_or;
                arith_f3_and : decode_package_out.alu_op = alu_op_and;

                default: begin
                end
            endcase
        end

        op_b_lui: begin
            decode_package_out.valid     = 1'b1;
            decode_package_out.rd_arch   = decoded.u_type.rd;
            decode_package_out.imm       = u_imm;
            decode_package_out.imm_instr = 1'b1;
            decode_package_out.alu_op    = alu_op_lui;
        end

        op_b_auipc: begin
            decode_package_out.valid          = 1'b1;
            decode_package_out.rd_arch        = decoded.u_type.rd;
            decode_package_out.imm            = u_imm;
            decode_package_out.imm_instr      = 1'b1;
            decode_package_out.alu_src1_is_pc = 1'b1;
            decode_package_out.alu_op         = alu_op_add;
        end

        op_b_jal: begin
            decode_package_out.valid          = 1'b1;
            decode_package_out.rd_arch        = decoded.j_type.rd;
            decode_package_out.imm            = j_imm;
            decode_package_out.imm_instr      = 1'b1;
            decode_package_out.alu_src1_is_pc = 1'b1;
            decode_package_out.alu_src2_is_4  = 1'b1;
            decode_package_out.alu_op         = alu_op_add;
            decode_package_out.jal            = 1'b1;
        end

        op_b_jalr: begin
            decode_package_out.valid          = 1'b1;
            decode_package_out.rd_arch        = decoded.i_type.rd;
            decode_package_out.rs1_arch       = decoded.i_type.rs1;
            decode_package_out.imm            = i_imm;
            decode_package_out.imm_instr      = 1'b1;
            decode_package_out.alu_src1_is_pc = 1'b1;
            decode_package_out.alu_src2_is_4  = 1'b1;
            decode_package_out.alu_op         = alu_op_add;
            decode_package_out.jalr           = 1'b1;
        end

        op_b_br: begin
            decode_package_out.valid      = 1'b1;
            decode_package_out.rs1_arch   = decoded.b_type.rs1;
            decode_package_out.rs2_arch   = decoded.b_type.rs2;
            decode_package_out.imm        = b_imm;
            decode_package_out.branch     = 1'b1;
            decode_package_out.branch_op  = funct3;
            decode_package_out.alu_op     = alu_op_add;
        end

        op_b_load: begin
            decode_package_out.valid     = 1'b1;
            decode_package_out.rd_arch   = decoded.i_type.rd;
            decode_package_out.rs1_arch  = decoded.i_type.rs1;
            decode_package_out.imm       = i_imm;
            decode_package_out.imm_instr = 1'b1;
            decode_package_out.load      = 1'b1;

            unique case (funct3)
                load_f3_lb : decode_package_out.load_op = load_f3_lb;
                load_f3_lh : decode_package_out.load_op = load_f3_lh;
                load_f3_lw : decode_package_out.load_op = load_f3_lw;
                load_f3_lbu: decode_package_out.load_op = load_f3_lbu;
                load_f3_lhu: decode_package_out.load_op = load_f3_lhu;
                default    : decode_package_out.load_op = '0;
            endcase
        end

        op_b_store: begin
            decode_package_out.valid     = 1'b1;
            decode_package_out.rs1_arch  = decoded.s_type.rs1;
            decode_package_out.rs2_arch  = decoded.s_type.rs2;
            decode_package_out.imm       = s_imm;
            decode_package_out.imm_instr = 1'b1;
            decode_package_out.store     = 1'b1;

            unique case (funct3)
                store_f3_sb: decode_package_out.store_op = store_f3_sb;
                store_f3_sh: decode_package_out.store_op = store_f3_sh;
                store_f3_sw: decode_package_out.store_op = store_f3_sw;
                default    : decode_package_out.store_op = '0;
            endcase
        end

        default: begin
        end

    endcase
end

endmodule : decode