`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/02/2025 12:02:50 AM
// Design Name: FIR lowpass filter 317 taps
// Module Name: sample_mem
// Target Devices: Arty s7 -50
// Description: Dual-read, single-write circular buffer for FIR samples,
//              works as simple dual-port RAM 
///////////////////////////////////////////////////////////////////////////////////////

module sample_mem #(
    parameter integer data_width = 16, //input data Q1.15
    parameter integer filter_taps    = 317 // order of the filter
)(
    //control inputs
    input  wire clk, // system clock @100MHz
    input  wire rst, //global reset
    input  wire en_write, // 1 = write new sample
    input wire update_ptr,
    
    // data input
    input  wire signed [data_width-1:0] x_in, // new sample from fir core
    input  wire [$clog2(filter_taps/2)-1:0] k_index,
    
    // Read data outputs to the fir core
    output reg signed [data_width-1:0] x_left,
    output reg signed [data_width-1:0] x_right

);

    // Circular buffer RAM
    reg signed [data_width-1:0] memory [0:filter_taps-1]; //register array to carry memory
    reg [$clog2(filter_taps)-1:0] write_ptr;// circular index, this points to where the next input sample will be written -> after it reaches to NUM_TAPS - 1, return back to 0.
    reg [$clog2(filter_taps)-1:0] address_left; // address of x[n-k] from fir core , $clog2 determines the number of bits needed automatically.
    reg [$clog2(filter_taps)-1:0] address_right;// address of x[n- (M-1-k)] from fir core
    wire [$clog2(filter_taps):0] tmp;
    reg [$clog2(filter_taps)-1:0] write_ptr_new = 0;
    // Write new sample into circular buffer
    always @(posedge clk) begin
        if (rst) begin
            write_ptr <= 0;
        end else if (en_write) begin
            memory[write_ptr] <= x_in;
            // increment with wrap-around
            if (write_ptr == filter_taps-1)begin
                write_ptr <= 0;
            end else begin    
                write_ptr <= write_ptr + 1;
            end   
        end
        if (write_ptr==0)begin
            write_ptr_new <= filter_taps-1;
        end else if(update_ptr) begin
            write_ptr_new <= write_ptr +1;
        end       
    end
    
    // Compute symmetric addresses 
    
    assign tmp = write_ptr_new + 1 + k_index;
    
    always @(*) begin
        // LEFT side
        if (write_ptr_new >= k_index)begin
            address_left = write_ptr_new - k_index;
        end else begin
            address_left = write_ptr_new + filter_taps - k_index;
        end
        // RIGHT side
       
        if (tmp >= filter_taps)begin
            address_right = tmp - filter_taps;
        end else begin
            address_right = tmp[9:0];
        end    
    end
    // Dual synchronous read 
    always @(posedge clk) begin
        x_left  <= memory[address_left];
        x_right <= memory[address_right];
    end
    
    
endmodule