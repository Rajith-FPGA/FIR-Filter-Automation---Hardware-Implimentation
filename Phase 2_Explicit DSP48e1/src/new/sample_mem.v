`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/02/2025 12:02:50 AM
// Design Name: FIR lowpass filter 317 taps
// Module Name: sample_mem
// Target Devices: Arty s7 -50
// Description: Dual-read, single-write circular buffer for FIR samples,
//              works as simple dual-port RAM 
// Update(11/13/2025): synchronized the sample mem / Latency: 8 clock cycles.
///////////////////////////////////////////////////////////////////////////////////////
// ====================================================================================
// LATENCY SUMMARY [Excluding Enabling Cycle from FSM]
// ------------------------------------------------------------------------------------
// * Internal pipeline (k → tmp → address):        6 cycles
// * BRAM registered read output:                 +1 cycle
// * Total from en_read assert → valid output:    7 cycles
// * FSM capture (optional next edge):            8 cycles total
//
// This guarantees all address generation logic is registered,
// breaking long intra-clock timing paths and ensuring the design
// meets 200 MHz closure.
//
// ====================================================================================

module sample_mem #(
    parameter integer data_width = 16, //input data Q1.15
    parameter integer filter_taps    = 317 // order of the filter
)(
    //control inputs
    input  wire clk, // system clock @100MHz
    input  wire rst, //global reset
    input  wire en_write, // 1 = write new sample
    input wire en_read,
    // data input
    input  wire signed [data_width-1:0] x_in, // new sample from fir core
    input  wire [$clog2(filter_taps/2)-1:0] k_index,
    
    // Read data outputs to the fir core
    output reg signed [data_width-1:0] x_left,
    output reg signed [data_width-1:0] x_right

);

(*ram_style = "block"*)reg signed [data_width-1:0] memory [0:filter_taps-1]; //register array to carry memory
    reg [$clog2(filter_taps)-1:0] write_ptr;// circular index, this points to where the next input sample will be written -> after it reaches to NUM_TAPS - 1, return back to 0.
    reg [$clog2(filter_taps)-1:0] address_left; // address of x[n-k] from fir core , $clog2 determines the number of bits needed automatically.
    reg [$clog2(filter_taps)-1:0] address_right;// address of x[n- (M-1-k)] from fir core
    
    reg [$clog2(filter_taps)-1:0] address_left_r, address_right_r;
   
    // Write new sample into circular buffer
    
    reg [$clog2(filter_taps/2)-1:0] k_index_1;
    reg [$clog2(filter_taps/2)-1:0] k_index_w;
     reg [$clog2(filter_taps)-1:0] write_ptr_1; 
    always @(posedge clk) begin
        if (rst) begin
            write_ptr <= 0;
            k_index_1 <=0;
            write_ptr_1 <=0;
        end else if (en_write) begin
            memory[write_ptr] <= x_in;
            // increment with wrap-around
            if (write_ptr == filter_taps-1)begin
                write_ptr <= 0;
                write_ptr_1 <= write_ptr;
                k_index_1 <= k_index;
            end else begin    
               write_ptr <= write_ptr +1;
               write_ptr_1 <= write_ptr;
               k_index_1 <= k_index;  
            end
        end else begin
            k_index_1 <= k_index;
        end                    
    end
    //making write_p
    reg [$clog2(filter_taps)-1:0]   write_ptr_new;
    reg [$clog2(filter_taps/2)-1:0] k_index_2; 
    reg [$clog2(filter_taps)-1:0] write_ptr_2;
   
    //reg [$clog2(filter_taps)-1:0] write_ptr_new_n;
    always@(posedge clk)begin
        if(rst)begin
            k_index_2 <= 0;
            write_ptr_2<=0;
            write_ptr_new <=0;                 
        end else if(write_ptr_1 == 0) begin
            k_index_2 <= k_index_1;
            write_ptr_2 <= write_ptr_1;
            write_ptr_new <= write_ptr_1;
        end else begin
            k_index_2 <= k_index_1;
            write_ptr_2 <= write_ptr_1;
            write_ptr_new <= write_ptr_1 - 1;        
        end    
           
   end
   

   
     //making temp to track left side                    
    //1-clk delay
    reg [$clog2(filter_taps):0]     tmp;   
    reg [$clog2(filter_taps)-1:0]   write_ptr_new_1;
    reg [$clog2(filter_taps)-1:0]   write_ptr_3;
    reg [$clog2(filter_taps/2)-1:0] k_index_3;
    always@(posedge clk)begin
        if(rst)begin
            tmp <= 0;
            k_index_3<=0;
            write_ptr_new_1<=0;
            write_ptr_3 <=0;            
        end else begin
           if(write_ptr_2>0)begin
                if(write_ptr_new > k_index_2)begin
                    tmp <= write_ptr_new -1;
                    k_index_3 <= k_index_2 ;
                    write_ptr_new_1 <= write_ptr_new;
                    write_ptr_3 <= write_ptr_2;
                end else begin
                    tmp <= filter_taps-1;                   
                    k_index_3 <= k_index_2 ;
                    write_ptr_new_1 <= write_ptr_new;
                    write_ptr_3 <= write_ptr_2;
                end
           end else begin
               tmp <= filter_taps -1;
               k_index_3 <= k_index_2 ;
               write_ptr_new_1<=write_ptr_new;
               write_ptr_3 <= write_ptr_2;
           end     
        end          
    end      
    reg [$clog2(filter_taps)-1:0] write_ptr_4; 
    reg [$clog2(filter_taps)-1:0] commn_math; // to meet timing do the math prior to comparing and assigning
    reg signed [$clog2(filter_taps)-1:0] commn_math2; // to meet timing
    reg [$clog2(filter_taps)-1:0] write_ptr_new_2 = 0;
    reg [$clog2(filter_taps/2)-1:0] k_index_4;
    
   
    always@(posedge clk)begin
        if(rst)begin
            commn_math<=0;
            commn_math2<=0;
            write_ptr_new_2<=0;
            k_index_4<=0;
            write_ptr_4<=0;
        end else begin
            commn_math <= write_ptr_new_1 + k_index_3;
            commn_math2<= tmp - k_index_3;
            write_ptr_new_2 <= write_ptr_new_1;
            k_index_4 <= k_index_3;
            write_ptr_4<=write_ptr_3;
        end
    end
 
    //let address left be temp/ address right w_P [writing purposes, not relavent for general reading]      
    //Computing left and right address
    always @(posedge clk ) begin
         if(rst )begin
            address_left_r <= 0;   
            address_right_r <= 0;
        end else if(write_ptr_4>0)begin
            if (write_ptr_new_2 > k_index_4)begin
                if((commn_math) > ((filter_taps-1)))begin
                    address_right_r <= commn_math - filter_taps;
                    address_left_r <= commn_math2;
                   
                end else begin
                    address_right_r <= commn_math;
                    address_left_r <= commn_math2;
                   
                end 
            end else begin
                address_right_r <= commn_math;
                address_left_r <= commn_math2 + write_ptr_new_2;
              
                
            end      
        end else begin
            address_right_r <= commn_math;
            address_left_r <= commn_math2;
            
            
      end
   end    
    
    
    always @(posedge clk) begin
        if(rst )begin
            address_left <= 0;   
            address_right<= 0;
        end else begin
            address_left <= address_left_r;    
            address_right<= address_right_r;
        end    
    end
    
    // delaying the control signal by 6 cycles
    reg [5:0] en_read_pipe;          // 6-bit shift register
    always @(posedge clk) begin
        if (rst)begin 
            en_read_pipe <= 6'b000000;
        end else begin
            en_read_pipe <= {en_read_pipe[4:0], en_read};
        end
     end   

    wire en_read_new = en_read_pipe[5];  // delaying signal for 6 cycles
    // Dual synchronous read 
    always @(posedge clk) begin
       if(rst )begin
            x_left <= 0;   
            x_right<= 0;
        end else if(en_read_new)begin
         x_left  <= memory[address_left];    
         x_right <= memory[address_right];       
          //x_left  <= address_left;    //debugg lines //used to verify address generator, and mac behaviour
         // x_right <= address_right; //debugg lines
 
        end
    end
endmodule