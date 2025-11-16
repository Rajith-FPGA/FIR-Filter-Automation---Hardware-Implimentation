`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/01/2025 09:56:50 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: coeff_rom
// Target Devices: Arty S7-50
// Description:
//    Block-ROM based coefficient fetch unit for 317-tap FIR filter.
//    Loads Python-generated Q1.17 coefficients from HEX file and
//    provides deterministic, fully-pipelined coefficient output
//    to match sample_mem latency.
//
// Update (11/14/2025):
//    • Increased pipeline depth to 6 stages for 200 MHz timing closure
//    • Finalized latency alignment with BRAM-based sample_mem
///////////////////////////////////////////////////////////////////////////////////////
// ====================================================================================
// LATENCY SUMMARY (Corrected for your current pipeline)
// ------------------------------------------------------------------------------------
// Pipeline structure:
//   addr_pipe[0]  ← cycle 0 (raw address)
//   addr_pipe[1]  ← cycle 1
//   addr_pipe[2]  ← cycle 2
//   addr_pipe[3]  ← cycle 3
//   addr_pipe[4]  ← cycle 4
//   addr_pipe[5]  ← cycle 5 (used in BRAM lookup)
//
// • Address pipeline depth:                   6 cycles
// • Synchronous BRAM read inside same cycle: +0 cycles
// • Total from en_read_co_eff → coeff_out:    6 cycles
// • FSM capture (optional next 200 MHz edge): 7 cycles total
//
// This latency perfectly matches the BRAM-based sample_mem
// pipeline depth, ensuring x[n-k] samples and b[k] coefficients
// arrive in lock-step at the FIR datapath.
// ====================================================================================

 
module coeff_rom#(

    parameter integer filter_coeff_width = 18, // coeff in Q1.17
    parameter integer number_taps = 159 // filter is 317 taps. bcs of symmetry 158 taps + 1 center tap
)(
    //control inputs
    input wire clk, //system clk @100MHz
    //input wire rst,
    //data inputs
    input wire [7:0] address, // we have 159 entries, log2(159) = 8bits
    input wire en_read_co_eff,
    //output
    output reg signed [filter_coeff_width-1:0] coeff_out


    );
    // coeff_memory is an array of registers that works like a ROM.
    //18 bit signed regs -> 0 to 158 (159 total)
    (*ram_style = "block"*)reg signed [filter_coeff_width-1:0] coeff_memory [0:number_taps];
 
    initial begin   
        $readmemh("fir_coeffs_317_q17.mem", coeff_memory);
    end
    
  
    // Address and control pipelining for latency alignment (6 total cycles)

    reg [7:0] addr_pipe [0:5];       
    reg       en_pipe   [0:5];     
    integer i;

    always @(posedge clk) begin
        // Shift pipeline (6 stages)
        addr_pipe[0] <= address;
        en_pipe[0]   <= en_read_co_eff;
        for (i = 1; i < 6; i = i + 1) begin
            addr_pipe[i] <= addr_pipe[i-1];
            en_pipe[i]   <= en_pipe[i-1];
        end
    end
 
    //synchronous read -> works like real BRAM in arty s7_50, 1 output at rising edge of the clock
    always@(posedge clk)begin
       if (en_pipe[5]) begin
            coeff_out <= coeff_memory[addr_pipe[5]];
       end
    end        
endmodule
