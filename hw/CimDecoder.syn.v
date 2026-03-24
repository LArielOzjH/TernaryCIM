/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : P-2019.03-SP5
// Date      : Fri Aug  4 10:29:23 2023
/////////////////////////////////////////////////////////////


module CimDecoder ( CK, ADDR, WRWL );
  input [3:0] ADDR;
  output [15:0] WRWL;
  input CK;
  wire   n12, n13, n14, n15, n16, n17, n18, n19, n20, n21, eco_net;

  OR2D1BWP30P140HVT U29 ( .A1(ADDR[1]), .A2(ADDR[2]), .Z(n21) );
  CKND0BWP30P140HVT U30 ( .I(ADDR[3]), .ZN(n15) );
  CKND0BWP30P140HVT U31 ( .I(ADDR[0]), .ZN(n12) );
  ND3D0BWP30P140HVT U32 ( .A1(eco_net), .A2(n15), .A3(n12), .ZN(n19) );
  NR2D0BWP30P140HVT U33 ( .A1(n21), .A2(n19), .ZN(WRWL[0]) );
  ND2D0BWP30P140HVT U34 ( .A1(ADDR[1]), .A2(ADDR[2]), .ZN(n16) );
  ND3D0BWP30P140HVT U35 ( .A1(ADDR[3]), .A2(eco_net), .A3(n12), .ZN(n13) );
  NR2D0BWP30P140HVT U36 ( .A1(n16), .A2(n13), .ZN(WRWL[14]) );
  IND2D0BWP30P140HVT U37 ( .A1(ADDR[1]), .B1(ADDR[2]), .ZN(n17) );
  ND3D0BWP30P140HVT U38 ( .A1(eco_net), .A2(ADDR[3]), .A3(ADDR[0]), .ZN(n14)
         );
  NR2D0BWP30P140HVT U39 ( .A1(n17), .A2(n14), .ZN(WRWL[13]) );
  NR2D0BWP30P140HVT U40 ( .A1(n17), .A2(n13), .ZN(WRWL[12]) );
  IND2D0BWP30P140HVT U41 ( .A1(ADDR[2]), .B1(ADDR[1]), .ZN(n18) );
  NR2D0BWP30P140HVT U42 ( .A1(n18), .A2(n14), .ZN(WRWL[11]) );
  NR2D0BWP30P140HVT U43 ( .A1(n18), .A2(n13), .ZN(WRWL[10]) );
  NR2D0BWP30P140HVT U44 ( .A1(n21), .A2(n14), .ZN(WRWL[9]) );
  NR2D0BWP30P140HVT U45 ( .A1(n21), .A2(n13), .ZN(WRWL[8]) );
  NR2D0BWP30P140HVT U46 ( .A1(n16), .A2(n14), .ZN(WRWL[15]) );
  ND3D0BWP30P140HVT U47 ( .A1(eco_net), .A2(ADDR[0]), .A3(n15), .ZN(n20) );
  NR2D0BWP30P140HVT U48 ( .A1(n20), .A2(n16), .ZN(WRWL[7]) );
  NR2D0BWP30P140HVT U49 ( .A1(n19), .A2(n16), .ZN(WRWL[6]) );
  NR2D0BWP30P140HVT U50 ( .A1(n20), .A2(n17), .ZN(WRWL[5]) );
  NR2D0BWP30P140HVT U51 ( .A1(n19), .A2(n17), .ZN(WRWL[4]) );
  NR2D0BWP30P140HVT U52 ( .A1(n20), .A2(n18), .ZN(WRWL[3]) );
  NR2D0BWP30P140HVT U53 ( .A1(n19), .A2(n18), .ZN(WRWL[2]) );
  NR2D0BWP30P140HVT U54 ( .A1(n21), .A2(n20), .ZN(WRWL[1]) );
  DEL050MD1BWP30P140HVT eco_cell ( .I(CK), .Z(eco_net) );
endmodule

/*
Used to dc_compiler, all the cell is defined in the tcbn28hpcplusbwp30p140hvt_180a/tcbn28hpcplusbwp30p140hvttt0p9v25c.db
simple decoder
*/
