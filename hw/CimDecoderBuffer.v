module CimDecoderBuffer  #(
    parameter DEPTH = 16) (
    input [DEPTH - 1:0]WRWL,
    output [DEPTH - 1:0]BUFFWRWL
);

    genvar i;
    for (i = 0;i < DEPTH;i = i + 1) begin:BUFF
        BUFFD8BWP30P140HVT BUFF(.I(WRWL[i]), .Z(BUFFWRWL[i]));
    end

endmodule

/*
No else explanation, just a buffer. 
*/