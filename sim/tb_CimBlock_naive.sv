// tb_CimBlock_naive.sv
// Testbench for CimBlock_naive (ablation baseline: no LUT, direct MAC).
// Reads the same test vectors as tb_CimBlock_sparse via +sparse_dir=<path>.
// All 32 rows should PASS (naive computation equals the golden reference).
// FSDB output goes to <sparse_dir>/tb_CimBlock_naive.fsdb for PTPX.

`timescale 1ns/1ps

module tb_CimBlock_naive;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam int N_GROUPS   = 16;
    localparam int DEPTH      = 32;
    localparam int ADDR_WIDTH = 5;
    localparam int ACT_SETTLE = 4;

    localparam real CLK_HALF = 1.25;  // 400 MHz

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic                       clk;
    logic                       reset;

    logic                       cim_wen;
    logic [ADDR_WIDTH-1:0]      cim_waddr;
    logic [5*N_GROUPS-1:0]      cim_wdata;

    logic [24*N_GROUPS-1:0]     act_in;
    logic [7:0]                 zp_in;
    logic                       act_valid;

    logic                       cim_ren;
    logic [ADDR_WIDTH-1:0]      cim_raddr;

    logic [31:0]                cim_odata;
    logic                       cim_odata_valid;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    CimBlock_naive #(
        .N_GROUPS  (N_GROUPS),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk            (clk),
        .reset          (reset),
        .cim_wen        (cim_wen),
        .cim_waddr      (cim_waddr),
        .cim_wdata      (cim_wdata),
        .act_in         (act_in),
        .zp_in          (zp_in),
        .act_valid      (act_valid),
        .cim_ren        (cim_ren),
        .cim_raddr      (cim_raddr),
        .cim_odata      (cim_odata),
        .cim_odata_valid(cim_odata_valid)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // -----------------------------------------------------------------------
    // Test data memory
    // -----------------------------------------------------------------------
    logic [79:0]    weight_mem [0:DEPTH-1];
    logic [7:0]     act_bytes  [0:47];
    logic [7:0]     zp_byte    [0:0];
    logic [31:0]    golden     [0:DEPTH-1];

    logic [31:0]    sim_results [0:DEPTH-1];
    integer         collected_count;
    integer         out_fd;

    string          sparse_dir;

    // -----------------------------------------------------------------------
    // Task: apply reset
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            reset     = 1;
            cim_wen   = 0;  cim_waddr  = '0;  cim_wdata = '0;
            act_in    = '0; zp_in      = '0;  act_valid = 0;
            cim_ren   = 0;  cim_raddr  = '0;
            repeat (8) @(posedge clk);
            #1;
            reset = 0;
            @(posedge clk); #1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: write all rows to SRAM
    // -----------------------------------------------------------------------
    task write_all_weights;
        integer row;
        begin
            $display("[%0t] Writing %0d rows to SRAM...", $time, DEPTH);
            for (row = 0; row < DEPTH; row = row + 1) begin
                @(posedge clk); #1;
                cim_wen   = 1;
                cim_waddr = row[ADDR_WIDTH-1:0];
                cim_wdata = weight_mem[row];
                @(posedge clk); #1;
                @(posedge clk); #1;
                cim_wen   = 0;
            end
            @(posedge clk); #1;
            $display("[%0t] SRAM write complete.", $time);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: load activations, pulse act_valid, wait for register settle
    // -----------------------------------------------------------------------
    task load_activations;
        integer i;
        begin
            for (i = 0; i < 3*N_GROUPS; i = i + 1)
                act_in[8*i +: 8] = act_bytes[i];
            zp_in = zp_byte[0];

            $display("[%0t] Loading activations, ZP=0x%02h", $time, zp_byte[0]);

            @(posedge clk); #1;
            act_valid = 1;
            @(posedge clk); #1;
            act_valid = 0;

            repeat (ACT_SETTLE) @(posedge clk);
            #1;
            $display("[%0t] act_reg ready.", $time);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: read all rows (2-cycle pipeline)
    // -----------------------------------------------------------------------
    task read_all_rows;
        integer cyc;
        begin
            collected_count = 0;
            $display("[%0t] Reading %0d rows...", $time, DEPTH);

            for (cyc = 0; cyc <= DEPTH + 1; cyc = cyc + 1) begin
                @(negedge clk); #0.1;
                if (cyc < DEPTH) begin
                    cim_ren   = 1;
                    cim_raddr = cyc[ADDR_WIDTH-1:0];
                end else begin
                    cim_ren   = 0;
                    cim_raddr = '0;
                end

                @(posedge clk); #0.1;

                if (cim_odata_valid) begin
                    if (collected_count < DEPTH) begin
                        sim_results[collected_count] = cim_odata;
                        collected_count = collected_count + 1;
                    end
                end
            end

            $display("[%0t] Read complete. Collected %0d results.", $time, collected_count);
        end
    endtask

    // -----------------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------------
    initial begin
`ifdef FSDB
        begin
            string _fsdb_dir;
            if (!$value$plusargs("sparse_dir=%s", _fsdb_dir))
                _fsdb_dir = "tests_sparse/h080_f075_s8";
            $fsdbDumpfile({_fsdb_dir, "/tb_CimBlock_naive.fsdb"});
            $fsdbDumpvars(0, dut);
            $fsdbDumpMDA();
        end
