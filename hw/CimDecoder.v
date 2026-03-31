
module CimDecoder #(
    parameter DEPTH      = 32,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input                   CK,
    input  [ADDR_WIDTH-1:0] ADDR,
    output [DEPTH-1:0]      WRWL
);
    wire [DEPTH-1:0] WL;

    genvar i;
    for (i = 0; i < DEPTH; i = i + 1) begin : DECODE
        assign WL[i] = (ADDR == i[ADDR_WIDTH-1:0]);
    end

    assign WRWL = CK ? WL : {DEPTH{1'b0}};

endmodule

/*
module CimDecoder #(parameter DEPTH = 32) (
    input CK,
    input [4:0] ADDR,  
    output [DEPTH-1:0] WRWL
);

    wire [DEPTH-1:0] WL;
    wire [3:0] a01, a23;
    wire [1:0] a4;  
    
    assign a01 = {ADDR[1]&ADDR[0],
                  ADDR[1]&(~ADDR[0]),
                  (~ADDR[1])&ADDR[0],
                  (~ADDR[1])&(~ADDR[0])};
    
    assign a23 = {ADDR[3]&ADDR[2],
                  ADDR[3]&(~ADDR[2]),
                  (~ADDR[3])&ADDR[2],
                  (~ADDR[3])&(~ADDR[2])};
    
    assign a4 = {ADDR[4], ~ADDR[4]};
    
    genvar i, j, k, m;
    for (m=0; m<2; m=m+1) begin
        for (i=0; i<4; i=i+1) begin
            for (j=0; j<4; j=j+1) begin
                assign WL[16*m+4*i+j] = a4[m] & a23[i] & a01[j];
            end
        end
    end
    
    assign WRWL = CK ? WL : 0;
    
endmodule
*/