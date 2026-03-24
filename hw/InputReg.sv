module InputReg #(
    parameter int WIDTH = 64,
    parameter int DEPTH = 16,
    parameter int N = 8,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  var logic                            clock,
    input  var logic                            reset,

    input  var logic [WIDTH - 1 : 0]            cim_idata,
    input  var logic                            cim_ren,
    input  var logic [ADDR_WIDTH - 1 : 0]       cim_raddr,

    input  var logic                            cim_wen,
    input  var logic [ADDR_WIDTH - 1 : 0]       cim_waddr,
    input  var logic [WIDTH - 1 : 0]            cim_wdata,
    input  var logic                            cim_mode,

    output var logic [WIDTH - 1 : 0]            cim_idata_reg,
    output var logic [ADDR_WIDTH - 1 : 0]       cim_raddr_reg,

    output var logic [ADDR_WIDTH - 1 : 0]       cim_waddr_reg,
    output var logic [WIDTH - 1 : 0]            cim_wdata_reg,  
    output var logic                            cim_mode_reg
);

        
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cim_idata_reg   <= '0;
            cim_raddr_reg   <= '0;
            cim_mode_reg    <= '0;
        end
        else if (cim_ren) begin
            cim_idata_reg   <= cim_idata;
            cim_raddr_reg   <= cim_raddr;
            cim_mode_reg    <= cim_mode;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cim_waddr_reg   <= '0;
            cim_wdata_reg   <= '0;
        end
        else if(cim_wen) begin
            cim_waddr_reg   <= cim_waddr;
            cim_wdata_reg   <= cim_wdata;
        end
    end

endmodule: InputReg