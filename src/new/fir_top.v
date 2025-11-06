`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/03/2025 06:10:16 AM
// Design Name: 
// Module Name: fir_top
// Project Name: 
// Target Devices: 
// Description: 
//////////////////////////////////////////////////////////////////////////////////


module fir_top (
    input  wire        sys_clk_100,     // Arty S7 100 MHz
    input  wire        rst,             // active-LOW button (e.g., BTN0) -> invert below
    input  wire signed [15:0] x_in,     // for now: drive from testbench; later: I²S sample
    output wire signed [15:0] y_out,    // to DAC later (I²S path)
    output wire        y_valid        // 1-cycle pulse each output sample
);

   
    // ---- FIR core instance (unchanged RTL; it has its own PLL + clk_sync) ----
    wire signed [15:0] y_core;
    wire               out_ready_core;

    fir_core #(
        .data_width(16),
        .coeff_width(18),
        .accumulator_width(48),
        .num_taps(317)
    ) fir_1 (
        .clk          (sys_clk_100),   // your fir_core expects the 100 MHz here
        .rst          (rst),
        .x_in         (x_in),
        .y_out        (y_core),
        .output_ready (out_ready_core)
    );

    // ---- Simple wiring to outputs ----
    assign y_out   = y_core;
    assign y_valid = out_ready_core;

endmodule

