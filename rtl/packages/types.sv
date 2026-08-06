package rv32i_types;
import tage_types::*;

localparam ROB_DEPTH = 32;
localparam ROB_IDX_W = $clog2(ROB_DEPTH);
typedef logic [ROB_IDX_W-1:0] rob_idx_t;

typedef enum logic [6:0] {
        op_b_lui       = 7'b0110111, // load upper immediate (U type)
        op_b_auipc     = 7'b0010111, // add upper immediate PC (U type)
        op_b_jal       = 7'b1101111, // jump and link (J type)
        op_b_jalr      = 7'b1100111, // jump and link register (I type)
        op_b_br        = 7'b1100011, // branch (B type)
        op_b_load      = 7'b0000011, // load (I type)
        op_b_store     = 7'b0100011, // store (S type)
        op_b_imm       = 7'b0010011, // arith ops with register/immediate operands (I type)
        op_b_reg       = 7'b0110011  // arith ops with register operands (R type)
        // op_b_mul       = 7'b0110011  //Multiply extension opcode (R type) same as above one need to check in decode
    } rv32i_opcode;


    typedef enum logic [2:0] {
        arith_f3_add   = 3'b000, // check logic 30 for sub if op_reg op
        arith_f3_sll   = 3'b001,
        arith_f3_slt   = 3'b010,
        arith_f3_sltu  = 3'b011,
        arith_f3_xor   = 3'b100,
        arith_f3_sr    = 3'b101, // check logic 30 for logical/arithmetic
        arith_f3_or    = 3'b110,
        arith_f3_and   = 3'b111
    } arith_f3_t;


    typedef enum logic [2:0] {
        load_f3_lb     = 3'b000,
        load_f3_lh     = 3'b001,
        load_f3_lw     = 3'b010,
        load_f3_lbu    = 3'b100,
        load_f3_lhu    = 3'b101
    } load_f3_t;

    typedef enum logic [2:0] {
        mul_default= 3'b000,
        mul_high = 3'b001,
        mul_high_s_u = 3'b010,
        mul_high_u = 3'b011,
        div_default = 3'b100,
        div_u = 3'b101,
        rem_default = 3'b110,
        rem_u = 3'b111
    }   mul_div_rem_f3_t;


    typedef enum logic [2:0] {
        store_f3_sb    = 3'b000,
        store_f3_sh    = 3'b001,
        store_f3_sw    = 3'b010
    } store_f3_t;


    typedef enum logic [2:0] {
        branch_f3_beq  = 3'b000,
        branch_f3_bne  = 3'b001,
        branch_f3_blt  = 3'b100,
        branch_f3_bge  = 3'b101,
        branch_f3_bltu = 3'b110,
        branch_f3_bgeu = 3'b111
    } branch_f3_t;


    typedef enum logic [3:0] {
        alu_op_add     = 4'b0000,
        alu_op_sll     = 4'b0001,
        alu_op_sra     = 4'b0010,
        alu_op_sub     = 4'b0011,
        alu_op_xor     = 4'b0100,
        alu_op_srl     = 4'b0101,
        alu_op_or      = 4'b0110,
        alu_op_and     = 4'b0111,
        alu_op_slt     = 4'b1000,
        alu_op_sltu    = 4'b1001,
        alu_op_auipc   = 4'b1010,
        alu_op_lui     = 4'b1011,
        alu_op_store   = 4'b1100,
        alu_op_jalr    = 4'b1101,
        alu_op_jal     = 4'b1110
    } alu_ops;


    typedef enum logic [1:0] {
    alu = 2'b00,
    mul = 2'b01,
    div = 2'b10,
    rem = 2'b11
    } fsu;


    typedef union packed {
        logic [31:0] word;


        struct packed {
            logic [11:0] i_imm;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } i_type;


        struct packed {
            logic [6:0]  funct7;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } r_type;


        struct packed {
            logic [11:5] imm_s_top;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  imm_s_bot;
            rv32i_opcode opcode;
        } s_type;

        struct packed {
            logic imm12;
            logic [10:5] imm_b_top;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:1] imm_b_bottom;
            logic imm11;
            rv32i_opcode opcode;
        } b_type;


        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } j_type;


        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } u_type;


    } instr_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] predicted_pc;
        instr_t inst;
        tage_meta_t bp_meta;
    } iq_package;

        typedef struct packed {
        logic        valid;
        logic [4:0]  rs1_arch;
        logic [4:0]  rs2_arch;
        logic [4:0]  rd_arch;
        logic [3:0]  alu_op;
        logic [1:0]  sign; //indicates whether each operand of the mul/div/remainder operations will be signed or unsigned. 1 = signed, 0 = unsigned.
        logic        imm_instr;// 0 means rs2 1 means immediate
        logic        alu_src1_is_pc;
        logic        alu_src2_is_4;
        logic        mul_h; //indicates whether this is a high or low multiply instruction, 1 means high, 0 means low
        logic [31:0] imm; //if it is an immediate instruction we will output the immediate value for the RS
        logic [1:0]  fsu; // will be used to determine which FSU to send the instruction to // 00 alu, 01 mul, 10 div
        logic        branch;
        logic [2:0]  branch_op;
        logic        jal;
        logic        jalr;
        logic        store;
        logic [2:0]  store_op;
        logic        load;
        logic [2:0]  load_op;
    } decode_package;

 typedef struct packed{
        logic [31:0] pc;
        logic [31:0] predicted_pc;
        logic [31:0] inst;
        decode_package decode_package_out;
        logic valid;
        logic [5:0] rs1_phys;
        logic [5:0] rs2_phys;
        logic [5:0] rd_phys;
        logic rs1_ready;
        logic operand2_ready;
        rob_idx_t rob_idx;
        
        logic [3:0]  lq_idx;
        logic [3:0]  sq_idx;
        logic        is_load;
        logic        is_store;
        tage_meta_t bp_meta;
    } rs_entry;


