// WeightPopcount: derives the algebraic sum of ternary weights from 5-bit encoding.
//
// 5-bit weight code = {sign[4], flag[3], data[2:0]}
// popcount = Σ w_i  where w_i ∈ {-1, 0, +1}
//
// Flag=0 (weights are 0 or +1): popcount = bit_count(data), range [0, 3]
// Flag=1 (weights contain -1):  popcount = (+1 count) - (-1 count), range [-2, +2]
//   data encodings for flag=1:
//     data=000: (0,+1,-1)  → (+1 count=1) - (-1 count=1) = 0
//     data=001: (+1,0,-1)  → 1 - 1 = 0
//     data=010: (+1,-1,0)  → 1 - 1 = 0
//     data=011: (+1,-1,+1) → 2 - 1 = +1
//     data=100: (+1,+1,-1) → 2 - 1 = +1
//     data=101: (+1,-1,-1) → 1 - 2 = -1
//
// Special: {flag,data}==4'b1111 (all-zero group) → popcount = 0
// If sign=1: negate popcount (mirror of whole group)
//
// Output: 4-bit signed, range [-3, +3] (sign-magnitude of weight sum).

module WeightPopcount (
    input  var logic [4:0]          weight_code,    // {sign[4], flag[3], data[2:0]}
    output var logic signed [3:0]   popcount        // Σ w_i, signed, range -3..+3
);
    logic        grp_sign;
    logic        flag_bit;
    logic [2:0]  data;

    assign grp_sign = weight_code[4];
    assign flag_bit = weight_code[3];
    assign data     = weight_code[2:0];

    logic signed [3:0] raw_popcount;

    always_comb begin
        if (weight_code[3:0] == 4'b1111) begin
            // All-zero group
            raw_popcount = 4'sd0;
        end else if (!flag_bit) begin
            // Flag=0: popcount = number of 1-bits in data
            raw_popcount = $signed({3'b0, data[0]})
                         + $signed({3'b0, data[1]})
                         + $signed({3'b0, data[2]});
        end else begin
            // Flag=1: fixed popcount per data pattern
            case (data)
                3'd0: raw_popcount = 4'sd0;   // (0,+1,-1)  → 0
                3'd1: raw_popcount = 4'sd0;   // (+1,0,-1)  → 0
                3'd2: raw_popcount = 4'sd0;   // (+1,-1,0)  → 0
                3'd3: raw_popcount = 4'sd1;   // (+1,-1,+1) → +1
                3'd4: raw_popcount = 4'sd1;   // (+1,+1,-1) → +1
                3'd5: raw_popcount = -4'sd1;  // (+1,-1,-1) → -1
                default: raw_popcount = 4'sd0;
            endcase
        end
    end

    // Apply group sign: if sign=1, negate (mirror)
    assign popcount = grp_sign ? -raw_popcount : raw_popcount;

endmodule: WeightPopcount
