// DualAdderTree_TC: ablation baseline for DualAdderTree.
// Converts each sign-magnitude input to 2's complement, then accumulates
// in a single signed adder tree.
//
// Architecture delta vs DualAdderTree:
//   - No POS/NEG routing split
//   - SM→TC conversion per input: tc = sign ? -mag : +mag (11-bit signed)
//   - Single always_comb accumulation with 32-bit sign extension
//
// Comparison:
//   DualAdderTree  : route mux + 10-bit unsigned trees + 1 subtract
//   DualAdderTree_TC: per-input TC conversion (negate) + 32-bit signed tree

`timescale 1ns/1ps

module DualAdderTree_TC #(
    parameter int N = 16
)(
    input  var logic [10:0]          sm_in [0:N-1],
    output var logic signed [31:0]   result
);
    // SM → TC conversion: sign=1 → negate magnitude (11-bit signed)
    logic signed [10:0] tc_val [0:N-1];

    for (genvar i = 0; i < N; i++) begin : CONV
        assign tc_val[i] = sm_in[i][10]
            ? $signed(-{1'b0, sm_in[i][9:0]})
            :  $signed( {1'b0, sm_in[i][9:0]});
    end

    // Single signed accumulation tree with 32-bit sign extension
    always_comb begin
        result = '0;
        for (int i = 0; i < N; i++)
            result += $signed({{21{tc_val[i][10]}}, tc_val[i]});
    end

endmodule: DualAdderTree_TC
