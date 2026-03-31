// CimMacro_naive.sv
// Ablation-study baseline: same ZP/adder architecture as CimMacro, but uses a
// full 16-entry LUT (one entry per 4-bit {fl,dt} sub-code) instead of the
// 8-entry H4/L4-optimised LUT.
//
// The sign bit (wcode[4]=gs) is NOT stored in the LUT — it is applied at lookup
// by XORing the stored sign-magnitude sign bit:
//   sm_in[i] = { lut_reg[i][wcode[3:0]][10] ^ wcode[4],
//                lut_reg[i][wcode[3:0]][9:0] }
//
// Architecture delta vs CimMacro:
//   - No LutBuilder / LutLookup modules
//   - lut_reg: [N_GROUPS][16][10:0]  (16 entries, 4-bit index {fl,dt}, vs 8 entries)
//   - LUT entry p (gs=0 implicit) = w0×l4_0 + w1×l4_1 + w2×l4_2  (sign-mag)
//     where {w0,w1,w2} decoded from {gs=0, p[3]=fl, p[2:0]=dt}
//   - ZpSplitter, DualAdderTree, ZpCompensate, OutReg: IDENTICAL to CimMacro
//
// FF count comparison:
//   CimMacro      : lut_reg = 16×8×6   =  768 FF  (H4/L4 trick: 3-bit index)
//   CimMacro_naive: lut_reg = 16×16×7  = 1792 FF  (no H4/L4: 4-bit index)

