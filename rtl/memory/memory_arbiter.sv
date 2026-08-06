module memory_arbiter
import rv32i_types::*;
(
    input  logic            clk,
    input  logic            rst,

    // input for dmem
    input   logic   [31:0]  d_ufp_addr,
    input   logic   [3:0]   d_ufp_rmask,
    input   logic   [3:0]   d_ufp_wmask,
    output  logic   [31:0]  d_ufp_rdata,
    input   logic   [31:0]  d_ufp_wdata,
    output  logic           d_ufp_resp,
    output  logic           d_ufp_advance_ok,

    // input for imem
    input   logic   [31:0]  i_ufp_addr,
    input   logic   [3:0]   i_ufp_rmask,
    input   logic   [3:0]   i_ufp_wmask,
    output  logic   [31:0]  i_ufp_rdata,
    input   logic   [31:0]  i_ufp_wdata,
    output  logic           i_ufp_resp,
    output  logic           i_ufp_advance_ok,

    // memory signals
    output  logic   [31:0]  dram_addr,
    output  logic           dram_read,
    output  logic           dram_write,
    output  logic   [63:0]  dram_wdata,
    input   logic           dram_ready,

    input   logic   [63:0]  dram_rdata,
    input   logic           dram_rvalid
);

    logic [31:0]  i_dfp_addr,  d_dfp_addr;
    logic         i_dfp_read,  d_dfp_read;
    logic         i_dfp_write, d_dfp_write;
    logic [255:0] i_dfp_rdata, d_dfp_rdata;
    logic [255:0] i_dfp_wdata, d_dfp_wdata;
    logic         i_dfp_resp,  d_dfp_resp;

    logic [31:0]  i_dram_addr,   d_dram_addr;
    logic         i_dram_read,   d_dram_read;
    logic         i_dram_write,  d_dram_write;
    logic [63:0]  i_dram_wdata,  d_dram_wdata;
    logic [63:0]  i_dram_rdata,  d_dram_rdata;
    logic         i_dram_rvalid, d_dram_rvalid;
    logic         i_dram_ready,  d_dram_ready;

    adapter i_adapter (
        .clk        (clk),
        .rst        (rst),
        .dram_rdata (i_dram_rdata),
        .dram_rvalid(i_dram_rvalid),
        .dfp_addr   (i_dfp_addr),
        .dfp_read   (i_dfp_read),
        .dfp_write  (i_dfp_write),
        .dfp_wdata  (i_dfp_wdata),
        .dram_ready (i_dram_ready),
        .dfp_resp   (i_dfp_resp),
        .dfp_rdata  (i_dfp_rdata),
        .dram_addr  (i_dram_addr),
        .dram_read  (i_dram_read),
        .dram_write (i_dram_write),
        .dram_wdata (i_dram_wdata)
    );

    cache i_cache (
        .clk          (clk),
        .rst          (rst),
        .ufp_addr     (i_ufp_addr),
        .ufp_rmask    (i_ufp_rmask),
        .ufp_wmask    (i_ufp_wmask),
        .ufp_rdata    (i_ufp_rdata),
        .ufp_wdata    (i_ufp_wdata),
        .ufp_resp     (i_ufp_resp),
        .ufp_advance_ok(i_ufp_advance_ok),
        .dfp_addr     (i_dfp_addr),
        .dfp_read     (i_dfp_read),
        .dfp_write    (i_dfp_write),
        .dfp_rdata    (i_dfp_rdata),
        .dfp_wdata    (i_dfp_wdata),
        .dfp_resp     (i_dfp_resp)
    );

    adapter d_adapter (
        .clk        (clk),
        .rst        (rst),
        .dram_rdata (d_dram_rdata),
        .dram_rvalid(d_dram_rvalid),
        .dfp_addr   (d_dfp_addr),
        .dfp_read   (d_dfp_read),
        .dfp_write  (d_dfp_write),
        .dfp_wdata  (d_dfp_wdata),
        .dram_ready (d_dram_ready),
        .dfp_resp   (d_dfp_resp),
        .dfp_rdata  (d_dfp_rdata),
        .dram_addr  (d_dram_addr),
        .dram_read  (d_dram_read),
        .dram_write (d_dram_write),
        .dram_wdata (d_dram_wdata)
    );


    cache d_cache (
        .clk          (clk),
        .rst          (rst),
        .ufp_addr     (d_ufp_addr),
        .ufp_rmask    (d_ufp_rmask),
        .ufp_wmask    (d_ufp_wmask),
        .ufp_rdata    (d_ufp_rdata),
        .ufp_wdata    (d_ufp_wdata),
        .ufp_resp     (d_ufp_resp),
        .ufp_advance_ok(d_ufp_advance_ok),
        .dfp_addr     (d_dfp_addr),
        .dfp_read     (d_dfp_read),
        .dfp_write    (d_dfp_write),
        .dfp_rdata    (d_dfp_rdata),
        .dfp_wdata    (d_dfp_wdata),
        .dfp_resp     (d_dfp_resp)
    );

   
    typedef enum logic [1:0] {
        idle,
        i_waiting,
        d_waiting
    } state_t;

    state_t state, state_next;

    always_ff @(posedge clk) begin
        if (rst)
            state <= idle;
        else
            state <= state_next;
    end

    always_comb begin
        state_next = state;

        i_dram_ready  = 1'b0;
        i_dram_rdata  = 64'b0;
        i_dram_rvalid = 1'b0;

        d_dram_ready  = 1'b0;
        d_dram_rdata  = 64'b0;
        d_dram_rvalid = 1'b0;

        dram_addr  = 32'b0;
        dram_read  = 1'b0;
        dram_write = 1'b0;
        dram_wdata = 64'b0;

        unique case (state)

            idle: begin
                if (d_dfp_read || d_dfp_write)
                    state_next = d_waiting;
                else if (i_dfp_read || i_dfp_write)
                    state_next = i_waiting;
            end

            i_waiting: begin
                dram_addr     = i_dram_addr;
                dram_read     = i_dram_read;
                dram_write    = i_dram_write;
                dram_wdata    = i_dram_wdata;

                i_dram_ready  = dram_ready;
                i_dram_rdata  = dram_rdata;
                i_dram_rvalid = dram_rvalid;

                if (i_ufp_resp) begin
                    if (d_dfp_read || d_dfp_write)
                        state_next = d_waiting;
                    else if (i_dfp_read || i_dfp_write)
                        state_next = i_waiting;
                    else
                        state_next = idle;
                end
            end

            d_waiting: begin
                dram_addr     = d_dram_addr;
                dram_read     = d_dram_read;
                dram_write    = d_dram_write;
                dram_wdata    = d_dram_wdata;

                d_dram_ready  = dram_ready;
                d_dram_rdata  = dram_rdata;
                d_dram_rvalid = dram_rvalid;

                if (d_ufp_resp) begin
                    if (d_dfp_read || d_dfp_write)
                        state_next = d_waiting;
                    else if (i_dfp_read || i_dfp_write)
                        state_next = i_waiting;
                    else
                        state_next = idle;
                end
            end

            default: state_next = idle;

        endcase
    end

endmodule : memory_arbiter