// CimBlock: top-level wrapper around CimMacro with input register stage.
//
// Adds one pipeline register stage for:
//   - SRAM write signals (cim_wen, cim_waddr, cim_wdata)
//   - Activation + ZP inputs (act_in, zp_in, act_valid)
//
// SRAM read signals (cim_ren, cim_raddr) bypass the register stage so that
// read latency is consistent with CimMacro's one-cycle read pipeline.

module CimBlock #(
    parameter int N_GROUPS   = 16,
    parameter int DEPTH      = 32,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  var logic                        clk,
    input  var logic                        reset,

    // SRAM write
    input  var logic                        cim_wen,
    input  var logic [ADDR_WIDTH-1:0]       cim_waddr,
    input  var logic [5*N_GROUPS-1:0]       cim_wdata,      // 320-bit

    // Activation + ZP
    input  var logic [24*N_GROUPS-1:0]      act_in,         // 1536-bit
    input  var logic [7:0]                  zp_in,
    input  var logic                        act_valid,

    // SRAM read
    input  var logic                        cim_ren,
    input  var logic [ADDR_WIDTH-1:0]       cim_raddr,

    output var logic [31:0]                 cim_odata,
    output var logic                        cim_odata_valid
);

    // --- Input register stage ---
    logic                        cim_wen_reg;
    logic [ADDR_WIDTH-1:0]       cim_waddr_reg;
    logic [5*N_GROUPS-1:0]       cim_wdata_reg;

    logic [24*N_GROUPS-1:0]      act_in_reg;
    logic [7:0]                  zp_in_reg;
    logic                        act_valid_reg;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            cim_wen_reg   <= '0;
            cim_waddr_reg <= '0;
            cim_wdata_reg <= '0;
            act_in_reg    <= '0;
            zp_in_reg     <= '0;
            act_valid_reg <= '0;
        end else begin
            cim_wen_reg   <= cim_wen;
            cim_waddr_reg <= cim_waddr;
            cim_wdata_reg <= cim_wdata;
            act_in_reg    <= act_in;
            zp_in_reg     <= zp_in;
            act_valid_reg <= act_valid;
        end
    end

    // --- CimMacro instantiation ---
    CimMacro #(
        .N_GROUPS  (N_GROUPS),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uMacro (
        .clk            (clk),
        .reset          (reset),
        .cim_wen        (cim_wen_reg),
        .cim_waddr      (cim_waddr_reg),
        .cim_wdata      (cim_wdata_reg),
        .act_in         (act_in_reg),
        .zp_in          (zp_in_reg),
        .act_valid      (act_valid_reg),
        .cim_ren        (cim_ren),
        .cim_raddr      (cim_raddr),
        .cim_odata      (cim_odata),
        .cim_odata_valid(cim_odata_valid)
    );

endmodule: CimBlock
