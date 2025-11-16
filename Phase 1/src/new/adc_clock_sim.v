`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/05/2025 02:10:22 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: adc_clock_sim
// Target Devices: Arty s7 -50
// Description: Generates the 48 kHz sampling clock from the 12.288 MHz audio PLL. 
//              Divides the high-speed audio clock by 256 to simulate ADC sample rate. 
//              Provides a clean square-wave output synchronized to the PLL clock. 
//              Used to trigger each new input sample in the FIR processing chain. 
///////////////////////////////////////////////////////////////////////////////////////


module adc_clock_sim(
    input wire clk_audio_12M288,
    input wire rst,
    output wire sample_rate_clock
    );
    
    reg [7:0] div256 = 0;
    reg clock = 0;
    always@(posedge clk_audio_12M288 or posedge rst)begin
        if(rst)begin
            div256<=0;
            clock <= 0;
        end else begin
            if(div256== 8'd127)begin
                clock <= ~clock;
                div256 <= 0;
            end else begin
                div256 <= div256 + 1'b1;
            end    
        end
    end                    
    
    assign sample_rate_clock = clock;
endmodule
