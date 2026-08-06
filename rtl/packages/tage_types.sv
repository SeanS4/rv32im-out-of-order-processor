package tage_types;

    // Shared configuration for the area-reduced drop-in TAGE.
    // These values preserve the four-table organization and history lengths
    // while substantially reducing table depth and metadata width.
    localparam integer TAGE_NUM_TAGGED    = 4;
    localparam integer TAGE_INDEX_BITS    = 7;
    localparam integer TAGE_BASE_IDX_BITS = 11;
    localparam integer TAGE_TAG_BITS      = 9;

    typedef struct packed {
        logic [2:0]                     ctr;
        logic [TAGE_TAG_BITS-1:0]       tag;
        logic [1:0]                     u;
        logic                           valid;
    } tage_entry_t;

    typedef struct packed {
        logic [2:0] provider;
        logic       pred_taken;
        logic       alt_taken;

        // One saved prediction index per tagged component.
        logic [TAGE_NUM_TAGGED-1:0]
              [TAGE_INDEX_BITS-1:0] pred_idx;
    } tage_meta_t;

endpackage : tage_types
