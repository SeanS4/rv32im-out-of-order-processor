module rrat
#(
    parameter integer NUM_ARCH_REGS = 32,
    parameter integer NUM_PHYS_REGS = 64
)
(
    input  logic clk,
    input  logic rst,

    input  logic commit_en,
    input  logic [4:0] rd_arch,
    input  logic [$clog2(NUM_PHYS_REGS)-1:0] commit_phys,

    output logic [$clog2(NUM_PHYS_REGS)-1:0] map_table_out [NUM_ARCH_REGS]
);

localparam integer PHYS_W = $clog2(NUM_PHYS_REGS);

typedef logic [PHYS_W-1:0] phys_t;

logic [PHYS_W-1:0] map_table [NUM_ARCH_REGS];

assign map_table_out = map_table;

always_ff @(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < NUM_ARCH_REGS; i++) begin
            map_table[i] <= phys_t'($unsigned(i));
        end
    end else begin
        if (commit_en && (rd_arch != 5'd0)) begin
            map_table[rd_arch] <= commit_phys;
        end
        map_table[0] <= '0;
    end
end

endmodule : rrat