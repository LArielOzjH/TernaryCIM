module ClockGate (
    input  wire  inClock,
    output wire  outClock,
    input  wire  enable0,
    input  wire  enable1
);
`ifdef ASIC_CLOCK_GATING
    CKLNQD16BWP30P140HVT clock_gate_latch (
        .CP (inClock),
        .Q  (outClock),
        .E  (enable0),
        .TE (enable1)
    );
`else
    reg en_latch;
    always @(*) begin
        if(!inClock) begin
            en_latch = enable0;
        end
    end

    assign outClock = inClock & en_latch;
`endif
endmodule // ClockGate

/*
(base) [zhuojun_han@cloud-mgmt01 tcbn28hpcplusbwp30p140hvt_180a]$ grep CKLNQD16BWP30P140HVT tcbn28hpcplusbwp30p140hvttt0p9v25c.lib
 * Design : CKLNQD16BWP30P140HVT *
cell (CKLNQD16BWP30P140HVT) {

in the $NVLM_PATH/tcbn28hpcplusbwp30p140hvt_180a/tcbn28hpcplusbwp30p140hvttt0p9v25c.db(set up in the dc.tcl)

The module is used to gate the clock.
*/