`elsif VCD
        $dumpfile("tb_CimBlock_naive.vcd");
        $dumpvars(0, tb_CimBlock_naive);
`endif
    end

    // -----------------------------------------------------------------------
    // Main test body
    // -----------------------------------------------------------------------
    integer pass_count, fail_count, i;
    logic signed [31:0] got_s, exp_s;

    initial begin
        if (!$value$plusargs("sparse_dir=%s", sparse_dir))
            sparse_dir = "tests_sparse/h080_f075_s8";
        $display("[TB] sparse_dir = %s", sparse_dir);

        $readmemh({sparse_dir, "/weight_mem_sparse.hex"}, weight_mem);
        $readmemh({sparse_dir, "/act_mem_sparse.hex"},    act_bytes);
        $readmemh({sparse_dir, "/zp_sparse.hex"},         zp_byte);
        $readmemh({sparse_dir, "/golden_sparse.hex"},     golden);

        $display("============================================");
        $display("  Naive Baseline Testbench  N=%0d D=%0d", N_GROUPS, DEPTH);
        $display("============================================");

        do_reset();
        write_all_weights();

        $display("[PTPX] Inference window start: %0t", $realtime);
        load_activations();
        read_all_rows();
        $display("[PTPX] Inference window end:   %0t", $realtime);

        out_fd = $fopen({sparse_dir, "/sim_output_naive.hex"}, "w");
        if (!out_fd) begin
            $display("ERROR: cannot open %s/sim_output_naive.hex", sparse_dir);
            $finish;
        end
        for (i = 0; i < collected_count; i = i + 1)
            $fdisplay(out_fd, "%08h", sim_results[i]);
        $fclose(out_fd);
        $display("[%0t] Output written to %s/sim_output_naive.hex", $time, sparse_dir);

        pass_count = 0; fail_count = 0;
        $display("\n--- Per-row comparison ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            got_s = $signed(sim_results[i]);
            exp_s = $signed(golden[i]);
            if (sim_results[i] === golden[i]) begin
                pass_count = pass_count + 1;
                if (i < 16)
                    $display("  Row %3d PASS  sim=%08h (%0d)", i, sim_results[i], got_s);
            end else begin
                fail_count = fail_count + 1;
                $display("  Row %3d FAIL  sim=%08h (%0d)  exp=%08h (%0d)",
                         i, sim_results[i], got_s, golden[i], exp_s);
            end
        end

        $display("\n============================================");
        $display("  PASS: %0d / %0d    FAIL: %0d", pass_count, DEPTH, fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d FAILURES ***", fail_count);
        $display("============================================");

        $finish;
    end

    initial begin
        #10_000_000;
        $display("ERROR: simulation timeout at %0t", $time);
        $finish;
    end

endmodule: tb_CimBlock_naive
