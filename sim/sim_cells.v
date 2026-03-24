// sim_cells.v
// Behavioral models for ASIC-specific standard cells used in CimDecoderBuffer.
// These are simulation-only and should NOT be used in synthesis.
// Include this file ONLY during simulation (not in the synthesis filelist).

`timescale 1ns/1ps

// BUFFD8BWP30P140HVT: simple buffer
module BUFFD8BWP30P140HVT (
    input  I,
    output Z
);
    assign Z = I;
endmodule
