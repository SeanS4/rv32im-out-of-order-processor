package cache_types;

    typedef struct packed {
        logic [31:9] tag;
        logic [8:5] set;
        logic [4:0] offset;
    } addr_t;

    typedef struct packed{
        addr_t addr;
        logic [3:0] rmask;
        logic [3:0] wmask;
        logic [31:0] wdata;
        //logic [1:0] victim_way;
        logic [255:0] data_array_out;
        logic [22:0] tag_array_out;
    } pipeline_reg_t;


    typedef struct packed {
        logic [31:0] ufp_addr;
        logic [3:0] ufp_rmask;
        logic [3:0] ufp_wmask;
        logic [31:0] ufp_wdata;
        logic [255:0] dfp_rdata;
    } input_transaction_t;

    typedef struct packed {
        logic [31:0] ufp_rdata;
        logic caused_dfp_read;
        logic caused_dfp_write;
        logic [31:0] dfp_read_address;
        logic [31:0] dfp_write_address;
        logic [255:0] dfp_writeback_data;
        logic hit;
    
    } output_transaction_t;

endpackage : cache_types