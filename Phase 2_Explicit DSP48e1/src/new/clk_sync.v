`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
//Create Date: 11/02/2025 09:21:55 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: clk_sync
// Target Devices: Arty s7 -50
// Description: Synchronizes the slow sample-rate clock with the main 100 MHz system clock. 
//              Converts the asynchronous 48 kHz clock pulse into a clean single-cycle pulse. 
//              Prevents metastability between clock domains using two flip-flops. 
//              Ensures reliable triggering of FIR operations at each new input sample.
///////////////////////////////////////////////////////////////////////////////////////


module clk_sync(
    input wire clk_fast,
    input wire async_clk,
    input wire rst,
    output wire clean_pulse
    );
    
    reg ff1,ff2;
    
    always@(posedge clk_fast or posedge rst)begin
        if(rst)begin
            ff1 <= 0;
            ff2 <= 0;
        end else begin
            ff1 <= async_clk;
            ff2 <= ff1;
        end        
    end
    
    assign clean_pulse = ff1 & ~ff2;
endmodule