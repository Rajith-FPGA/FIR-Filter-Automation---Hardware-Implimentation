`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 10/31/2025 05:09:56 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: mac_unit
// Target Devices: Arty s7 -50
// Description: Pre-add, multiply, accumulate.pipelined inside 1 DSP48E1 slice.
//              Portable. behavioral version for functional simulation.
////////////////////////////////////////////////////////////////////////////////////


module mac_unit#(
    parameter integer x_left_width = 16, // width of x[n-k], using Q1.15 (will feed to AREG)
    parameter integer x_right_width = 16,// width of x[n-(M-1-k)], using Q1.15(will feed to DREG)
    parameter integer coeff_width = 18, //filter co-effs in Q1.17 format (will feed to BREG)
    parameter integer pre_add_width = 18,// x_left and x_right will be sign extend to Q2.15. keep Q3.15 
    parameter integer product_out_width = 36 ,// pre_add * coeff , Q3.15 * Q1.17 -> Q4.32
    parameter integer accumulate_width = 48 // Q4.32 + log2(159)<- for additions = Q12.32 --- kept 48 bits to cleanly map to DSP48E1 slice
    )(
    //Control Inputs
    input wire clk, //system clock (Master)
    input wire rst, // reset
    input wire clear_mac, //1-cycle pulse to clear the accumulator
    input wire en_mac, // accumulate enable
    input wire center_mode, 
    input wire en_coeff,
    //Data Inputs
    input wire signed [x_left_width-1:0] x_left,
    input wire signed [x_right_width-1:0] x_right,
    input wire signed [coeff_width-1:0] filter_coeff,
    //Status 
    output wire busy, // MAC pipeline is active
    
    //Outputs
    output reg signed [accumulate_width-1: 0] accumulated_sum //PREG of DSP48E1 slice
    
    );
    //reg preadd_ready, coeff_ready, acc_done;//debugg reg
    wire signed [pre_add_width-1:0] pre_add;
    reg signed [pre_add_width-1:0] pre_add_store;
     //naddition for cenetr tap//11/03/2025
    wire signed [x_right_width-1:0] x_right_new = center_mode ? {x_right_width{1'b0}} : x_right;
    
    reg signed [x_left_width-1:0] x_left_final;
    reg signed [x_right_width-1:0] x_right_final;
    reg signed [coeff_width-1:0] filter_coeff_final;
    
    always @(posedge clk) begin
        if(rst || clear_mac)begin
            x_left_final <= 16'sb0;
            x_right_final <= 16'sb0;
            //preadd_ready <= 0; //debugg regs
        end else if(en_mac) begin
            x_left_final <= x_left;
            x_right_final <= x_right_new; 
            //preadd_ready <= 1; //debugg regs
        end
    end        
         
   //calculating pre-add 
   assign pre_add = x_left_final + x_right_final; //pre_add ready in the same time x_finals gets values
   
   //end of 1st clock cycle 
   //by this time our pre added sum is ready            
   //now wait for filter  coeff from rom and perform the calculations 
   always @(posedge clk)begin
        if(rst || clear_mac)begin
            filter_coeff_final <= 18'sb0;
        end else if(en_coeff) begin
            filter_coeff_final <= filter_coeff;
            //coeff_ready <= 1; //debugg regs
        end
    end
    
   //end of 2nd clock cycle.
   //after the final input, accumulation must work for 3 more cycles to finish all the work.
   //also mac should start at the 3rd cycle once pre-adder recieves data.           
   //Track pipeline latency for valid multiply results
   // valid count
   // 00 -> 01 -> 11 
    reg [1:0]valid_count_start = 0;
    reg [2:0] valid_count_end = 0;
        
    always@(posedge clk) begin              
        if(rst || clear_mac)begin
            valid_count_start <= 2'b0;
            valid_count_end <= 3'b0;
        end else begin
            valid_count_start <= {valid_count_start[1], en_mac};
            valid_count_end <= {valid_count_end[1:0],en_mac};
        end
    end
                
    wire mac_valid = valid_count_start[0] || valid_count_end[2];
    //end of 2nd clk cycle mac_valid becomes high.
    //In 3rd clk cycle accumulation will start.
    //once en_mac gets deasserted, accumulation will run for 3 more clock cycles before become in valid
    always@(posedge clk) begin
        if(rst || clear_mac)begin
            accumulated_sum <= 48'sb0;
        end else if (mac_valid)begin
            accumulated_sum <= accumulated_sum + pre_add * filter_coeff_final;
            //acc_done <= 1; //debugg regs
        end else begin
            //acc_done<=0; //debugg regs
            accumulated_sum <= accumulated_sum; // hold the value unless cleared or rst
        end     
    end                
    
    assign busy = |valid_count_end | en_mac;    
               
endmodule
