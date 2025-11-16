`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/03/2025 06:10:16 AM
// Design Name: FIR lowpass filter 317 taps
// Module Name: fir_top
// Target Devices: Arty S7-50
// Description:
//    Top-level wrapper that instantiates the fully pipelined FIR core.
//    Provides clean integration point for future I²S ADC/DAC interface,
//    while exposing a simple sample_in → sample_out streaming interface.
//
//    This module passes raw 16-bit Q1.15 samples into fir_core,
//    receives filtered samples and a 1-cycle valid strobe, and
//    makes them available for higher-level system logic.
///////////////////////////////////////////////////////////////////////////////////////
// ====================================================================================
// FUNCTIONAL SUMMARY
// ------------------------------------------------------------------------------------
// * Accepts 16-bit signed input samples (Q1.15)
// * Directly feeds fir_core (which generates all PLLs, CDC, buffering)
// * For each new output sample:
//      - y_out presents the filtered 16-bit Q1.15 result
//      - y_valid pulses high for exactly one 100 MHz cycle
//
// fir_top contains **no datapath** and **no internal FSMs**.
// It is purely a system-level integration shell designed for
// clean connection to:
//      • I²S receiver (ADC path)
//      • I²S transmitter (DAC path)
//      • Logic analyzer / debug instrumentation
//
// This keeps the FIR core entirely self-contained and portable.
// ====================================================================================
// LATENCY SUMMARY
// ------------------------------------------------------------------------------------
// All latency is handled inside fir_core:
//   • 200 MHz FFSM pipeline (sample_mem + coeff_rom path)
//   • CDC via safe_sample (bundle transfer)
//   • Dual DSP48E1 MAC chain
//   • 100 MHz SFSM accumulation + rounding + saturation
//
// fir_top introduces **0 additional cycles** of latency.
//
// y_valid is simply the direct propagation of output_ready from fir_core.
// ====================================================================================



module fir_top (
    input  wire        clk,     // Arty S7 100 MHz
    input  wire        rst,             // active-LOW button (e.g., BTN0) -> invert below
    input  wire signed [15:0] x_in,     // for now: drive from testbench; later: I²S sample
    output wire signed [15:0] y_out,    // to DAC later (I²S path)
    output wire        y_valid        // 1-cycle pulse each output sample
);

// --------------------------------------------------------------------------
// FIR core instance
// --------------------------------------------------------------------------
// fir_core internally generates:
//   • 12.288 MHz audio-rate PLL clock
//   • 200 MHz FFSM clock
//   • 100 → 200 MHz safe CDC
//   • sample_mem + coeff_rom pipeline
//   • dual DSP48E1 MAC chain
//
// This top-level simply forwards x_in and returns y_out/y_valid.
// -------------------------------------------------------------------------
   
    // ---- FIR core instance (unchanged RTL; it has its own PLL + clk_sync) ----
    wire signed [15:0] y_core;
    wire               out_ready_core;

    fir_core #(
        .data_width(16),
        .coeff_width(18),
        .accumulator_width(48),
        .num_taps(317)
    ) fir_1 (
        .clk          (clk),   //fir_core expects the 100 MHz here
        .rst          (rst),
        .x_in         (x_in),
        .y_out        (y_core),
        .output_ready (out_ready_core)
    );
// --------------------------------------------------------------------------
// Output wiring
// --------------------------------------------------------------------------
// y_out   → actual filtered value (Q1.15)
// y_valid → asserted for 1 cycle when y_out is updated
// --------------------------------------------------------------------------
    
    assign y_out   = y_core;
    assign y_valid = out_ready_core;

endmodule

