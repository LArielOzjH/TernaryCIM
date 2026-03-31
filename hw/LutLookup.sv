// LutLookup: given a 5-bit weight code and 8 stored flag=0 SM entries,
// produces the final SM output for that weight group.
//
// 5-bit weight code = {sign[4], flag[3], data[2:0]}
// - sign : group mirror — XOR with entry sign for final sign
// - flag : 0 = direct lookup; 1 = dynamic computation from flag=0 entries
// - data : 3-bit index for flag=0 lookup, or pattern selector for flag=1
//
// Special case: {flag,data} == 4'b1111 (i.e., all-zero weight group) → output 0.
//
// Flag=1 dynamic derivation (data[2:0] → weight pattern → two stored entries):
//   data=000: (0,+1,-1)  → entry[010] - entry[100]   = A1 - A2
//   data=001: (+1,0,-1)  → entry[001] - entry[100]   = A0 - A2
//   data=010: (+1,-1,0)  → entry[001] - entry[010]   = A0 - A1
//   data=011: (+1,-1,+1) → entry[101] - entry[010]   = (A0+A2) - A1
//   data=100: (+1,+1,-1) → entry[011] - entry[100]   = (A0+A1) - A2
//   data=101: (+1,-1,-1) → entry[001] - entry[110]   = A0 - (A1+A2)
//
// Entry format: 6-bit unsigned magnitude (no sign bit; flag=0 entries always non-negative).
// Output SM format: {out_sign, out_mag[9:0]}  (out_mag zero-extended from 6 bits).

module LutLookup (
    input  var logic [4:0]   weight_code,    // {sign[4], flag[3], data[2:0]}
    input  var logic [5:0]   entry [0:7],    // flag=0 stored 6-bit magnitude entries from LutBuilder

    output var logic         out_sign,       // final sign (after group sign XOR)
    output var logic [9:0]   out_mag         // final magnitude
);
    logic        grp_sign;
    logic        flag_bit;
    logic [2:0]  data;

    assign grp_sign = weight_code[4];
    assign flag_bit = weight_code[3];
    assign data     = weight_code[2:0];

    // All-zero: {flag,data} == 4'b1111 → output zero
    logic all_zero;
    assign all_zero = (weight_code[3:0] == 4'b1111);

    // --- Flag=0 path: direct lookup ---
    logic [5:0] direct_entry;
    assign direct_entry = entry[data];

    // --- Flag=1 path: dynamic computation ---
    // Each flag=1 case = (minuend entry) - (subtrahend entry)
    // Result may be negative; convert to SM.
    logic [5:0] minuend, subtrahend;
    always_comb begin
        case (data)
            3'd0: begin minuend = entry[3'b010]; subtrahend = entry[3'b100]; end // A1 - A2
            3'd1: begin minuend = entry[3'b001]; subtrahend = entry[3'b100]; end // A0 - A2
            3'd2: begin minuend = entry[3'b001]; subtrahend = entry[3'b010]; end // A0 - A1
            3'd3: begin minuend = entry[3'b101]; subtrahend = entry[3'b010]; end // (A0+A2) - A1
            3'd4: begin minuend = entry[3'b011]; subtrahend = entry[3'b100]; end // (A0+A1) - A2
            3'd5: begin minuend = entry[3'b001]; subtrahend = entry[3'b110]; end // A0 - (A1+A2)
            default: begin minuend = '0; subtrahend = '0; end  // unused (data=6,7 invalid for flag=1)
        endcase
    end

    // Entries are always non-negative, so magnitude = entry value directly.
    logic [5:0]  min_mag, sub_mag;
    assign min_mag = minuend;
    assign sub_mag = subtrahend;

    // SM result of (min_mag - sub_mag); max magnitude = 45, fits in 6 bits.
    logic        dyn_sign;
    logic [5:0]  dyn_mag;
    always_comb begin
        if (min_mag >= sub_mag) begin
            dyn_sign = 1'b0;
            dyn_mag  = min_mag - sub_mag;
        end else begin
            dyn_sign = 1'b1;
            dyn_mag  = sub_mag - min_mag;
        end
    end

    // --- Mux between paths ---
    logic        raw_sign;
    logic [9:0]  raw_mag;
    always_comb begin
        if (all_zero) begin
            raw_sign = 1'b0;
            raw_mag  = 10'd0;
        end else if (flag_bit) begin
            raw_sign = dyn_sign;
            raw_mag  = {4'b0, dyn_mag};    // zero-extend 6-bit result to 10 bits
        end else begin
            raw_sign = 1'b0;               // flag=0 entries always non-negative
            raw_mag  = {4'b0, direct_entry}; // zero-extend 6-bit entry to 10 bits
        end
    end

    // Apply group sign: final_sign = raw_sign XOR grp_sign
    assign out_sign = raw_sign ^ grp_sign;
    assign out_mag  = raw_mag;

endmodule: LutLookup
