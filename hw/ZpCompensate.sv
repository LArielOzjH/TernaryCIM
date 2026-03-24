// ZpCompensate: accumulates the zero-point compensation term across 64 weight groups.
//
// For each group i:
//   W · A = W · (H4×16 + L4)
//         = popcount_i × H4_i × 16 + W · L4   (expanded)
//         = popcount_i × ZP_H4 × 16            (when H4_i == ZP_H4, absorbed into LUT)
//         + popcount_i × delta_i × 16           (delta_i = H4_i - ZP_H4 for each position)
//
// Because per-position H4 may differ, the per-group compensation is:
//   comp_i = popcount_i × ZP_H4 + Σ_j (w_j × delta_j)
// where the summation over j is the per-weight delta contribution.
//
// In practice, per-group delta sum = popcount_i × ZP_H4 +
//   Σ_j (w_j × (H4_j - ZP_H4)) = Σ_j w_j × H4_j
// which simplifies to just Σ_j w_j × H4_j.
//
// For hardware simplicity, we compute:
//   comp_total = Σ_i [ w_i0×H4_i0 + w_i1×H4_i1 + w_i2×H4_i2 ] × 16
// where w_ij ∈ {-1, 0, +1} is the j-th weight in group i.
//
// This is computed from:
//   - per-group popcount (signed, for the ZP_H4 term): popcount_i × ZP_H4
//   - per-group delta terms: w_j × delta_j for each of the 3 weight positions
//
// The delta_j for each activation position in the group comes from ZpSplitter.
// The individual weights w_j are decoded from the 5-bit weight code.
//
// Output: 32-bit signed compensation to add to DualAdderTree result (left-shifted by 4).

module ZpCompensate #(
    parameter int N = 64    // number of weight groups per row
)(
    // ZP info (common to all groups)
    input  var logic [3:0]          zp_h4,          // ZP[7:4]

    // Per-group inputs (arrays of N)
    input  var logic signed [3:0]   popcount [0:N-1],   // from WeightPopcount
    // Per-group per-position deltas (delta_j = H4_j - ZP_H4, signed 5-bit)
    input  var logic signed [4:0]   delta0   [0:N-1],   // delta for activation 0 of each group
    input  var logic signed [4:0]   delta1   [0:N-1],
    input  var logic signed [4:0]   delta2   [0:N-1],
    // Per-group per-position weights (decoded: 2-bit signed {-1,0,+1})
    // Encoded as 2-bit: 2'b01=+1, 2'b11=-1, 2'b00=0
    input  var logic signed [1:0]   w0       [0:N-1],   // ternary weight for position 0
    input  var logic signed [1:0]   w1       [0:N-1],
    input  var logic signed [1:0]   w2       [0:N-1],

    output var logic signed [31:0]  compensation    // to add to raw dot product result
);
    // Per-group H4 contribution: Σ_j w_j × H4_j = popcount×ZP_H4 + Σ_j w_j×delta_j
    // Bit widths:
    //   popcount×ZP_H4: 4-bit signed × 4-bit unsigned = 8-bit signed, range [-48, +48]
    //   w_j×delta_j: 2-bit signed × 5-bit signed = 7-bit signed, range [-15, +15]
    //   Per-group sum: up to 48 + 3×15 = 93 → 8-bit signed (fits in [-128,127])
    // Across 64 groups: max 64×93 = 5952 → 13-bit signed

    logic signed [8:0]  group_comp [0:N-1];

    for (genvar i = 0; i < N; i++) begin : GROUP_COMP
        logic signed [8:0] pc_term;
        logic signed [7:0] d_term;
        // popcount × ZP_H4
        assign pc_term = $signed(popcount[i]) * $signed({1'b0, zp_h4});
        // Σ w_j × delta_j (each w_j is 2-bit signed, delta is 5-bit signed → 7-bit product)
        assign d_term  = $signed(w0[i]) * $signed(delta0[i])
                       + $signed(w1[i]) * $signed(delta1[i])
                       + $signed(w2[i]) * $signed(delta2[i]);
        assign group_comp[i] = pc_term + $signed(d_term);  // sign-extend d_term to 9 bits
    end

    // Sum across all groups (13-bit sufficient)
    logic signed [20:0] total_comp;
    always_comb begin
        total_comp = '0;
        for (int i = 0; i < N; i++) total_comp += $signed({{12{group_comp[i][8]}}, group_comp[i]});
    end

    // Left-shift by 4 (×16) to get the H4 contribution in full precision
    // Then sign-extend to 32 bits
    assign compensation = $signed(total_comp) <<< 4;

endmodule: ZpCompensate
