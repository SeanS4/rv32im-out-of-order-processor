module prf
#(
    parameter integer NUM_PHYS_REGS = 64,
    parameter integer NUM_ARCH_REGS = 32,
    parameter integer DATA_WIDTH    = 32,
    parameter integer REG_WIDTH     = $clog2(NUM_PHYS_REGS)
)
(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         flush,
    input  logic [REG_WIDTH-1:0]         restore_map [NUM_ARCH_REGS],
    input  logic                         regf_we,
    input  logic                         bypass_en,
    input  logic [DATA_WIDTH-1:0]        rd_v,
    input  logic [REG_WIDTH-1:0]         rs1_s,
    input  logic [REG_WIDTH-1:0]         rs2_s,
    input  logic [REG_WIDTH-1:0]         rd_s,
    input  logic                         alloc_we,
    input  logic [REG_WIDTH-1:0]         alloc_phys,
    input  logic                         free_we,
    input  logic [REG_WIDTH-1:0]         free_phys,
    input  logic                         lq_bypass_we,
    input  logic [REG_WIDTH-1:0]         lq_bypass_rd_s,
    input  logic [DATA_WIDTH-1:0]        lq_bypass_rd_v,
    input  logic                         flush_bypass_we,
    input  logic [REG_WIDTH-1:0]         flush_bypass_rd_s,
    input  logic [DATA_WIDTH-1:0]        flush_bypass_rd_v,
    output logic [DATA_WIDTH-1:0]        rs1_v,
    output logic [DATA_WIDTH-1:0]        rs2_v,
    output logic [NUM_PHYS_REGS-1:0]     ready
);

logic [DATA_WIDTH-1:0] data [NUM_PHYS_REGS];

always_ff @(posedge clk) begin
    integer i;

    if (rst) begin
        for (i = 0; i < NUM_PHYS_REGS; i++) begin
            data[i] <= '0;
            ready[i] <= (i < NUM_ARCH_REGS) ? 1'b1 : 1'b0;
        end
        data[0]  <= '0;
        ready[0] <= 1'b1;

    end else if (flush) begin
        for (i = 0; i < NUM_ARCH_REGS; i++) begin
            if (restore_map[i] != '0) begin
                ready[restore_map[i]] <= 1'b1;
            end
        end
        if (regf_we && (rd_s != '0)) begin
            data[rd_s]  <= rd_v;
            ready[rd_s] <= 1'b1;
        end
        if (lq_bypass_we && (lq_bypass_rd_s != '0)) begin
            data[lq_bypass_rd_s]  <= lq_bypass_rd_v;
            ready[lq_bypass_rd_s] <= 1'b1;
        end
        if (flush_bypass_we && (flush_bypass_rd_s != '0)) begin
            data[flush_bypass_rd_s]  <= flush_bypass_rd_v;
            ready[flush_bypass_rd_s] <= 1'b1;
        end
        data[0]  <= '0;
        ready[0] <= 1'b1;

    end else begin
        if (regf_we && (rd_s != '0)) begin
            data[rd_s]  <= rd_v;
            ready[rd_s] <= 1'b1;
        end
        if (free_we && (free_phys != '0)) begin
            ready[free_phys] <= 1'b0;
        end
        if (alloc_we && (alloc_phys != '0)) begin
            ready[alloc_phys] <= 1'b0;
        end
        data[0]  <= '0;
        ready[0] <= 1'b1;
    end
end

always_comb begin
    if (rs1_s == '0) begin
        rs1_v = '0;
    end else if (bypass_en && regf_we && (rs1_s == rd_s)) begin
        rs1_v = rd_v;
    end else begin
        rs1_v = data[rs1_s];
    end
    if (rs2_s == '0) begin
        rs2_v = '0;
    end else if (bypass_en && regf_we && (rs2_s == rd_s)) begin
        rs2_v = rd_v;
    end else begin
        rs2_v = data[rs2_s];
    end
end

endmodule : prf