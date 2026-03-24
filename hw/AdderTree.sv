module AdderTree#(
    parameter int N = 8
) (
    input  var logic signed [N*17 - 1 : 0]          in,
    // input  var logic                                cim_mode, // KEEP/MERGE
    output var logic signed [31 : 0]                sum
);


    always_comb begin
        sum = '0;
        for (int i = 0; i < N; i = i + 1) begin
            sum += $signed(in[17*i +: 17]);
        end
    end

endmodule: AdderTree


// change to N = 16, DEPTH = 32, WIDTH = 128