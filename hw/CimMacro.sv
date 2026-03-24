// CimMacro: top-level CIM macro for Ternary LLM (W1.58, A8) inference.
//
// Architecture:
//   - SRAM: DEPTH=128 rows × WIDTH=320 bits (64 groups × 5 bits/group, 5-pack-3 encoding)
//   - LUT phase (act_valid=1): latch 192 INT8 activations + ZP → build 64 per-group LUTs
//   - Compute phase (cim_ren=1): for each row read, perform
//       64× LUT lookup → SM Dual Adder Tree → ZP compensation → 32-bit output
//
// Activation bus layout (act_in[24*i +: 24] = group i):
//   group i: act_in[24*i +: 8] = act0_i, act_in[24*i+8 +: 8] = act1_i, act_in[24*i+16 +: 8] = act2_i
//
// Weight bus layout (w_out from CellArray):
//   group i: w_out[5*i +: 5] = {sign[4], flag[3], data[2:0]}
//
// Output: cim_odata valid one cycle after cim_ren.

module CimMacro #(
    parameter int N_GROUPS   = 64,
    parameter int DEPTH      = 128,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  var logic                        clk,
    input  var logic                        reset,

    // SRAM write interface
    input  var logic                        cim_wen,
    input  var logic [ADDR_WIDTH-1:0]       cim_waddr,
    input  var logic [5*N_GROUPS-1:0]       cim_wdata,      // 320-bit weight row

    // Activation + ZP (pulse act_valid to latch and build LUTs)
    input  var logic [24*N_GROUPS-1:0]      act_in,         // 64×3×8=1536-bit
    input  var logic [7:0]                  zp_in,          // unsigned zero point
    input  var logic                        act_valid,

    // Weight read interface
    input  var logic                        cim_ren,
    input  var logic [ADDR_WIDTH-1:0]       cim_raddr,

    output var logic [31:0]                 cim_odata,
    output var logic                        cim_odata_valid
);

    // -----------------------------------------------------------------------
    // cim_ren pipeline register: OutReg captures result one cycle after SRAM read
    // to avoid race condition between SRAM read and OutReg capture.
    // -----------------------------------------------------------------------
    logic cim_ren_reg;
    always_ff @(posedge clk, posedge reset) begin
        if (reset) cim_ren_reg <= '0;
        else       cim_ren_reg <= cim_ren;
    end

    // -----------------------------------------------------------------------
    // SRAM: 128 × 320 weight storage
    // -----------------------------------------------------------------------
    logic [5*N_GROUPS-1:0] w_out;   // raw 320-bit word from current row

    CellArray #(
        .DEPTH(DEPTH),
        .WIDTH(5*N_GROUPS)
    ) uCellArray (
        .clock      (clk),
        .cim_ren    (cim_ren),
        .cim_raddr  (cim_raddr),
        .cim_wen    (cim_wen),
        .cim_waddr  (cim_waddr),
        .cim_wdata  (cim_wdata),
        .w_out      (w_out)
    );

    // -----------------------------------------------------------------------
    // Per-group activation split and LUT build (combinational from act_in)
    // -----------------------------------------------------------------------
    logic [3:0]         zp_h4_comb;
    assign zp_h4_comb = zp_in[7:4];

    // Combinational outputs from ZpSplitter and LutBuilder per group
    logic [7:0]          act0_in [0:N_GROUPS-1];
    logic [7:0]          act1_in [0:N_GROUPS-1];
    logic [7:0]          act2_in [0:N_GROUPS-1];

    logic [3:0]          h4_0_comb [0:N_GROUPS-1];
    logic [3:0]          l4_0_comb [0:N_GROUPS-1];
    logic [3:0]          h4_1_comb [0:N_GROUPS-1];
    logic [3:0]          l4_1_comb [0:N_GROUPS-1];
    logic [3:0]          h4_2_comb [0:N_GROUPS-1];
    logic [3:0]          l4_2_comb [0:N_GROUPS-1];
    logic signed [4:0]   delta0_comb [0:N_GROUPS-1];
    logic signed [4:0]   delta1_comb [0:N_GROUPS-1];
    logic signed [4:0]   delta2_comb [0:N_GROUPS-1];
    logic                all_zp_comb [0:N_GROUPS-1];

    logic [10:0]         lut_comb [0:N_GROUPS-1][0:7];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_SPLIT_BUILD
        assign act0_in[i] = act_in[24*i    +: 8];
        assign act1_in[i] = act_in[24*i+8  +: 8];
        assign act2_in[i] = act_in[24*i+16 +: 8];

        ZpSplitter uZpSplit (
            .act0   (act0_in[i]),
            .act1   (act1_in[i]),
            .act2   (act2_in[i]),
            .zp     (zp_in),
            .h4_0   (h4_0_comb[i]),   .l4_0 (l4_0_comb[i]),
            .h4_1   (h4_1_comb[i]),   .l4_1 (l4_1_comb[i]),
            .h4_2   (h4_2_comb[i]),   .l4_2 (l4_2_comb[i]),
            .delta0 (delta0_comb[i]),
            .delta1 (delta1_comb[i]),
            .delta2 (delta2_comb[i]),
            .is_zp0 (),               // individual flags unused here
            .is_zp1 (),
            .is_zp2 (),
            .all_zp (all_zp_comb[i])
        );

        LutBuilder uLutBuild (
            .act0    (act0_in[i]),
            .act1    (act1_in[i]),
            .act2    (act2_in[i]),
            .l4_0    (l4_0_comb[i]),
            .l4_1    (l4_1_comb[i]),
            .l4_2    (l4_2_comb[i]),
            .all_zp  (all_zp_comb[i]),
            .entry   (lut_comb[i])
        );
    end

    // -----------------------------------------------------------------------
    // LUT registers: latch LUT entries and ZP state on act_valid
    // -----------------------------------------------------------------------
    logic [3:0]          zp_h4_reg;
    logic signed [4:0]   delta0_reg [0:N_GROUPS-1];
    logic signed [4:0]   delta1_reg [0:N_GROUPS-1];
    logic signed [4:0]   delta2_reg [0:N_GROUPS-1];
    logic [10:0]         lut_reg [0:N_GROUPS-1][0:7];

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            zp_h4_reg <= '0;
            for (int i = 0; i < N_GROUPS; i++) begin
                delta0_reg[i] <= '0;
                delta1_reg[i] <= '0;
                delta2_reg[i] <= '0;
                for (int e = 0; e < 8; e++) lut_reg[i][e] <= '0;
            end
        end else if (act_valid) begin
            zp_h4_reg <= zp_h4_comb;
            for (int i = 0; i < N_GROUPS; i++) begin
                delta0_reg[i] <= delta0_comb[i];
                delta1_reg[i] <= delta1_comb[i];
                delta2_reg[i] <= delta2_comb[i];
                for (int e = 0; e < 8; e++) lut_reg[i][e] <= lut_comb[i][e];
            end
        end
    end

    // -----------------------------------------------------------------------
    // Per-group weight decode + LUT lookup + popcount (combinational from w_out)
    // -----------------------------------------------------------------------
    logic [4:0]          wcode [0:N_GROUPS-1];     // 5-bit weight codes
    logic                out_sign [0:N_GROUPS-1];
    logic [9:0]          out_mag  [0:N_GROUPS-1];
    logic [10:0]         sm_in    [0:N_GROUPS-1];  // to DualAdderTree
    logic signed [3:0]   popcount_arr [0:N_GROUPS-1];

    // Per-group individual ternary weights for ZpCompensate (-1/0/+1 as 2-bit signed)
    logic signed [1:0]   w0_arr [0:N_GROUPS-1];
    logic signed [1:0]   w1_arr [0:N_GROUPS-1];
    logic signed [1:0]   w2_arr [0:N_GROUPS-1];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_LOOKUP
        assign wcode[i] = w_out[5*i +: 5];

        LutLookup uLookup (
            .weight_code (wcode[i]),
            .entry       (lut_reg[i]),
            .out_sign    (out_sign[i]),
            .out_mag     (out_mag[i])
        );

        assign sm_in[i] = {out_sign[i], out_mag[i]};

        WeightPopcount uPopcount (
            .weight_code (wcode[i]),
            .popcount    (popcount_arr[i])
        );

        // Inline weight decoder for ZpCompensate: decode w0/w1/w2 from wcode
        // Flag=0: w_j = sign ? (data[j]?-1:0) : (data[j]?+1:0)
        // Flag=1: fixed pattern per data, then negate if sign
        // All-zero: w0=w1=w2=0
        logic        gs, fl;
        logic [2:0]  dt;
        assign gs = wcode[i][4];
        assign fl = wcode[i][3];
        assign dt = wcode[i][2:0];

        logic signed [1:0] rw0, rw1, rw2;  // raw (before sign negation)
        always_comb begin
            if (wcode[i][3:0] == 4'b1111) begin
                rw0 = 2'sb00; rw1 = 2'sb00; rw2 = 2'sb00;
            end else if (!fl) begin
                // flag=0: each bit of data → 0 or +1
                rw0 = dt[0] ? 2'sb01 : 2'sb00;
                rw1 = dt[1] ? 2'sb01 : 2'sb00;
                rw2 = dt[2] ? 2'sb01 : 2'sb00;
            end else begin
                // flag=1: decode per data pattern
                case (dt)
                    3'd0: begin rw0=2'sb00; rw1=2'sb01; rw2=2'sb11; end // (0,+1,-1)
                    3'd1: begin rw0=2'sb01; rw1=2'sb00; rw2=2'sb11; end // (+1,0,-1)
                    3'd2: begin rw0=2'sb01; rw1=2'sb11; rw2=2'sb00; end // (+1,-1,0)
                    3'd3: begin rw0=2'sb01; rw1=2'sb11; rw2=2'sb01; end // (+1,-1,+1)
                    3'd4: begin rw0=2'sb01; rw1=2'sb01; rw2=2'sb11; end // (+1,+1,-1)
                    3'd5: begin rw0=2'sb01; rw1=2'sb11; rw2=2'sb11; end // (+1,-1,-1)
                    default: begin rw0=2'sb00; rw1=2'sb00; rw2=2'sb00; end
                endcase
            end
        end

        // Apply group sign (negate all weights if sign=1)
        assign w0_arr[i] = gs ? -rw0 : rw0;
        assign w1_arr[i] = gs ? -rw1 : rw1;
        assign w2_arr[i] = gs ? -rw2 : rw2;
    end

    // -----------------------------------------------------------------------
    // SM Dual Adder Tree
    // -----------------------------------------------------------------------
    logic signed [31:0] raw_result;

    DualAdderTree #(.N(N_GROUPS)) uDualTree (
        .sm_in  (sm_in),
        .result (raw_result)
    );

    // -----------------------------------------------------------------------
    // ZP Compensation
    // -----------------------------------------------------------------------
    logic signed [31:0] zp_comp;

    ZpCompensate #(.N(N_GROUPS)) uZpComp (
        .zp_h4       (zp_h4_reg),
        .popcount    (popcount_arr),
        .delta0      (delta0_reg),
        .delta1      (delta1_reg),
        .delta2      (delta2_reg),
        .w0          (w0_arr),
        .w1          (w1_arr),
        .w2          (w2_arr),
        .compensation(zp_comp)
    );

    // -----------------------------------------------------------------------
    // Final output: raw + ZP compensation → OutReg
    // -----------------------------------------------------------------------
    logic signed [31:0] final_result;
    assign final_result = raw_result + zp_comp;

    OutReg uOutReg (
        .clock          (clk),
        .reset          (reset),
        .cim_ren        (cim_ren_reg),   // registered: capture 1 cycle after SRAM read
        .odata          (final_result),
        .cim_odata_valid(cim_odata_valid),
        .cim_odata      (cim_odata)
    );

endmodule: CimMacro
