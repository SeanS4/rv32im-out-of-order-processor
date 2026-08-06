module adapter
(
    input logic clk,
    input logic rst,
    input logic [63:0] dram_rdata,
    input logic dram_rvalid,
    input logic [31:0] dfp_addr,
    input logic dfp_read,
    input logic dfp_write,
    input logic [255:0] dfp_wdata,
    input logic dram_ready,
    
    output logic dfp_resp,
    output logic [255:0] dfp_rdata,
    output logic [31:0] dram_addr,
    output logic dram_read,
    output logic dram_write,
    output logic [63:0] dram_wdata
);

typedef enum logic[2:0]{
    idle,
    read_wait,
    first_burst,
    second_burst,
    third_burst
} state_t;

state_t state, state_next;
logic [191:0] rdata_buf_q, rdata_buf_d;

always_ff @(posedge clk) begin
    if(rst) begin
        state <= idle;
        rdata_buf_q <= '0;
    end else begin
        state <= state_next;
        rdata_buf_q <= rdata_buf_d;
    end
end

assign dram_addr = dfp_addr;

always_comb begin
    state_next = state;
    dfp_resp = 1'b0;
    dram_write = 1'b0;
    dram_wdata = '0;
    dram_read = 1'b0;
    dfp_rdata = '0;
    rdata_buf_d = rdata_buf_q;

    unique case(state)
    idle: begin
        if(dfp_write && dram_ready) begin //assuming ready means we can accept new request
            state_next = first_burst;
            dram_wdata = dfp_wdata[63:0];
            dram_write = 1'b1;
        end else if(dfp_read && dram_ready) begin
            state_next = read_wait;
            dram_read = 1'b1;
            rdata_buf_d = '0;
        end

    end


    read_wait: begin
        if(dram_rvalid && dfp_read) begin
            rdata_buf_d[63:0] = dram_rdata;
            state_next = first_burst;
        end else begin
            state_next = read_wait;
        end
    end

    first_burst: begin
        if(dfp_write) begin
            state_next = second_burst;
            dram_write = 1'b1;
            dram_wdata = dfp_wdata[127:64];
        end else if (dfp_read && dram_rvalid) begin
            state_next = second_burst;
            rdata_buf_d[127:64] = dram_rdata;
        end
        
    end
    

    second_burst: begin
       if(dfp_write) begin
        state_next = third_burst;
        dram_wdata = dfp_wdata[191:128];
        dram_write = 1'b1;
       end else if(dfp_read && dram_rvalid) begin
        state_next = third_burst;
        rdata_buf_d[191:128] = dram_rdata;
       end
    end

    third_burst: begin
        if(dfp_write) begin
            state_next = idle;
            dram_wdata = dfp_wdata[255:192];
            dram_write = 1'b1;
            dfp_resp = 1'b1;
        end else if(dfp_read && dram_rvalid) begin
            state_next = idle;
            dfp_resp = 1'b1;
            dfp_rdata = {dram_rdata, rdata_buf_d};
        end
    end

    default: begin
        state_next = idle;  
    end
    endcase
end

endmodule: adapter