`timescale 1ns/1ps

module CimMacro_naive #(
    parameter int N_GROUPS   = 16,
    parameter int DEPTH      = 32,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  var logic                        clk,
    input  var logic                        reset,

    // SRAM write interface
    input  var logic                        cim_wen,
    input  var logic [ADDR_WIDTH-1:0]       cim_waddr,
    input  var logic [5*N_GROUPS-1:0]       cim_wdata,

    // Activation + ZP (pulse act_valid to latch and build LUTs)
    input  var logic [24*N_GROUPS-1:0]      act_in,
    input  var logic [7:0]                  zp_in,
    input  var logic                        act_valid,

    // Weight read interface
    input  var logic                        cim_ren,
    input  var logic [ADDR_WIDTH-1:0]       cim_raddr,

    output var logic [31:0]                 cim_odata,
    output var logic                        cim_odata_valid
);

    // -----------------------------------------------------------------------
    // cim_ren pipeline register
    // -----------------------------------------------------------------------
    logic cim_ren_reg;
    always_ff @(posedge clk, posedge reset) begin
        if (reset) cim_ren_reg <= '0;
        else       cim_ren_reg <= cim_ren;
    end

    // -----------------------------------------------------------------------
    // SRAM: 32 × 80 weight storage (identical to CimMacro)
    // -----------------------------------------------------------------------
    logic [5*N_GROUPS-1:0] w_out;

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
    // Per-group activation split (identical to CimMacro)
    // ZpSplitter kept: provides l4_j for LUT build, delta_j for ZpCompensate
    // -----------------------------------------------------------------------
    logic [3:0]          zp_h4_comb;
    assign zp_h4_comb = zp_in[7:4];

    logic [7:0]          act0_in [0:N_GROUPS-1];
    logic [7:0]          act1_in [0:N_GROUPS-1];
    logic [7:0]          act2_in [0:N_GROUPS-1];

    logic [3:0]          l4_0_comb [0:N_GROUPS-1];
    logic [3:0]          l4_1_comb [0:N_GROUPS-1];
    logic [3:0]          l4_2_comb [0:N_GROUPS-1];
    logic signed [4:0]   delta0_comb [0:N_GROUPS-1];
    logic signed [4:0]   delta1_comb [0:N_GROUPS-1];
    logic signed [4:0]   delta2_comb [0:N_GROUPS-1];
    logic                all_zp_comb [0:N_GROUPS-1];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_ZP_SPLIT
        assign act0_in[i] = act_in[24*i    +: 8];
        assign act1_in[i] = act_in[24*i+8  +: 8];
        assign act2_in[i] = act_in[24*i+16 +: 8];

        ZpSplitter uZpSplit (
            .act0   (act0_in[i]),
            .act1   (act1_in[i]),
            .act2   (act2_in[i]),
            .zp     (zp_in),
            .h4_0   (),   .l4_0 (l4_0_comb[i]),
            .h4_1   (),   .l4_1 (l4_1_comb[i]),
            .h4_2   (),   .l4_2 (l4_2_comb[i]),
            .delta0 (delta0_comb[i]),
            .delta1 (delta1_comb[i]),
            .delta2 (delta2_comb[i]),
            .is_zp0 (),
            .is_zp1 (),
            .is_zp2 (),
            .all_zp (all_zp_comb[i])
        );
    end

    // -----------------------------------------------------------------------
    // Full 16-entry LUT build (combinational)
    // Index p = {fl[3], dt[2:0]} = wcode[3:0] (sign bit gs stripped).
    // gs=0 is assumed during build; gs is applied at lookup via sign-bit XOR.
    // Entry = w0×l4_0[i] + w1×l4_1[i] + w2×l4_2[i]  decoded with gs=0.
    // Stored as sign-magnitude (7-bit: {sign[6], mag[5:0]}; max magnitude = 45).
    // -----------------------------------------------------------------------
    logic [6:0] lut_comb_naive [0:N_GROUPS-1][0:15];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_LUT_GROUP
        for (genvar p = 0; p < 16; p++) begin : GEN_LUT_ENTRY
            // p = {fl[3], dt[2:0]}, gs=0 implicit
            // Identical decode logic as CimMacro GEN_LOOKUP, but without sign flip
            logic signed [1:0] bw0, bw1, bw2;
            always_comb begin
                // All-zero code: p[3:0] == 4'b1111
                if (p[3:0] == 4'b1111) begin
                    bw0 = 2'sb00; bw1 = 2'sb00; bw2 = 2'sb00;
                end else if (!p[3]) begin
                    // flag=0: each data bit selects 0 or +1
                    bw0 = p[0] ? 2'sb01 : 2'sb00;
                    bw1 = p[1] ? 2'sb01 : 2'sb00;
                    bw2 = p[2] ? 2'sb01 : 2'sb00;
                end else begin
                    // flag=1: fixed patterns per data[2:0]
                    case (p[2:0])
                        3'd0: begin bw0=2'sb00; bw1=2'sb01; bw2=2'sb11; end
                        3'd1: begin bw0=2'sb01; bw1=2'sb00; bw2=2'sb11; end
                        3'd2: begin bw0=2'sb01; bw1=2'sb11; bw2=2'sb00; end
                        3'd3: begin bw0=2'sb01; bw1=2'sb11; bw2=2'sb01; end
                        3'd4: begin bw0=2'sb01; bw1=2'sb01; bw2=2'sb11; end
                        3'd5: begin bw0=2'sb01; bw1=2'sb11; bw2=2'sb11; end
                        default: begin bw0=2'sb00; bw1=2'sb00; bw2=2'sb00; end
                    endcase
                    // gs=0: no sign flip applied here
                end
            end

            // Dot product with L4 (7-bit signed, range ±45)
            logic signed [6:0] entry_val;
            assign entry_val = $signed(bw0) * $signed({1'b0, l4_0_comb[i]})
                             + $signed(bw1) * $signed({1'b0, l4_1_comb[i]})
                             + $signed(bw2) * $signed({1'b0, l4_2_comb[i]});

            // Sign-magnitude conversion (7-bit: {sign[6], mag[5:0]}; max magnitude = 45)
            assign lut_comb_naive[i][p] = entry_val[6]
                ? {1'b1, 6'(-entry_val)}
                : {1'b0, 6'(entry_val)};
        end
    end

    // -----------------------------------------------------------------------
    // LUT registers: latch all 16 entries + ZP state on act_valid
    // (same structure as CimMacro, but 16 entries instead of 8)
    // -----------------------------------------------------------------------
    logic [3:0]          zp_h4_reg;
    logic signed [4:0]   delta0_reg [0:N_GROUPS-1];
    logic signed [4:0]   delta1_reg [0:N_GROUPS-1];
    logic signed [4:0]   delta2_reg [0:N_GROUPS-1];
    logic [6:0]          lut_reg    [0:N_GROUPS-1][0:15];

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            zp_h4_reg <= '0;
            for (int i = 0; i < N_GROUPS; i++) begin
                delta0_reg[i] <= '0;
                delta1_reg[i] <= '0;
                delta2_reg[i] <= '0;
                for (int e = 0; e < 16; e++) lut_reg[i][e] <= '0;
            end
        end else if (act_valid) begin
            zp_h4_reg <= zp_h4_comb;
            for (int i = 0; i < N_GROUPS; i++) begin
                delta0_reg[i] <= delta0_comb[i];
                delta1_reg[i] <= delta1_comb[i];
                delta2_reg[i] <= delta2_comb[i];
                for (int e = 0; e < 16; e++) lut_reg[i][e] <= lut_comb_naive[i][e];
            end
        end
    end

    // -----------------------------------------------------------------------
    // Per-group weight decode + direct LUT lookup + popcount
    // (combinational from w_out, identical to CimMacro except lookup)
    // -----------------------------------------------------------------------
    logic [4:0]          wcode [0:N_GROUPS-1];
    logic [10:0]         sm_in [0:N_GROUPS-1];
    logic signed [3:0]   popcount_arr [0:N_GROUPS-1];

    logic signed [1:0]   w0_arr [0:N_GROUPS-1];
    logic signed [1:0]   w1_arr [0:N_GROUPS-1];
    logic signed [1:0]   w2_arr [0:N_GROUPS-1];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_LOOKUP
        assign wcode[i] = w_out[5*i +: 5];

        // 4-bit indexed lookup (wcode[3:0] = {fl,dt}), sign applied via XOR
        // sm_in sign = stored sign XOR gs (wcode[4]); magnitude zero-extended to 10 bits
        assign sm_in[i] = {lut_reg[i][wcode[i][3:0]][6] ^ wcode[i][4],
                           4'b0, lut_reg[i][wcode[i][3:0]][5:0]};

        WeightPopcount uPopcount (
            .weight_code (wcode[i]),
            .popcount    (popcount_arr[i])
        );

        // Inline weight decoder for ZpCompensate (identical to CimMacro)
        logic        gs, fl;
        logic [2:0]  dt;
        assign gs = wcode[i][4];
        assign fl = wcode[i][3];
        assign dt = wcode[i][2:0];

        logic signed [1:0] rw0, rw1, rw2;
        always_comb begin
            if (wcode[i][3:0] == 4'b1111) begin
                rw0 = 2'sb00; rw1 = 2'sb00; rw2 = 2'sb00;
            end else if (!fl) begin
                rw0 = dt[0] ? 2'sb01 : 2'sb00;
                rw1 = dt[1] ? 2'sb01 : 2'sb00;
                rw2 = dt[2] ? 2'sb01 : 2'sb00;
            end else begin
                case (dt)
                    3'd0: begin rw0=2'sb00; rw1=2'sb01; rw2=2'sb11; end
                    3'd1: begin rw0=2'sb01; rw1=2'sb00; rw2=2'sb11; end
                    3'd2: begin rw0=2'sb01; rw1=2'sb11; rw2=2'sb00; end
                    3'd3: begin rw0=2'sb01; rw1=2'sb11; rw2=2'sb01; end
                    3'd4: begin rw0=2'sb01; rw1=2'sb01; rw2=2'sb11; end
                    3'd5: begin rw0=2'sb01; rw1=2'sb11; rw2=2'sb11; end
                    default: begin rw0=2'sb00; rw1=2'sb00; rw2=2'sb00; end
                endcase
            end
        end

        assign w0_arr[i] = gs ? -rw0 : rw0;
        assign w1_arr[i] = gs ? -rw1 : rw1;
        assign w2_arr[i] = gs ? -rw2 : rw2;
    end

    // -----------------------------------------------------------------------
    // SM Dual Adder Tree (identical to CimMacro)
    // -----------------------------------------------------------------------
    logic signed [31:0] raw_result;

    DualAdderTree #(.N(N_GROUPS)) uDualTree (
        .sm_in  (sm_in),
        .result (raw_result)
    );

    // -----------------------------------------------------------------------
    // ZP Compensation (identical to CimMacro — same module, same ports)
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
    // Final output (identical to CimMacro)
    // -----------------------------------------------------------------------
    logic signed [31:0] final_result;
    assign final_result = raw_result + zp_comp;

    OutReg uOutReg (
        .clock          (clk),
        .reset          (reset),
        .cim_ren        (cim_ren_reg),
        .odata          (final_result),
        .cim_odata_valid(cim_odata_valid),
        .cim_odata      (cim_odata)
    );

endmodule: CimMacro_naive
