module cache
import cache_types::*;
(
    input   logic           clk,
    input   logic           rst,


    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,
    output  logic           ufp_advance_ok,


    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);

    addr_t addr;
    logic [3:0] ufp_set;
    logic [22:0] ufp_tag;
    logic [3:0] [22:0] SRAM_tag;
    logic [3:0] [255:0] SRAM_data;
    logic [2:0] lru_out;
    logic [2:0] lru_in;
    logic [3:0] valid_out;
    logic valid_in;
    logic [3:0] valid_web;
    logic lru_web;
    logic [3:0] tag_web;
    logic [22:0] tag_in;
    logic [255:0] data_in;
    logic [3:0] [31:0] data_wmask;
    logic [1:0] victim_way;
    logic [3:0] hit_way_arr;
    logic [1:0] hit_way_num;
    logic [3:0] dirty_web;
    logic dirty_in;
    logic [3:0] dirty_out;
    logic [3:0] reg_wmask;
    logic [3:0] reg_rmask;
    logic [31:0] reg_wdata;
    logic [3:0] set;
    pipeline_reg_t pipeline_reg;


   always_comb begin
    hit_way_arr = 4'b0000;
    hit_way_num = 2'd0;


    if (valid_out[0] && (SRAM_tag[0] == pipeline_reg.addr.tag)) begin
        hit_way_arr[0] = 1'b1;
        hit_way_num = 2'd0;
    end


    if (valid_out[1] && (SRAM_tag[1] == pipeline_reg.addr.tag)) begin
        hit_way_arr[1] = 1'b1;
        hit_way_num = 2'd1;
    end


    if (valid_out[2] && (SRAM_tag[2] == pipeline_reg.addr.tag)) begin
        hit_way_arr[2] = 1'b1;
        hit_way_num = 2'd2;
    end


    if (valid_out[3] && (SRAM_tag[3] == pipeline_reg.addr.tag)) begin
        hit_way_arr[3] = 1'b1;
        hit_way_num = 2'd3;
    end
