// LutBuilder: builds 8 flag=0 LUT entries from the L4 (low-nibble) values of
// 3 uint8 activations.
//
// The LUT ALWAYS uses L4 (act[3:0]).  ZpCompensate independently adds the H4
// contribution: Σ w_j × H4_j × 16 = (popcount × ZP_H4 + Σ w_j × delta_j) × 16.
// Together, raw_LUT_result + compensation = Σ w_j × (L4_j + H4_j × 16) = Σ w_j × act_j.
//
// This is correct for both ZP-mode groups (H4 = ZP_H4, delta = 0) and
// non-ZP-mode groups (H4 ≠ ZP_H4, delta ≠ 0).
//
// Each entry indexed by data[2:0] ∈ {0..7}:
//   entry[d] = Σ l4_i  for all i where d[i] = 1
//
// L4 max value = 15, so max entry magnitude = 3×15 = 45 → fits in 6 bits.
// Output: 6-bit unsigned magnitude per entry (no sign bit; entries always non-negative).
// Flag=1 entries are derived dynamically in LutLookup.

module LutBuilder (
    input  var logic [7:0]  act0,       // uint8 activation for position 0
    input  var logic [7:0]  act1,       // uint8 activation for position 1
    input  var logic [7:0]  act2,       // uint8 activation for position 2
    input  var logic [3:0]  l4_0,       // low nibble of act0 (from ZpSplitter)
    input  var logic [3:0]  l4_1,       // low nibble of act1
    input  var logic [3:0]  l4_2,       // low nibble of act2
    input  var logic        all_zp,     // 1=ZP mode (use L4); 0=full (use act)

    // Flag=0 LUT entries, indexed [0..7].
    // 6-bit unsigned magnitude (max 45); no sign bit needed.
    output var logic [5:0] entry [0:7]
);
    // Source values: always L4 (ZpCompensate handles the H4 term).
    // all_zp is kept as an input for connectivity but does not affect the output.
    logic [5:0] src0, src1, src2;
    assign src0 = {2'b0, l4_0};
    assign src1 = {2'b0, l4_1};
    assign src2 = {2'b0, l4_2};

    // entry[d]: magnitude = conditional sum of sources (max 45 < 64, no overflow)
    // Expanded explicitly to avoid tool-specific int-indexing issues.
    always_comb begin
        // d=000: no sources active → 0
        entry[0] = 6'd0;
        // d=001: only A0
        entry[1] = src0;
        // d=010: only A1
        entry[2] = src1;
        // d=011: A0 + A1
        entry[3] = src0 + src1;
        // d=100: only A2
        entry[4] = src2;
        // d=101: A0 + A2
        entry[5] = src0 + src2;
        // d=110: A1 + A2
        entry[6] = src1 + src2;
        // d=111: A0 + A1 + A2
        entry[7] = src0 + src1 + src2;
    end

endmodule: LutBuilder
