// ZpSplitter: splits 3 INT8 activations into H4/L4, compares with ZP_H4,
// computes delta = H4 - ZP_H4 for each activation.
//
// One instance per weight group (3 activations per group).
// Used to determine whether the ZP-optimized LUT path applies.

module ZpSplitter (
    input  var logic [7:0]  act0,       // INT8 activation 0 (signed 2C)
    input  var logic [7:0]  act1,       // INT8 activation 1
    input  var logic [7:0]  act2,       // INT8 activation 2
    input  var logic [7:0]  zp,         // zero point (unsigned 8-bit)

    output var logic [3:0]  h4_0,       // high 4 bits of act0
    output var logic [3:0]  l4_0,       // low  4 bits of act0
    output var logic [3:0]  h4_1,
    output var logic [3:0]  l4_1,
    output var logic [3:0]  h4_2,
    output var logic [3:0]  l4_2,

    // delta = H4 - ZP_H4 (signed 4-bit, range -8..+7)
    output var logic signed [4:0] delta0,
    output var logic signed [4:0] delta1,
    output var logic signed [4:0] delta2,

    output var logic        is_zp0,     // h4_0 == zp[7:4]
    output var logic        is_zp1,
    output var logic        is_zp2,
    output var logic        all_zp      // all three match ZP_H4
);
    logic [3:0] zp_h4;
    assign zp_h4 = zp[7:4];

    // Split H4 / L4
    assign h4_0 = act0[7:4];
    assign l4_0 = act0[3:0];
    assign h4_1 = act1[7:4];
    assign l4_1 = act1[3:0];
    assign h4_2 = act2[7:4];
    assign l4_2 = act2[3:0];

    // ZP match flags
    assign is_zp0 = (h4_0 == zp_h4);
    assign is_zp1 = (h4_1 == zp_h4);
    assign is_zp2 = (h4_2 == zp_h4);
    assign all_zp = is_zp0 & is_zp1 & is_zp2;

    // delta = H4 - ZP_H4 (5-bit signed to avoid overflow)
    assign delta0 = $signed({1'b0, h4_0}) - $signed({1'b0, zp_h4});
    assign delta1 = $signed({1'b0, h4_1}) - $signed({1'b0, zp_h4});
    assign delta2 = $signed({1'b0, h4_2}) - $signed({1'b0, zp_h4});

endmodule: ZpSplitter
