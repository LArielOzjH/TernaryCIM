// CimMacro_noH4.sv
// Ablation baseline: same 8-entry flag=0 LUT + sign halving as CimMacro,
// but LUT entries are built from full 8-bit activations (not L4-only).
//
// Architecture delta vs CimMacro:
//   - LutBuilder     → LutBuilder_full  (src = full act, not L4)
//   - ZpSplitter     removed  (H4/L4 split not needed)
//   - delta*_reg     removed  (no H4 correction term)
//   - zp_h4_reg      removed
//   - ZpCompensate   removed  (final_result = raw_result directly)
//   - WeightPopcount removed  (only used by ZpCompensate)
//   - zp_in port     removed  (unused without ZP compensation)
//   - DualAdderTree, LutLookup, OutReg: IDENTICAL to CimMacro
//
// Only supports symmetric quantization (ZP = 0).
// For asymmetric ZP, an external -ZP×(Σ_i popcount_i) correction is needed.
//
// Register count:
//   lut_reg : 16×8×11 = 1408 FF  (same as CimMacro)
//   delta/zp: 0 FF               (CimMacro: 240 FF)
//   Total   : ~1408 FF vs ~1648 FF in CimMacro

`timescale 1ns/1ps

module CimMacro_noH4 #(
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

    // Activation (pulse act_valid to latch and build LUTs)
    // Note: no zp_in port — this design only supports symmetric quantization (ZP=0)
    input  var logic [24*N_GROUPS-1:0]      act_in,
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
    // SRAM: 32 × 80 weight storage
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
    // Per-group LUT build using full activations (no ZpSplitter)
    // -----------------------------------------------------------------------
    logic [7:0]  act0_in [0:N_GROUPS-1];
    logic [7:0]  act1_in [0:N_GROUPS-1];
    logic [7:0]  act2_in [0:N_GROUPS-1];

    logic [10:0] lut_comb [0:N_GROUPS-1][0:7];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_BUILD
        assign act0_in[i] = act_in[24*i    +: 8];
        assign act1_in[i] = act_in[24*i+8  +: 8];
        assign act2_in[i] = act_in[24*i+16 +: 8];

        LutBuilder_full uLutBuild (
            .act0  (act0_in[i]),
            .act1  (act1_in[i]),
            .act2  (act2_in[i]),
            .entry (lut_comb[i])
        );
    end

    // -----------------------------------------------------------------------
    // LUT registers: latch on act_valid (no delta/zp_h4 state)
    // -----------------------------------------------------------------------
    logic [10:0] lut_reg [0:N_GROUPS-1][0:7];

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            for (int i = 0; i < N_GROUPS; i++)
                for (int e = 0; e < 8; e++) lut_reg[i][e] <= '0;
        end else if (act_valid) begin
            for (int i = 0; i < N_GROUPS; i++)
                for (int e = 0; e < 8; e++) lut_reg[i][e] <= lut_comb[i][e];
        end
    end

    // -----------------------------------------------------------------------
    // Per-group weight decode + LUT lookup (combinational from w_out)
    // No WeightPopcount / w*_arr needed (ZpCompensate removed)
    // -----------------------------------------------------------------------
    logic [4:0]  wcode    [0:N_GROUPS-1];
    logic        out_sign [0:N_GROUPS-1];
    logic [9:0]  out_mag  [0:N_GROUPS-1];
    logic [10:0] sm_in    [0:N_GROUPS-1];

    for (genvar i = 0; i < N_GROUPS; i++) begin : GEN_LOOKUP
        assign wcode[i] = w_out[5*i +: 5];

        LutLookup uLookup (
            .weight_code (wcode[i]),
            .entry       (lut_reg[i]),
            .out_sign    (out_sign[i]),
            .out_mag     (out_mag[i])
        );

        assign sm_in[i] = {out_sign[i], out_mag[i]};
    end

    // -----------------------------------------------------------------------
    // SM Dual Adder Tree (same as CimMacro)
    // -----------------------------------------------------------------------
    logic signed [31:0] raw_result;

    DualAdderTree #(.N(N_GROUPS)) uDualTree (
        .sm_in  (sm_in),
        .result (raw_result)
    );

    // -----------------------------------------------------------------------
    // Final output: no ZP compensation (symmetric ZP=0 only)
    // -----------------------------------------------------------------------
    OutReg uOutReg (
        .clock          (clk),
        .reset          (reset),
        .cim_ren        (cim_ren_reg),
        .odata          (raw_result),
        .cim_odata_valid(cim_odata_valid),
        .cim_odata      (cim_odata)
    );

endmodule: CimMacro_noH4
