module rat
import rv32i_types::*;
#(
    parameter integer reg_length  = 32,
    parameter integer phys_length = 64,
    parameter integer phys_width  = $clog2(phys_length),
    parameter integer reg_width   = $clog2(reg_length)
)
(
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   flush,
    input  logic [phys_width-1:0]  restore_map [reg_length],

    input  logic [reg_width-1:0]   rs1_arch,
    input  logic [reg_width-1:0]   rs2_arch,
    output logic [phys_width-1:0]  rs1_phys,
    output logic [phys_width-1:0]  rs2_phys,
    output logic [phys_width-1:0]  old_rd_phys,

    input  logic                   rename,
    input  logic [reg_width-1:0]   rd_arch,
    input  logic [phys_width-1:0]  new_rd_phys
);

typedef logic [phys_width-1:0] phys_t;

phys_t data [reg_length];

always_comb begin
    if (rs1_arch == '0) begin
        rs1_phys = '0;
    end else begin
        rs1_phys = data[rs1_arch];
    end

    if (rs2_arch == '0) begin
        rs2_phys = '0;
    end else begin
        rs2_phys = data[rs2_arch];
    end

    if(rd_arch == '0) begin
        old_rd_phys = '0;
    end else begin
        old_rd_phys = data[rd_arch];
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < reg_length; i++) begin
            data[i] <= phys_t'(i);
        end
    end else if (flush) begin
        for (integer i = 0; i < reg_length; i++) begin
            data[i] <= restore_map[i];
        end
        data[0] <= '0;
    end else begin
        if (rename && (rd_arch != '0)) begin
            data[rd_arch] <= new_rd_phys;
        end
        data[0] <= '0;
    end
end

endmodule : rat