typedef struct packed{
        rs_entry rs_entry_out;
        logic issue_valid;
        logic [31:0] pc_wdata;
        logic [31:0] rs1_v; 
        logic [31:0] rs2_v;
    } issue_exec_reg_t;

typedef struct packed {
    logic            valid;
    logic            addr_ready;
    logic            issued;
    logic [31:0]     addr;
    logic [3:0]      rmask;
    logic [5:0]      rd_phys;
    logic [4:0] rd_arch;
    rob_idx_t      rob_idx;
    logic [2:0]      load_op;
    logic [31:0]     raw_rdata;
    issue_exec_reg_t issue_exec_reg;
} load_queue_entry_t;

    typedef struct packed {
    logic        valid;
    logic        addr_ready;
    logic        data_ready;
    logic        committed;
    logic        issued;
    logic [31:0] addr;
    logic [3:0]  wmask;
    logic [31:0] data;
    rob_idx_t  rob_idx;
    logic [2:0]  store_op;
} store_queue_entry_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] pc_wdata;
        logic [31:0] inst;

        logic [31:0] rs1_rdata;
        logic [31:0] rs2_rdata;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;

        logic        regf_we;
        logic [31:0] rd_wdata;

        logic [31:0] mem_addr;
        logic [3:0]  mem_rmask;
        logic [3:0]  mem_wmask;
        logic [31:0] mem_rdata;
        logic [31:0] mem_wdata;
    } commit_entry_t;

    typedef struct packed {
    //rv32i_opcode opcode;
    logic [4:0]  rd_arch;
    logic [5:0]  new_rd_phys;
    logic [5:0]  old_rd_phys;
    logic        ready;
    logic        valid;
    commit_entry_t commit_data;

    logic        is_store;
    logic [3:0]  sq_idx;
    tage_meta_t  bp_meta;
   
    //logic        reg_write;
    //logic        is_store;
    //logic        is_branch;
    } rob_entry_t;
    

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] inst;
        logic [31:0] predicted_pc;
        logic valid;
        tage_meta_t bp_meta;
    } if_id_reg_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] inst;
        logic [31:0] predicted_pc;
        logic        valid;
        decode_package decode_package_out;
        tage_meta_t bp_meta;
    } id_rename_reg_t;


    typedef struct packed{
        rs_entry rs_entry_in;
        rob_idx_t rob_idx;
        logic valid;
    }   dispatch_issue_reg_t;

    typedef struct packed{
        logic [31:0] pc_wdata;
        issue_exec_reg_t issue_exec_reg;
        logic [65:0] product;
        logic [31:0] aluout;
        logic [31:0] quotient;
        logic [31:0] remainder;
        logic  divide_by_0;
        logic [31:0] rs1_v;
        logic [31:0] rs2_v;
        } fsu_reg_t;
    

    typedef struct packed{
        fsu_reg_t reg_out;
    } writeback_reg_t;
    




endpackage