`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/02/2025 02:25:43 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: fir_core
// Target Devices: Arty s7 -50
// Description: Main FIR processing core that coordinates sample memory, 
//              coefficient ROM, and MAC unit through an FSM controller. 
//              Handles input sampling, accumulation, and output generation 
//              synchronized with the audio clock (48 kHz from PLL).
///////////////////////////////////////////////////////////////////////////////////////



module fir_core#(
    parameter integer data_width = 16, //sapmles are in Q1.15    
    parameter integer coeff_width = 18, //filter coeffs in Q1.17
    parameter integer accumulator_width = 48, //Q12.32 -> kept 48 bits to cleanly map to DSP48E1 slice
    parameter integer num_taps = 317 // filter order
    
)(
    //control inputs
    input wire clk, //system clk @100MHz
    input wire rst, //global reset
    
    //data inputs
    input wire signed [data_width-1:0] x_in, //input from top (top gets from ADC)
    
    //data outputs
    output reg signed [data_width-1: 0] y_out, //output to top (top sends to DAC)
    
    //status
    output reg output_ready
    
    );
    
    //regs designed while debugging  
   
    reg en_read_co_eff_from_fir_core = 0;
    reg center_done=0;
    reg en_mac_done=0;
    reg en_produc_from_fir_core=0;
    reg en_coeff_from_fir_core=0;
    reg update_ptr_from_fir_core;
    
    //Internal Signals and registers
    //creating while initiating sample_mem
    wire signed [data_width-1:0] x_left_out_from_sample_mem, x_right_out_from_sample_mem;
    reg en_write_from_fir_core = 0;
    reg [$clog2(num_taps/2)-1:0] k_index_from_fir_core; //coeff index for symmetry
    
    //creating while initiating coeffs_rom
    wire signed [coeff_width-1:0] filter_coeffs_out_from_coeffs_rom;
    
    //creating while initiating mac
    wire mac_busy_from_mac_unit;
    wire signed [accumulator_width-1:0] acc_sum_from_mac_unit;
    reg clear_acc_from_fir_core = 0;
    reg en_mac_from_fir_core = 0;
    reg signed [33:0] rounded_val= 0;
    reg center_mode_from_fir_core = 0;
    //creating while initiating clk_sync
    wire sample_ready;
    
    //clock gen
    //get experience with using system generated clocks without using clk dividers
    //also this gives the most truthful value
    wire clk_audio_12M288 ;
    wire pll_locked ;
    wire sample_clock;
    //hold FIR FSM in reset until PLL locks
    wire sys_rst = rst | ~pll_locked; 
    
    clk_wiz_audio audio_pll_inst(
        //inputs 
        .clk_in1(clk),
        .reset(rst),
        //outputs
        .clk_out1(clk_audio_12M288),
        .locked(pll_locked)
       
    );
    
    adc_clock_sim s_clock(
    .clk_audio_12M288(clk_audio_12M288),
    .rst(sys_rst),
    .sample_rate_clock(sample_clock)
    );
    
    clk_sync s_signal(
        //inputs
        .clk_fast(clk),
        .async_clk(sample_clock),
        .rst(sys_rst),
        //output
        .clean_pulse(sample_ready)
    );
    
    //sample mem initiation
    sample_mem #(
        .data_width(data_width) ,
        .filter_taps(num_taps) // order of the filter
    )buffer(
        //control inputs
        .clk(clk), // system clock @100MHz
        .rst(sys_rst), //global reset
        .en_write(en_write_from_fir_core), // 1 = write new sample
        .update_ptr(update_ptr_from_fir_core),
        // data input
        .x_in(x_in), // new sample from fir core
        .k_index(k_index_from_fir_core),
        // Read data outputs to the fir core
        .x_left(x_left_out_from_sample_mem),
        .x_right(x_right_out_from_sample_mem)
       
    );

    //coeff_rom initiation
    
    coeff_rom #(
        .filter_coeff_width(coeff_width), // coeff in Q1.17
        .number_taps(num_taps) // filter is 317 taps. bcs of symmetry 158 taps + 1 center tap
    )coeffs(
        //control inputs
        .clk(clk), //system clk @100MHz
        //data inputs
        .en_read_co_eff(en_read_co_eff_from_fir_core),
        .address(k_index_from_fir_core), // we have 159 entries, log2(159) = 8bits
        //output
        .coeff_out(filter_coeffs_out_from_coeffs_rom)

    );
    
    mac_unit#(
    .x_left_width(data_width), 
    .x_right_width(data_width),
    .coeff_width(coeff_width), 
    .pre_add_width(18),
    .product_out_width(36),// pre_add * coeff , Q3.15 * Q1.17 -> Q4.32
    .accumulate_width(accumulator_width)// Q4.32 + log2(159)<- for additions = Q12.32 --- kept 48 bits to cleanly map to DSP48E1 slice
    )mac_1(
    //Control Inputs
    .clk(clk), //system clock (Master)
    .rst(sys_rst), // reset
    .clear_mac(clear_acc_from_fir_core), //1-cycle pulse to clear the accumulator
    .en_mac(en_mac_from_fir_core), // accumulate enable,
    .center_mode(center_mode_from_fir_core), 
    .en_coeff(en_coeff_from_fir_core),
    //Data Inputs
    .x_left(x_left_out_from_sample_mem),
    .x_right(x_right_out_from_sample_mem),
    .filter_coeff(filter_coeffs_out_from_coeffs_rom),
    //Status 
    .busy(mac_busy_from_mac_unit), // MAC pipeline is active
    
    //Outputs
    .accumulated_sum(acc_sum_from_mac_unit) //PREG of DSP48E1 slice
    
    );
    
    
   
   
     //////////FSM//////////////////////////////////////////////////////////////////////////////////////////////////////////////////    
     
    
    
                   
    localparam s_idle = 0,
               s_write = 1, 
               s_load = 2,// will remove in phase 2
               s_mac  = 3,
               s_stop = 4;
    
     (* fsm_encoding = "user" *) reg [2:0] state = 0;
    
    always@(posedge clk)begin
        if(sys_rst)begin
            en_mac_from_fir_core <= 0;
            clear_acc_from_fir_core <= 0;
            en_write_from_fir_core <= 0;
            output_ready <= 0;
            center_mode_from_fir_core <= 0;
            k_index_from_fir_core = 0;
            en_coeff_from_fir_core <= 0;
            state <= s_idle;
            update_ptr_from_fir_core <= 0;
              
        end else begin
           
        //FSM Behv
            case(state)
    
                s_idle: begin
                    en_mac_from_fir_core <= 0;
                    clear_acc_from_fir_core <= 0;
                    en_write_from_fir_core <= 0;
                    output_ready <= 0;
                    center_mode_from_fir_core <= 0;
                    k_index_from_fir_core <=0;
                    y_out <= y_out;
                    output_ready <= 0;
                    update_ptr_from_fir_core <= 0;
                    if(sample_ready)begin 
                        en_mac_from_fir_core <= 1;
                        clear_acc_from_fir_core <= 1;        
                        state <= s_write;
                    end else begin
                        state <= s_idle;
                    end
                end
                
                s_write: begin
                    en_write_from_fir_core <= 1; //assert flag to start writing sample from memory.
                    
                    update_ptr_from_fir_core <= 1;
                    
                    en_read_co_eff_from_fir_core <= 1;                       
                    state <= s_mac;
                    
                end               
                
                s_mac: begin  
                    en_write_from_fir_core   <= 0;   // stop writing new input samples
                    clear_acc_from_fir_core  <= 0;   // keep accumulator active
                    en_mac_from_fir_core <= 1;
                    en_coeff_from_fir_core <= 1;
                   
                    update_ptr_from_fir_core <= 0;
                    if(k_index_from_fir_core < num_taps/2)begin                      
                        k_index_from_fir_core <= k_index_from_fir_core + 1;
                        state <= s_mac;
                    end else if(k_index_from_fir_core == 158)begin
                        center_mode_from_fir_core <= 0;       
                        k_index_from_fir_core <= k_index_from_fir_core + 1;
                        state <= s_mac;
                    end else begin
                        center_mode_from_fir_core <= 0;
                        k_index_from_fir_core<=0;    
                        en_mac_from_fir_core <= 0;
                        en_coeff_from_fir_core <= 0;
                        en_read_co_eff_from_fir_core <= 0;
                        state <= s_stop;
                    end                    
                end
            
                s_stop: begin
    
                    // Disable all FIR operations - MAC is complete
                    clear_acc_from_fir_core <= 0;
                   // Rounding + scaling back to Q1.15
                    // acc_sum is Q13.32 (approx) → shift down by 17
                    // Add 0.5 LSB at bit 16 for round-to-nearest                
                    rounded_val <= acc_sum_from_mac_unit + (48'sd1 <<< 16);
                    // Scale back to Q1.15
                    y_out <= rounded_val >>> 17;
                    // Saturate to 16-bit signed range (optional)
                    if (y_out > 32767)begin
                        y_out <= 32767;
                    end else if (y_out < -32768)begin
                        y_out <= -32768;
                    end       
                    // Output 
                    output_ready <= 1;          // one-cycle pulse to signal valid output
                    state   <= s_idle;     // ready for next input sample
                end

            endcase
        end
    end 
                       
endmodule

