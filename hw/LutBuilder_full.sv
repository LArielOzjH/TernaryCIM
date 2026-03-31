// LutBuilder_full: ablation baseline for LutBuilder.
// Builds 8 flag=0 LUT entries using the FULL 8-bit activation values instead
// of the L4 (low-nibble) values used by LutBuilder.
//
// Architecture delta vs LutBuilder:
//   - src0/1/2 = {2'b0, act0/1/2}  (10-bit, act is 8-bit unsigned)
//     instead of {6'b0, l4_0/1/2}  (10-bit, L4 is 4-bit)
//   - l4_0/1/2, all_zp inputs removed (not needed)
//   - No ZpCompensate path: LUT already encodes the full W·act contribution
//
// Consequence:
//   - Each entry has value range 0..3×255 = 765 → needs 10 bits (vs 6 for L4-only)
//   - lut_reg upper bits are now meaningful (vs always-zero in LutBuilder)
//   - Asymmetric ZP cannot be supported without an external -ZP×Σw correction

module LutBuilder_full (
    input  var logic [7:0]  act0,       // uint8 activation for position 0
    input  var logic [7:0]  act1,       // uint8 activation for position 1
    input  var logic [7:0]  act2,       // uint8 activation for position 2

    // Flag=0 SM entries, indexed [0..7].
    // Bit 10 = sign (always 0), bits [9:0] = magnitude.
    output var logic [10:0] entry [0:7]
);
    // Source values: full 8-bit activations (zero-extended to 10 bits)
    logic [9:0] src0, src1, src2;
    assign src0 = {2'b0, act0};
    assign src1 = {2'b0, act1};
    assign src2 = {2'b0, act2};

    // entry[d]: sign=0, magnitude = conditional sum of sources
    always_comb begin
        entry[0] = 11'd0;
        entry[1] = {1'b0, src0};
        entry[2] = {1'b0, src1};
        entry[3] = {1'b0, src0 + src1};
        entry[4] = {1'b0, src2};
        entry[5] = {1'b0, src0 + src2};
        entry[6] = {1'b0, src1 + src2};
        entry[7] = {1'b0, src0 + src1 + src2};
    end

endmodule: LutBuilder_full
