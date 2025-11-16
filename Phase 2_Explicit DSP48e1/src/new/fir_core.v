`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/02/2025 02:25:43 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: fir_core
// Target Devices: Arty S7-50
// Description:
//    Top-level FIR processing engine coordinating:
//      • High-speed 200 MHz sample/coeff fetch (FFSM)
//      • Safe multi-clock transfer (200 → 100 MHz)
//      • Dual DSP48E1 multiply-accumulate pipeline
//      • System-clock output accumulation + rounding + saturation (SFSM)
//
//    Handles input sampling, memory updates, coefficient sequencing,
//    batch formation, accumulation, and finally delivers a 48 kHz
//    audio-rate output to the DAC through the top module.
//
// Update (11/15/2025):
//    • Finalized parallel MAC pipeline
//    • Latency-deterministic FFSM/SFSM sequencing
//    • Cleaned 200→100 MHz safe-sampling interface alignment
///////////////////////////////////////////////////////////////////////////////////////
// ====================================================================================
// FUNCTIONAL SUMMARY
// ------------------------------------------------------------------------------------
// * Generates two internal clocks via PLLs (12.288 MHz and 200 MHz)
// * FFSM (200 MHz domain):
//      - Writes incoming samples into BRAM circular buffer
//      - Reads symmetric sample pairs + coefficients
//      - Forms 81 batches (158 taps + padded), two taps per batch
//      - Aligns pipeline latency for BRAM + ROM (7-cycle delay)
// * Safe transfer block:
//      - Snapshots 100-bit bundles across clock domains (no metastability)
// * SFSM (100 MHz domain):
//      - Feeds DSP48E1 slices
//      - Accumulates MAC output
//      - Applies rounding (add 1 LSB) + arithmetic shift
//      - Saturates to Q1.15
//      - Asserts output_ready for DAC interface
//
// All pipeline stages are explicitly registered to break long timing paths
// and guarantee 200 MHz closure for the read-side datapath.
// ====================================================================================
// LATENCY / PIPELINE SUMMARY
// ------------------------------------------------------------------------------------
// * 200 MHz domain (FFSM):
//      Stage 1: Sample write + first read request                1 cycle
//      Stage 2: Address & coefficient pipe-up (ROM/BRAM)         6 cycles
//      Stage 3: Dual-tap bundle formation                        1 cycle
//      Stage 4: Drain/padding for center-tap alignment        ~ 9 cycles
//
// * Safe-sampling transfer (200 → 100 MHz):
//      Deterministic handshaked latency:                         1-2 cycles
//
// * 100 MHz domain (SFSM):
//      Stage 1: Receive bundle + latch DSP inputs                1 cycle
//      Stage 2: DSP accumulation (slice1 → slice2 chain)         1 cycle
//      Stage 3: Add rounding LSB                                 1 cycle
//      Stage 4: >>>17 alignment                                   1 cycle
//      Stage 5: Q1.15 saturation                                 1 cycle
//      Stage 6: Output register + ready pulse                    1 cycle
//
// * Total latency from sample_ready → valid y_out:
//      ≈ 20-23 cycles depending on alignment / drain window.
//
// All long combinational datapaths are broken by explicit register walls
// to ensure deterministic behavior across both clock domains.
// ====================================================================================




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
    
  
    //Internal Signals and registers
    //creating while initiating sample_mem
    wire signed [data_width-1:0] x_left_out_from_sample_mem, x_right_out_from_sample_mem;
   
    
   //Initiating coeffs_rom
   wire signed [coeff_width-1:0] filter_coeffs_out_from_coeffs_rom;
   reg en_coeff_from_fir_core=0;
   reg en_write_from_fir_core = 0;
   reg en_mem_read = 0;
   reg [$clog2(num_taps/2)-1:0]k_index_fast; 
  
    
    //initiating clk_sync
    wire sample_ready;
    
    //clock gen
    //get experience with using system generated clocks without using clk dividers
    //also this gives the most truthful value
    wire clk_audio_12M288 ;
    wire pll_locked ;
    wire sample_clock;
    wire pll_locked_2;
    wire clk_200;
    wire sys_clk, sys_rst;
  
    
    // One IBUF + BUFG in top-level for external 100 MHz clock
    wire clk_ibuf, clk_g;
    IBUF ibuf_clk (.I(clk), .O(clk_ibuf));
    BUFG bufg_clk (.I(clk_ibuf), .O(clk_g));     
    //hold FIR FSM in reset until PLL locks
    assign sys_rst = rst | ~pll_locked |~pll_locked_2;
    assign sys_clk = clk_g; 
    
    ////////////////////////////////////////////////////////
    // Feedback nets
    wire clkfb_audio, clkfb_audio_buf;
    wire clkfb_fast,  clkfb_fast_buf;
    BUFG fb_buf_audio (.I(clkfb_audio), .O(clkfb_audio_buf));
    BUFG fb_buf_fast (.I(clkfb_fast), .O(clkfb_fast_buf));
    
    //genarating 12.288MHz clock to make 48000kHz sample pulse
    clk_wiz_audio audio_pll_inst(
        //inputs 
        .clk_in1(clk_g),
        .reset(rst),
        //outputs
        .clk_out1(clk_audio_12M288),
        .clkfb_out (clkfb_audio),
        .clkfb_in  (clkfb_audio_buf),
        .locked(pll_locked)
       
    );
    
    //generating a 200MHz clock to read data twice fast as system clock.
    //2MACs work in parallel in 100MHz domain. 
   
    clk_wiz_200 fast_clk(
        .clkfb_in(clkfb_fast_buf),
        // Clock out ports
        .clk_out1(clk_200),
        .clkfb_out(clkfb_fast),
        // Status and control signals
        .reset(rst),
        .locked(pll_locked_2),
        // Clock in ports
        .clk_in1(clk_g)
    );
    
    //48000kHz clock
    adc_clock_sim s_clock(
    .clk_audio_12M288(clk_audio_12M288),
    .rst(sys_rst),
    .sample_rate_clock(sample_clock)
    );
    
    //Introducing single stable pulse to 200MHz clock at sample time
    clk_sync s_signal(
        //inputs
        .clk_fast(clk_200),
        .async_clk(sample_clock),
        .rst(sys_rst),
        //output
        .clean_pulse(sample_ready)
    );

    ////////////////////////////
   
    
    //sample mem initiation
    sample_mem #(
        .data_width(data_width) ,
        .filter_taps(num_taps) // order of the filter
    )buffer(
        //control inputs
        .clk(clk_200), // system clock @100MHz
        .rst(sys_rst), //global reset
        .en_write(en_write_from_fir_core), // 1 = write new sample
        .en_read(en_mem_read),
        // data input
        .x_in(x_in), // new sample from fir core
        .k_index(k_index_fast),
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
        .clk(clk_200), 
        //data inputs
        .en_read_co_eff(en_coeff_from_fir_core),
        .address(k_index_fast), 
        //output
        .coeff_out(filter_coeffs_out_from_coeffs_rom)
    );
   
   
 //=====================================================================================================================================================================//
 //================================================ 200Mhz FSM -> FAST FSM -> FFSM  ====================================================================================//          
 //=====================================================================================================================================================================//   
 //Sample buffer(x_sample values in BRAM) and coeffs(ROM) has same end-to-end 5 clock cycle delay.
 //There are 3 clock cycles from asserting point to load state. Need to stall 2 more cycles. result availble at 6th clock 
 
 //==================================NOTE: Drain stage will be optimized in phase 3 ====================================================================================//
// =====================================================================================================================================================================//
 reg signed [coeff_width-1:0] coeff_out1,coeff_out1_p,coeff_out1_r;
 reg signed [coeff_width-1:0] coeff_out2,coeff_out2_p,coeff_out2_r;
 reg counter;
 reg signed [data_width-1:0] xL1, xL1_p,xL1_r;
 reg signed [data_width-1:0] xL2, xL2_p,xL2_r;
 reg signed [data_width-1:0] xR1, xR1_p,xR1_r;
 reg signed [data_width-1:0] xR2, xR2_p,xR2_r;
 reg wrt_flg, batch_ready;
 //reg first_read_from_fir_core; debugging purposes
 
 reg [3:0]stall_cycle;
 reg [4:0]drain;   
    
// reg[9:0] counterdegugg;  debugging purposes
   localparam FFSM_idle = 0, FFSM_write = 1, FFSM_load = 2, FFSM_drain =3, FFSM_stop = 4;
   
   (* fsm_encoding = "user" *) reg [2:0] FFSM_state = 0;
   
   always @(posedge clk_200)begin//s1
    if(sys_rst)begin//s2
        counter<=0;
        coeff_out1<=0;
        coeff_out2<=0;
        k_index_fast <= 0;
        xL1 <= 0;
        xL2 <= 0;
        xR1 <= 0;
        xR2 <= 0;
        wrt_flg <=0;
        batch_ready<=0;
        en_mem_read<=0;
        en_coeff_from_fir_core<=0;
        stall_cycle<=0;
        drain<=0;
        //counterdegugg<=0;
        //first_read_from_fir_core<=0; debugging purposes
    end else begin//e2,s3
        case (FFSM_state) 
        
            FFSM_idle: begin//s4
               //counterdegugg<=0; debugg line
               counter<=0;
               coeff_out1<=0;
               coeff_out2<=0;
               k_index_fast <= 0;
               xL1 <= 0;
               xL2 <= 0;
               xR1 <= 0;
               xR2 <= 0;
               wrt_flg <=0;
               batch_ready<=0;
               en_coeff_from_fir_core<=0;
               en_write_from_fir_core <= 0;
               stall_cycle<=0;
               counter <= 0;
               if(sample_ready)begin//s5
                en_write_from_fir_core <= 1;
                wrt_flg<=1;
                en_coeff_from_fir_core<=1;
                en_mem_read<=1;
                drain <= 9;
                FFSM_state <= FFSM_write;
               end else begin//e5, s6
                FFSM_state <= FFSM_idle;
               end //e6    
            end//e4
        
            FFSM_write: begin//s7
               k_index_fast <= k_index_fast +1;
               en_write_from_fir_core <= 0;
               FFSM_state<=FFSM_load;                 
            end
        
            FFSM_load: begin//s10
                //Need 7 more cycles of stalls to capture BRAM and COEFF ROM values at 9th cycle
                if(stall_cycle < 6)begin
                    k_index_fast <= k_index_fast +1;
                    stall_cycle <= stall_cycle+1;
                    FFSM_state<=FFSM_load;
                end else 
                if(stall_cycle==6)begin//s12
                   if(k_index_fast<=158) begin  //s14  //158
                     if(counter == 0)begin//s15
                            coeff_out1<=filter_coeffs_out_from_coeffs_rom;
                            xL1 <= x_left_out_from_sample_mem;
                            xR1 <= x_right_out_from_sample_mem;
                            //first_read_from_fir_core<=1; debugg line
                            if(k_index_fast == 158)begin
                                k_index_fast<=0;
                                batch_ready<=0;
                                //en_coeff_from_fir_core<=0; debugg line
                                //en_mem_read<=0; debugg line
                                FFSM_state<=FFSM_drain;
                            end else begin
                                k_index_fast <= k_index_fast +1;
                                counter <= 1;
                                batch_ready<=0;
                                FFSM_state<=FFSM_load;
                            end    
                        end //e15
                        else if(counter == 1)begin//s16
                            coeff_out2<=filter_coeffs_out_from_coeffs_rom;  //159th value comes here 
                            xL2 <= x_left_out_from_sample_mem;
                            xR2 <= x_right_out_from_sample_mem;
                            if(k_index_fast == 158)begin
                                en_coeff_from_fir_core<=0;
                                k_index_fast<=0;
                                en_mem_read<=0;
                                batch_ready<=1;
                                counter <= 0;
                                FFSM_state<=FFSM_drain;
                            end else begin
                                k_index_fast <= k_index_fast +1;
                                counter <= 0;
                                batch_ready<=1;
                                FFSM_state<=FFSM_load;
                            end    
                        end //e16
                    end //e14
                end     
                 //e20 
            end
            
            FFSM_drain: begin
                //counterdegugg<=counterdegugg+1; debugg line
                if(drain == 9)begin //FFSM load when count ==0
                    coeff_out1<=filter_coeffs_out_from_coeffs_rom;
                    xL1 <= x_left_out_from_sample_mem;
                    xR1 <= x_right_out_from_sample_mem;
                    drain <= drain -1;
                    batch_ready<=0;
                    FFSM_state<=FFSM_drain;
                end else
                if(drain == 8)begin
                    coeff_out2<=filter_coeffs_out_from_coeffs_rom;
                    xL2 <= x_left_out_from_sample_mem;
                    xR2 <= x_right_out_from_sample_mem;
                    drain <= drain -1;
                    batch_ready<=1;
                    FFSM_state<=FFSM_drain;
                end else 
                if(drain == 7)begin
                    coeff_out1<=filter_coeffs_out_from_coeffs_rom;
                    xL1 <= x_left_out_from_sample_mem;
                    xR1 <= x_right_out_from_sample_mem;
                    drain <= drain -1;
                    batch_ready<=0;
                    FFSM_state<=FFSM_drain;
                end else
                if(drain == 6)begin
                    coeff_out2<=filter_coeffs_out_from_coeffs_rom;
                    xL2 <= x_left_out_from_sample_mem;
                    xR2 <= x_right_out_from_sample_mem;
                    drain <= drain -1;
                    batch_ready<=1;
                    FFSM_state<=FFSM_drain;
                    
                end else if(drain==5)begin
                    coeff_out1<=filter_coeffs_out_from_coeffs_rom;
                    xL1 <= x_left_out_from_sample_mem;
                    xR1 <= x_right_out_from_sample_mem;
                    drain <= drain -1;
                    batch_ready<=0;
                    FFSM_state<=FFSM_drain;
                end else
                if(drain == 4)begin 
                    coeff_out2<=filter_coeffs_out_from_coeffs_rom;
                    xL2 <= x_left_out_from_sample_mem;
                    xR2 <= x_right_out_from_sample_mem; // only need one value here. center tap
                    drain <= drain -1;
                    batch_ready<=1;
                    FFSM_state<=FFSM_drain;
                   // en_coeff_from_fir_core<=0;
                end else if(drain==3)begin
                 //This batch gets the values of k =159, we don't need them
                //By setting them to zero now will simple the mac mode changes later.  
                   coeff_out1<=filter_coeffs_out_from_coeffs_rom;
                    xL1 <= x_left_out_from_sample_mem;
                    xR1 <= 16'sd0;
                    batch_ready<=0;
                    drain <= drain -1;
                    FFSM_state<=FFSM_drain;
                end else
                if(drain == 2)begin
                    coeff_out2<=18'sd0;
                    xL2 <= 16'sd0;
                    xR2 <= 16'sd0; 
                    drain <= drain -1; // keep sending batch ready pulse to transmit data to 100MHz domain
                    batch_ready<=1;
                    FFSM_state<=FFSM_drain;  
                end else if(drain == 1)begin
                    coeff_out1<=18'sd0;
                    xL1 <= 16'sd0;
                    xR1 <= 16'sd0;
                    drain <= drain -1;
                    batch_ready<=0;
                    FFSM_state<=FFSM_drain;
                end else if(drain == 0)begin
                    coeff_out2<=18'sd0;
                    xL2 <= 16'sd0;
                    xR2 <= 16'sd0;
                    batch_ready<=1;
                    FFSM_state<=FFSM_idle;
                end else begin
                batch_ready<=0;
                FFSM_state<=FFSM_drain;
                end
            end  
        endcase
        end //e3
     end 
    
    //======================================================END OF FFSM===============================================================================================//
     
    /////////////////////////Copying xL, xR, and coeff out to be passed to 100MHz clock domain//////////////////////////////////////////////
    // Thess registers get updates every two 200MHz clock cycles                                                                          //  
    //Also uses snapshot method to pass values to 100MHz domain. Since clocks are async values changes in between 100MHz clock period.    //
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    reg [99:0] bundle;//sending one
    reg [6:0]sent_counter; 
    reg take_batch; // This get asserted when batch is bundled in. safe sample function will no take a snapshot of this bundle and hold it steady.
   
    always @(posedge clk_200)begin
        if(sys_rst)begin
          coeff_out1_p<=0;
          coeff_out2_p<=0;
          xL1_p <= 0;
          xL2_p <= 0;
          xR1_p <= 0;
          xR2_p <= 0;
          take_batch<=0;
          sent_counter<=0;
          bundle<=0;  
        end else if(batch_ready && sent_counter <= 80 )begin
            coeff_out1_p <= coeff_out1;
            coeff_out2_p <= coeff_out2;
            xL1_p <= xL1;
            xL2_p <= xL2;
            xR1_p <= xR1;
            xR2_p <= xR2;
            bundle<={$unsigned(xL1_p[15:0]),$unsigned(xR1_p[15:0]),$unsigned(coeff_out1_p[17:0]),$unsigned(xL2_p[15:0]),$unsigned(xR2_p[15:0]),$unsigned(coeff_out2_p[17:0])};
            take_batch <= 1;
            sent_counter <= sent_counter +1;
            end else if(sent_counter > 80) begin
                take_batch <= 0;        
                sent_counter <= 0;
            end else begin
                take_batch<=0;
            end 
    end 
   
   //=======================================================================================================================================================================//      
   //================================================= MAC [DSP48E1 Slices]==================================================================================================//          
   //========================================================================================================================================================================// 
   //Explicit MACs (Internal regs active for pipelining [helps acheive high speed data transfers] )//
   //Using two MAC's parallely two increase throughput//
   
   //DSP Control Outputs//
   wire signed [accumulator_width-1:0] slice1_rslt;
   wire signed [accumulator_width-1:0] slice2_rslt;
   wire dsp_en = 1'b1;  // FSM's active signal
   reg dsp_en_1;
   wire rst_fsm, rst_mac; // rest for macs
   reg rst_set,rst_mac1; // rest from SFSM
   
   assign rst_fsm = rst_set | sys_rst;
   assign rst_mac = rst_fsm | rst_mac1;
   //first mac
   DSP48E1 #(
    .AREG(1), .BREG(2),.DREG(1),
    .ADREG(1),.MREG(1),.PREG(1),
    .INMODEREG(1), .OPMODEREG(1), .ALUMODEREG(1),
    .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
    .USE_DPORT("TRUE"),
    .USE_MULT("MULTIPLY"),
    .USE_SIMD("ONE48") 
   )mac1(
    .CLK(sys_clk),
    .RSTP(rst_fsm),
    .RSTM(rst_fsm),
    .RSTB(rst_fsm),
    .RSTD(rst_mac),
    .RSTA(rst_mac),
    .RSTALUMODE(rst_fsm), .RSTINMODE(rst_fsm), .RSTCTRL(rst_fsm),.RSTALLCARRYIN(rst_fsm),
    // CE pins - MUST be driven in sim
    .CEA2(dsp_en_1), 
     .CEB2(dsp_en), .CEB1(dsp_en_1),
    .CED (dsp_en_1), .CEAD(dsp_en),
    .CEM (dsp_en), .CEP (dsp_en),
    .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECTRL(1'b1),.CECARRYIN(1'b1),
    

    .A({{14{xL1_r[15]}}, xL1_r}),   // 16-bit → 30-bit (sign-extend)
    .D({{9{xR1_r[15]}}, xR1_r}),    // 16-bit → 25-bit (sign-extend)
    .B(coeff_out1_r),//coeff_out1_r
    
    .CARRYIN(1'b0),
    .CARRYINSEL(3'b000),
    //control signals
    .INMODE(5'b00100),
    .ALUMODE(4'b0000),
    .OPMODE(7'b0000001),
    
    //outputs
    .P(slice1_rslt)
    
   );
   
   //second mac
   DSP48E1 #(
    .AREG(1), 
    .BREG(2),
    .DREG(1),
    .ADREG(1),
    .MREG(1),
    .CREG(1),
    .PREG(1),
    .INMODEREG(1), .OPMODEREG(1), .ALUMODEREG(1),
    .A_INPUT("DIRECT"), .B_INPUT("DIRECT"),
    .USE_DPORT("TRUE"),
    .USE_MULT("MULTIPLY"),
    .USE_SIMD("ONE48") 
   )mac2(
    .CLK(sys_clk),
    .RSTP(rst_fsm),
    .RSTM(rst_fsm),
    .RSTB(rst_mac),
    .RSTD(rst_fsm),
    .RSTA(rst_fsm),
    .RSTC(rst_fsm),
    .RSTALUMODE(rst_fsm), .RSTINMODE(rst_fsm), .RSTCTRL(rst_fsm),.RSTALLCARRYIN(rst_fsm),
    
    // CE pins - MUST be driven in sim
    .CEA2(dsp_en), .CEC(1'b1),
    .CEB1(dsp_en), .CEB2(dsp_en),
    .CED (dsp_en), .CEAD(dsp_en),
    .CEM (dsp_en), .CEP (dsp_en),
    .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECTRL(1'b1),.CECARRYIN(1'b1),
    .A({{14{xL2_r[15]}}, xL2_r}),   // 16-bit → 30-bit (sign-extend)
    .D({{9{xR2_r[15]}}, xR2_r}),    // 16-bit → 25-bit (sign-extend)
    .B(coeff_out2_r),//coeff_out2_r
    .C(slice1_rslt),
    
    .CARRYIN(1'b0),
    .CARRYINSEL(3'b000),
    //control signals
    .INMODE(5'b00100),
    .ALUMODE(4'b0000),
    .OPMODE(7'b0101101),
    
    //outputs
    .P(slice2_rslt)
    
   );
 //======================================================END OF MACs==================================================================================================//
 
 //================================ Safe Data Transfer to 100MHz domain from 200MHz ==================================================================================//
 
   wire[99:0] bundle_s;//sending one
   wire[99:0] bundle_r; //recieving one
   wire done;
   assign bundle_s = bundle; //   99:84, 83:68, 67:50, 49:34, 33:18, 17:0 
   
   
   safe_sample#(

    .WIDTH(100)
    )safe_1(
    
    .clk200(clk_200),
    .clk100(sys_clk),
    .rst(sys_rst),
    
    .data_in(bundle_s),
    .ready(take_batch),
    .done(done),
    .data_out(bundle_r)

    );
    
 //===================================================================================================================================================================//
 //================================================ 100Mhz FSM -> SYSTEM FSM -> SFSM  ================================================================================//          
 //===================================================================================================================================================================//
   
   
   
   reg [6:0]batch_count;
   reg signed [accumulator_width-1:0] accumulated_results;
   reg signed [accumulator_width-1:0] rounded_acc;
   reg signed [31:0] shifted_val;
   reg signed [data_width-1: 0] y_sat;
   
   localparam SFSM_idle = 0, SFSM_mid = 1, SFSM_acc = 2, SFSM_shift = 4, SFSM_rounded = 3, SFSM_saturate=5, SFSM_final = 6 ;
   
   (* fsm_encoding = "user" *) reg [2:0] SFSM_state = 0;
   
   always@(posedge sys_clk)begin
    if(sys_rst)begin
       coeff_out1_r <= 0;
       coeff_out2_r <= 0;
       xL1_r<= 0;
       xL2_r<= 0;
       xR1_r<= 0;
       xR2_r<= 0;
       rst_set <=0;
       accumulated_results<=0;
       rounded_acc <= 0;
       output_ready <= 0;
       dsp_en_1<=0;
    end else begin
        
        case(SFSM_state) 
        
          SFSM_idle: begin
            coeff_out1_r <= 0;
            coeff_out2_r <= 0;
            xL1_r<= 0;
            xL2_r<= 0;
            xR1_r<= 0;
            xR2_r<= 0; 
            output_ready <= 0;
            dsp_en_1<=0; 
            if(done)begin
                rst_set <=0;
                rst_mac1 <=0; 
                batch_count<=0;
                SFSM_state<=SFSM_mid;
            end else begin
                SFSM_state<=SFSM_idle;    
            end       
          end //end of idle 
          
          SFSM_mid: begin
            if(batch_count <= 80)begin      
                coeff_out1_r <= bundle_r[67:50];
                coeff_out2_r <= bundle_r[17:0];
                xL1_r<= bundle_r[99:84];
                xL2_r<= bundle_r[49:34];
                xR1_r<= bundle_r[83:68];
                xR2_r<= bundle_r[33:18];
                dsp_en_1<=1;
                batch_count<=batch_count+1;
                SFSM_state<=SFSM_mid;
            end else if(batch_count ==86) begin // stall 4 cycles. final ready at 5th cycle
                SFSM_state<=SFSM_acc;
            end else begin
               rst_mac1 <=1; 
               batch_count<=batch_count+1;
               SFSM_state<=SFSM_mid;
            end    
          end//end of mid state
        
          SFSM_acc: begin
            accumulated_results <= slice2_rslt;
            rst_set <=1;               
            SFSM_state<=SFSM_rounded;
            end//end of acc
         
          SFSM_rounded: begin
            rounded_acc <= accumulated_results + (1 << 16);               
            SFSM_state<=SFSM_shift;
            end//end of acc   
         
          SFSM_shift: begin
            shifted_val <= (rounded_acc >>> 17);               
            SFSM_state<=SFSM_saturate;
            end//e
            
          SFSM_saturate:begin
            if(shifted_val > 32'sd32767)begin
                y_sat <= 16'sd32767;
            end else if (shifted_val < -32'sd32767)begin
                y_sat <= -16'sd32768;
            end else begin
                y_sat <= shifted_val[15:0];
            end
            SFSM_state<=SFSM_final;         
         end
          SFSM_final: begin
            batch_count<=0;
            y_out <= y_sat;
            output_ready <= 1;               
            SFSM_state<=SFSM_idle;
            end//e     
        endcase
    end //end of else after the reset
   end //end of always at begin 
          
   endmodule
   
   
   
   
  
    
   
     
     
 

