// DualAdderTree: sign-magnitude dual adder tree for 16 LUT lookup results.
//
// Each of the 16 inputs is a sign-magnitude pair {sign, mag[9:0]}.
// - If sign=0: value is positive → accumulate into POS tree
// - If sign=1: value is negative → accumulate into NEG tree (using magnitude)
// Output = POS_sum - NEG_sum (32-bit signed).
//
// POS/NEG trees sum up to 16 × 10-bit unsigned values:
//   Max per-tree sum = 16 × 765 = 12,240 → 14-bit (12240 < 16384 = 2^14)
// Result range: -12,240 .. +12,240 → fits in 15 bits signed; output as 32-bit.

module DualAdderTree #(
    parameter int N = 16        // number of input groups
)(
    // Packed SM inputs: {sign[0], mag[9:0]} × N = 11 bits × 16
    input  var logic [10:0]          sm_in [0:N-1],

    output var logic signed [31:0]   result
);
    // Unpack and route to POS / NEG arrays
    logic [9:0]  pos_in [0:N-1];    // positive contributions (zero if sign=1)
    logic [9:0]  neg_in [0:N-1];    // negative contributions (zero if sign=0)

    for (genvar i = 0; i < N; i++) begin : ROUTE
        assign pos_in[i] = sm_in[i][10] ? 10'd0 : sm_in[i][9:0];
        assign neg_in[i] = sm_in[i][10] ? sm_in[i][9:0] : 10'd0;
    end

    // POS tree: sum of N unsigned 10-bit values → 16-bit
    logic [15:0] pos_sum;
    always_comb begin
        pos_sum = '0;
        for (int i = 0; i < N; i++) pos_sum += {6'b0, pos_in[i]};
    end

    // NEG tree: sum of N unsigned 10-bit values → 16-bit
    logic [15:0] neg_sum;
    always_comb begin
        neg_sum = '0;
        for (int i = 0; i < N; i++) neg_sum += {6'b0, neg_in[i]};
    end

    // Final subtraction: sign-extend to 32 bits
    assign result = $signed({16'b0, pos_sum}) - $signed({16'b0, neg_sum});

endmodule: DualAdderTree
