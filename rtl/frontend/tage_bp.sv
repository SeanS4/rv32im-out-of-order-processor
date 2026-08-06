module tage_bp
import tage_types::*;

// Area-reduced configuration:
//   base table:   2048 entries
//   tagged tables: 4 x 128 entries
//   tag width:     9 bits
#(
    parameter integer NUM_TAGGED    = TAGE_NUM_TAGGED,
    parameter integer INDEX_BITS    = TAGE_INDEX_BITS,
    parameter integer BASE_IDX_BITS = TAGE_BASE_IDX_BITS,
    parameter integer TAG_BITS      = TAGE_TAG_BITS,
    parameter integer HISTORY_LEN   = 131,
    parameter integer PC_LEN        = 32
)
(
    input  logic               clk,
    input  logic               rst,
    input  logic [PC_LEN-1:0]  predict_pc,
    output logic               predict_taken,
    output tage_meta_t         predict_meta,
    input  logic               update_valid,
    input  logic [PC_LEN-1:0]  update_pc,
    input  logic               update_taken,
    input  tage_meta_t         update_meta
);

    logic [1:0]          base_table [1 << BASE_IDX_BITS];

    logic [2:0]          t_ctr   [NUM_TAGGED][1 << INDEX_BITS];
    logic [TAG_BITS-1:0] t_tag   [NUM_TAGGED][1 << INDEX_BITS];
    logic                t_valid [NUM_TAGGED][1 << INDEX_BITS];
    logic [1:0]          t_u     [NUM_TAGGED][1 << INDEX_BITS];

    logic [HISTORY_LEN-1:0] ghr;
    logic [INDEX_BITS-1:0]  ch_i  [NUM_TAGGED];
    logic [TAG_BITS-1:0]    ch_t1 [NUM_TAGGED];
    logic [TAG_BITS-2:0]    ch_t2 [NUM_TAGGED];

    logic [20:0] u_tick;

    typedef logic [2:0] provider_t;

    localparam provider_t BASE_TAG =
        provider_t'($unsigned(NUM_TAGGED));

    logic [INDEX_BITS-1:0]    pred_idx [NUM_TAGGED];
    logic [TAG_BITS-1:0]      pred_tag [NUM_TAGGED];
    logic [BASE_IDX_BITS-1:0] pred_base_idx;

    logic [INDEX_BITS-1:0]    upd_idx [NUM_TAGGED];
    logic [TAG_BITS-1:0]      upd_tag [NUM_TAGGED];
    logic [BASE_IDX_BITS-1:0] upd_base_idx;

    always_comb begin
        pred_base_idx = predict_pc[BASE_IDX_BITS+1:2];
        upd_base_idx  = update_pc[BASE_IDX_BITS+1:2];
        for (integer i = 0; i < NUM_TAGGED; i++) begin
            pred_idx[i] = predict_pc[INDEX_BITS+1:2] ^ ch_i[i];
            upd_idx[i]  = update_pc[INDEX_BITS+1:2]  ^ ch_i[i];
            pred_tag[i] = TAG_BITS'(predict_pc[TAG_BITS+1:2]) ^ ch_t1[i] ^ TAG_BITS'({ch_t2[i], 1'b0});
            upd_tag[i]  = TAG_BITS'(update_pc[TAG_BITS+1:2])  ^ ch_t1[i] ^ TAG_BITS'({ch_t2[i], 1'b0});
        end
    end

    logic [NUM_TAGGED-1:0] hit;

    always_comb begin
        for (integer i = 0; i < NUM_TAGGED; i++)
            hit[i] = t_valid[i][pred_idx[i]] &&
                     (t_tag[i][pred_idx[i]] == pred_tag[i]);
    end

    always_comb begin
        predict_meta          = '0;
        predict_meta.provider = BASE_TAG;
        predict_meta.alt_taken = base_table[pred_base_idx][1];
        predict_taken          = base_table[pred_base_idx][1];

        for (integer i = 0; i < NUM_TAGGED; i++) begin
            if (hit[i]) begin
                predict_meta.alt_taken = predict_taken;
                predict_meta.provider  = provider_t'($unsigned(i));
                predict_taken          = t_ctr[i][pred_idx[i]][2];
            end
        end

        predict_meta.pred_taken = predict_taken;

        for (integer i = 0; i < NUM_TAGGED; i++) begin
            predict_meta.pred_idx[i] = pred_idx[i];
        end
    end

    logic alloc_en  [NUM_TAGGED];
    logic decr_u_en [NUM_TAGGED];
    logic alloc_found;

    always_comb begin
        alloc_found = 1'b0;
        for (integer i = 0; i < NUM_TAGGED; i++) begin
            alloc_en[i]  = 1'b0;
            decr_u_en[i] = 1'b0;
        end

        if (update_valid && (update_taken != update_meta.pred_taken)) begin
            for (integer i = 0; i < NUM_TAGGED; i++) begin
                logic longer;
                longer = (update_meta.provider == BASE_TAG) ? 1'b1
                                                            : (provider_t'($unsigned(i))
                                                               > update_meta.provider);
                if (longer && !alloc_found) begin
                    if (!t_valid[i][update_meta.pred_idx[i]] ||
                        (t_u[i][update_meta.pred_idx[i]] == 2'b00)) begin
                        alloc_en[i]  = 1'b1;
                        alloc_found  = 1'b1;
                    end else begin
                        decr_u_en[i] = 1'b1;
                    end
                end
            end
        end
    end

    logic [INDEX_BITS-1:0] ch_i_next  [NUM_TAGGED];
    logic [TAG_BITS-1:0]   ch_t1_next [NUM_TAGGED];
    logic [TAG_BITS-2:0]   ch_t2_next [NUM_TAGGED];

    always_comb begin
        // T0
        ch_i_next[0]                   = {ch_i[0][INDEX_BITS-2:0],  update_taken};
        ch_i_next[0][0]               ^= ch_i[0][INDEX_BITS-1];
        ch_i_next[0][5 % INDEX_BITS]  ^= ghr[4];

        ch_t1_next[0]                  = {ch_t1[0][TAG_BITS-2:0],   update_taken};
        ch_t1_next[0][0]              ^= ch_t1[0][TAG_BITS-1];
        ch_t1_next[0][5 % TAG_BITS]   ^= ghr[4];

        ch_t2_next[0]                  = {ch_t2[0][TAG_BITS-3:0],   update_taken};
        ch_t2_next[0][0]              ^= ch_t2[0][TAG_BITS-2];
        ch_t2_next[0][5 % (TAG_BITS-1)] ^= ghr[4];

        // T1
        ch_i_next[1]                   = {ch_i[1][INDEX_BITS-2:0],  update_taken};
        ch_i_next[1][0]               ^= ch_i[1][INDEX_BITS-1];
        ch_i_next[1][15 % INDEX_BITS] ^= ghr[14];

        ch_t1_next[1]                  = {ch_t1[1][TAG_BITS-2:0],   update_taken};
        ch_t1_next[1][0]              ^= ch_t1[1][TAG_BITS-1];
        ch_t1_next[1][15 % TAG_BITS]  ^= ghr[14];

        ch_t2_next[1]                  = {ch_t2[1][TAG_BITS-3:0],   update_taken};
        ch_t2_next[1][0]              ^= ch_t2[1][TAG_BITS-2];
        ch_t2_next[1][15 % (TAG_BITS-1)] ^= ghr[14];

        // T2
        ch_i_next[2]                   = {ch_i[2][INDEX_BITS-2:0],  update_taken};
        ch_i_next[2][0]               ^= ch_i[2][INDEX_BITS-1];
        ch_i_next[2][44 % INDEX_BITS] ^= ghr[43];

        ch_t1_next[2]                  = {ch_t1[2][TAG_BITS-2:0],   update_taken};
        ch_t1_next[2][0]              ^= ch_t1[2][TAG_BITS-1];
        ch_t1_next[2][44 % TAG_BITS]  ^= ghr[43];

        ch_t2_next[2]                  = {ch_t2[2][TAG_BITS-3:0],   update_taken};
        ch_t2_next[2][0]              ^= ch_t2[2][TAG_BITS-2];
        ch_t2_next[2][44 % (TAG_BITS-1)] ^= ghr[43];

        // T3
        ch_i_next[3]                    = {ch_i[3][INDEX_BITS-2:0],  update_taken};
        ch_i_next[3][0]                ^= ch_i[3][INDEX_BITS-1];
        ch_i_next[3][130 % INDEX_BITS] ^= ghr[129];

        ch_t1_next[3]                   = {ch_t1[3][TAG_BITS-2:0],   update_taken};
        ch_t1_next[3][0]               ^= ch_t1[3][TAG_BITS-1];
        ch_t1_next[3][130 % TAG_BITS]  ^= ghr[129];

        ch_t2_next[3]                   = {ch_t2[3][TAG_BITS-3:0],   update_taken};
        ch_t2_next[3][0]               ^= ch_t2[3][TAG_BITS-2];
        ch_t2_next[3][130 % (TAG_BITS-1)] ^= ghr[129];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            ghr    <= '0;
            u_tick <= '0;

            for (integer i = 0; i < NUM_TAGGED; i++) begin
                ch_i[i]  <= '0;
                ch_t1[i] <= '0;
                ch_t2[i] <= '0;
            end

            for (integer e = 0; e < (1 << BASE_IDX_BITS); e++)
                base_table[e] <= 2'b01;

            // Reset only validity.  An invalid entry cannot hit, and the
            // allocation path initializes tag/counter/usefulness before the
            // entry becomes valid.  Avoiding reset muxes on the other fields
            // materially reduces area and reset-tree loading.
            for (integer t = 0; t < NUM_TAGGED; t++) begin
                for (integer e = 0; e < (1 << INDEX_BITS); e++) begin
                    t_valid[t][e] <= 1'b0;
                end
            end

        end else begin

            u_tick <= u_tick + 1'b1;

            if (u_tick == 21'h0FFFFF) begin
                for (integer t = 0; t < NUM_TAGGED; t++)
                    for (integer e = 0; e < (1 << INDEX_BITS); e++)
                        t_u[t][e][0] <= 1'b0;
            end

            if (u_tick == 21'h1FFFFF) begin
                for (integer t = 0; t < NUM_TAGGED; t++)
                    for (integer e = 0; e < (1 << INDEX_BITS); e++)
                        t_u[t][e][1] <= 1'b0;
            end

            if (update_valid) begin

                ghr <= {ghr[HISTORY_LEN-2:0], update_taken};

                for (integer i = 0; i < NUM_TAGGED; i++) begin
                    ch_i[i]  <= ch_i_next[i];
                    ch_t1[i] <= ch_t1_next[i];
                    ch_t2[i] <= ch_t2_next[i];
                end

                if (update_taken) begin
                    if (base_table[upd_base_idx] != 2'b11)
                        base_table[upd_base_idx] <= base_table[upd_base_idx] + 1'b1;
                end else begin
                    if (base_table[upd_base_idx] != 2'b00)
                        base_table[upd_base_idx] <= base_table[upd_base_idx] - 1'b1;
                end

                if (update_meta.provider != BASE_TAG) begin
                    if (update_taken) begin
                        if (t_ctr[update_meta.provider][update_meta.pred_idx[update_meta.provider]] != 3'b111)
                            t_ctr[update_meta.provider][update_meta.pred_idx[update_meta.provider]] <=
                                t_ctr[update_meta.provider][update_meta.pred_idx[update_meta.provider]] + 1'b1;
                    end else begin
                        if (t_ctr[update_meta.provider][update_meta.pred_idx[update_meta.provider]] != 3'b000)
                            t_ctr[update_meta.provider][update_meta.pred_idx[update_meta.provider]] <=
                                t_ctr[update_meta.provider][update_meta.pred_idx[update_meta.provider]] - 1'b1;
                    end

                    if (update_meta.pred_taken != update_meta.alt_taken) begin
                        if (update_taken == update_meta.pred_taken) begin
                            if (t_u[update_meta.provider][update_meta.pred_idx[update_meta.provider]] != 2'b11)
                                t_u[update_meta.provider][update_meta.pred_idx[update_meta.provider]] <=
                                    t_u[update_meta.provider][update_meta.pred_idx[update_meta.provider]] + 1'b1;
                        end else begin
                            if (t_u[update_meta.provider][update_meta.pred_idx[update_meta.provider]] != 2'b00)
                                t_u[update_meta.provider][update_meta.pred_idx[update_meta.provider]] <=
                                    t_u[update_meta.provider][update_meta.pred_idx[update_meta.provider]] - 1'b1;
                        end
                    end
                end

                for (integer i = 0; i < NUM_TAGGED; i++) begin
                    if (alloc_en[i]) begin
                        t_tag[i][update_meta.pred_idx[i]]   <= upd_tag[i];
                        t_ctr[i][update_meta.pred_idx[i]]   <= update_taken ? 3'b100 : 3'b011;
                        t_u[i][update_meta.pred_idx[i]]     <= 2'b00;
                        t_valid[i][update_meta.pred_idx[i]] <= 1'b1;
                    end else if (decr_u_en[i]) begin
                        if (t_u[i][update_meta.pred_idx[i]] != 2'b00)
                            t_u[i][update_meta.pred_idx[i]] <= t_u[i][update_meta.pred_idx[i]] - 1'b1;
                    end
                end

            end
        end
    end

endmodule : tage_bp