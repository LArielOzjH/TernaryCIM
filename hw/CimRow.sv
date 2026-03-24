module CimRow #(
    parameter int DEPTH = 128
)(
    input  var logic                      DIN, DINB, CKW, CKR, 
    input  var logic [DEPTH - 1 : 0]      RWL, WWL,
    output var logic                      HOT
);

    wire WBL, WBLN, RBL;

    WD7T uWD7T(.DIN(DIN), .DINB(DINB), .CKW(CKW), .WBL(WBL), .WBLN(WBLN));

    RA6T uRA6T(.RBL(RBL), .CKR(CKR), .ACT(1'b1), .ACTN(1'b0), .HOT(HOT));
    
    for (genvar i = 0; i < DEPTH; i += 1) begin: SRAM
        S8T1 uS8T1(.RWL(RWL[i]), .WWL(WWL[i]), .WBLN(WBLN), .WBL(WBL), .RBL(RBL));
    end

endmodule

/*
    CimRow defines the basic unit of the CimArray.
    It contains a WD7T, a RA6T, and DEPTH S8T1 cells.
    WD7T is used to write the data to the CimArray.
    RA6T is used to read the data from the CimArray.
    S8T1 is used to store the data in the CimArray.

    The expected array size is 16*(8*32), DEPTH is 16. WIDTH is 8*32=256.
    The data is stored in the CimArray in the following order:
    [0:7] [8:15] [16:23] [24:31] [32:39] [40:47] [48:55] [56:63]
    [64:71] [72:79] [80:87] [88:95] [96:103] [104:111] [112:119] [120:127]
    [128:135] [136:143] [144:151] [152:159] [160:167] [168:175] [176:183] [184:191]
    [192:199] [200:207] [208:215] [216:223] [224:231] [232:239] [240:247] [248:255]
*/