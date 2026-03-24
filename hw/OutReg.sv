module OutReg(
    input  var logic                        clock,
    input  var logic                        reset,
    input  var logic                        cim_ren,
    input  var logic [31 : 0]               odata,
    output var logic                        cim_odata_valid,
    output var logic [31 : 0]               cim_odata  
);


    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cim_odata <= '0;
        end
        else if (cim_ren) begin
            cim_odata <= odata;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cim_odata_valid <= '0;
        end
        else begin
            cim_odata_valid <= cim_ren;
        end
    end

endmodule: OutReg