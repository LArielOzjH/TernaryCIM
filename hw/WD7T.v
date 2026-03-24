// Verilog for library WD7T created by Liberate dev on Sat Sep 17 15:49:03 CST 2022 for SDF version 2.1

// type:  
`timescale 1ns/1ps
`celldefine
module WD7T (WBL, WBLN, CKW, DIN, DINB);
	output WBL, WBLN;
	input CKW, DIN, DINB;
	reg notifier;
	wire M1, M2, M3, M4, M5;
	//Function
	not(M1, DIN);
	not(M2, DINB);
	not(M3, CKW);
	and(M4, CKW, M1);
	and(M5, CKW, M2);
	or(WBL, M3, M5);
	or(WBLN, M3, M4);
	// Timing
	specify
		(DIN => WBL) = 0;
		(DINB => WBL) = 0;
		(CKW => WBL) = 0;
		(DIN => WBLN) = 0;
		(DINB => WBLN) = 0;
		(CKW => WBLN) = 0;
	endspecify
endmodule
`endcelldefine