end
   
    assign set = ufp_addr[8:5];

    always_comb begin // select victim
        victim_way = 2'd0;
        unique casez (lru_out)
            3'b00?: victim_way = 2'd0;
            3'b01?: victim_way = 2'd1;
            3'b1?0: victim_way = 2'd2;
            3'b1?1: victim_way = 2'd3;  
            default: victim_way = 2'd0;
        endcase
    end

    always_comb begin
        lru_in = lru_out;
        unique case (hit_way_num)
            2'd0: lru_in = {1'b1, 1'b1, lru_out[0]};
            2'd1: lru_in = {1'b1, 1'b0, lru_out[0]};
            2'd2: lru_in = {1'b0, lru_out[1], 1'b1};
            2'd3: lru_in = {1'b0, lru_out[1], 1'b0};
            default: lru_in = lru_out;
        endcase
    end

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (1'b0),
            .wmask0     (data_wmask[i]),
            .addr0      (pipeline_reg.addr.set),
            .din0       (data_in),
            
            
            .clk1       (clk),
            .csb1       (1'b0),
            .addr1      (set),
            .dout1      (SRAM_data[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (tag_web[i]),
            .addr0      (pipeline_reg.addr.set),
            .din0       (tag_in),

            .clk1       (clk),
            .csb1       (1'b0),
            .addr1      (set),
            .dout1      (SRAM_tag[i])
            
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (1'b0),
            .web0       (valid_web[i]),
            .addr0      (set),
            .addr1      (pipeline_reg.addr.set),
            .din0       (valid_in),
            .dout0      (valid_out[i])
        );


        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (1'b0),
            .web0       (dirty_web[i]),
            .addr0      (set),
            .addr1      (pipeline_reg.addr.set),
            .din0       (dirty_in),
            .dout0      (dirty_out[i])
        );
    end endgenerate


    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (1'b0),
        .web0       (lru_web),
        .addr0      (set),
        .addr1      (pipeline_reg.addr.set),
        .din0       (lru_in),
        .dout0      (lru_out)
    );

    typedef enum logic [1:0] {  
        tag_check,
        writeback,
        allocate,
        idle
    } state_t;

    state_t state, state_next;

    //logic for fetch to know when to advance pc

    assign ufp_advance_ok = (state == tag_check) &&
    (
        ((pipeline_reg.rmask == 4'b0000) && (pipeline_reg.wmask == 4'b0000))
        || (|hit_way_arr)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            pipeline_reg <= '0;
            state <= tag_check;
        end else if(state_next == tag_check) begin
            pipeline_reg.rmask <= ufp_rmask;
            pipeline_reg.wmask <= ufp_wmask;
            pipeline_reg.wdata <= ufp_wdata;
            pipeline_reg.addr <= ufp_addr;
            state <= state_next;
        end else begin
            state <= state_next;
            if(state == tag_check && state_next == writeback)begin
                pipeline_reg.data_array_out <= SRAM_data[victim_way];
                pipeline_reg.tag_array_out <= SRAM_tag[victim_way];
            end
        end
       
    end
     
   always_comb begin
    state_next = tag_check;
    lru_web = 1'b1;
    ufp_resp = 1'b0;
    dirty_web = 4'b1111;
    tag_web = 4'b1111;
    valid_web = 4'b1111;
    dfp_read = 1'b0;
    dfp_write = 1'b0;
    ufp_rdata = 32'd0;
    data_in = 256'd0;
    data_wmask = 128'd0;
    dirty_in = 1'b0;
    dfp_addr = 32'd0;
    dfp_wdata = 256'b0;
    tag_in = 23'd0;
    valid_in = 1'b0;

    unique case(state)
        tag_check: begin
            if(pipeline_reg.rmask == 4'b0 && pipeline_reg.wmask == 4'b0) begin
                state_next = tag_check;
            end else if(|hit_way_arr) begin
                lru_web = 1'b0;
                ufp_resp = 1'b1;
                state_next = tag_check;
                if(pipeline_reg.rmask != 4'b0) begin
                    ufp_rdata = SRAM_data[hit_way_num][pipeline_reg.addr.offset[4:2] * 32 +: 32];
                end
                if(pipeline_reg.wmask != 4'b0) begin
                    data_in = SRAM_data[hit_way_num];
                    data_in[pipeline_reg.addr.offset[4:2] * 32 +:32] = pipeline_reg.wdata;
                    data_wmask[hit_way_num][pipeline_reg.addr.offset[4:2] * 4 +: 4] = pipeline_reg.wmask;
                    dirty_web[hit_way_num] = 1'b0;
                    dirty_in = 1'b1;
                    if(pipeline_reg.wmask != 4'b0 && (
                        ((ufp_addr[8:2] == pipeline_reg.addr[8:2]) && (ufp_rmask & pipeline_reg.wmask) != 4'b0) ||
                        ((ufp_addr[8:5] == pipeline_reg.addr[8:5]) && ufp_wmask != 4'b0 && (ufp_wmask & pipeline_reg.wmask) != pipeline_reg.wmask)
                        )) begin
                        state_next = idle;
                    end
                end


            end else if(dirty_out[victim_way]) begin
                state_next = writeback;
            end else begin
                state_next = allocate;
            end
        end

        allocate: begin
            state_next = allocate;
            dfp_read = 1'b1;
            dfp_addr = {pipeline_reg.addr[31:5], 5'b00000};
            if(dfp_resp) begin
                
                data_in = dfp_rdata;
                tag_web[victim_way] = 1'b0;
                tag_in = pipeline_reg.addr.tag;
                data_wmask[victim_way] = 32'hffffffff;
                state_next = idle;
                valid_web[victim_way] = 1'b0;
                valid_in = 1'b1;
                dirty_web[victim_way] = 1'b0;
                dirty_in = 1'b0;
            end
        end

        idle: begin
            state_next = tag_check;
        end

        writeback: begin
            state_next = writeback;
            dfp_write = 1'b1;
            dfp_wdata = pipeline_reg.data_array_out;
            dfp_addr = {pipeline_reg.tag_array_out, pipeline_reg.addr.set, 5'b00000};
            if(dfp_resp) begin
                state_next = allocate;
            end
        end

        default: begin
            state_next = state;
            lru_web = 1'b1;
            dirty_web = 4'b1111;
            tag_web = 4'b1111;
            valid_web = 4'b1111;
            dfp_read = 1'b0;
            dfp_write = 1'b0;
            ufp_resp = 1'b0;
            ufp_rdata = 32'd0;
            data_in = 256'd0;
            data_wmask = 128'd0;
            dirty_in = 1'b0;
            dfp_addr = 32'd0;
            dfp_wdata = 256'b0;
            tag_in = 23'd0;
            valid_in = 1'b0;
        end

    endcase
   end

endmodule