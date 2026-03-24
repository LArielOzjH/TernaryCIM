module CellArray #(
    parameter int DEPTH      = 128,
    parameter int ADDR_WIDTH = $clog2(DEPTH),
    parameter int WIDTH      = 320       // 64 groups × 5 bits/group
)(
    input  var logic                            clock,

    input  var logic                            cim_ren,
    input  var logic [ADDR_WIDTH-1:0]           cim_raddr,

    input  var logic                            cim_wen,
    input  var logic [ADDR_WIDTH-1:0]           cim_waddr,
    input  var logic [WIDTH-1:0]                cim_wdata,

    output var logic [WIDTH-1:0]                w_out
);
    logic wr_clock, rd_clock;

    ClockGate WRCLK(
        .inClock(clock),
        .outClock(wr_clock),
        .enable0(cim_wen),
        .enable1(1'b0)
    );

    ClockGate RDCLK(
        .inClock(clock),
        .outClock(rd_clock),
        .enable0(cim_ren),
        .enable1(1'b0)
    );

    logic [WIDTH-1:0] DIN, DINB;
    assign DIN  =  cim_wdata;
    assign DINB = ~cim_wdata;

    logic [DEPTH-1:0] RWL, WWL;
    logic [DEPTH-1:0] BUFFRWL, BUFFWWL;

    CimDecoder #(.DEPTH(DEPTH)) wr_decoder(.CK(wr_clock), .ADDR(cim_waddr), .WRWL(WWL));
    CimDecoder #(.DEPTH(DEPTH)) rd_decoder(.CK(rd_clock), .ADDR(cim_raddr), .WRWL(RWL));

    CimDecoderBuffer #(.DEPTH(DEPTH)) w_buffer(.WRWL(WWL),  .BUFFWRWL(BUFFWWL));
    CimDecoderBuffer #(.DEPTH(DEPTH)) r_buffer(.WRWL(RWL),  .BUFFWRWL(BUFFRWL));

    for (genvar i = 0; i < WIDTH; i += 1) begin: MEM
        CimRow #(.DEPTH(DEPTH)) uCimRow(
            .DIN(DIN[i]), .DINB(DINB[i]),
            .CKW(wr_clock), .CKR(rd_clock),
            .RWL(BUFFRWL), .WWL(BUFFWWL),
            .HOT(w_out[i])
        );
    end

endmodule: CellArray

/*
    SRAM array: DEPTH=128 rows × WIDTH=320 bits per row.
    320 bits = 64 groups × 5 bits/group (5-pack-3 ternary weight encoding).
    Each CimRow stores one bit plane across all DEPTH rows.
    Decoder is parametric; CimDecoderBuffer drives word lines.
*/
