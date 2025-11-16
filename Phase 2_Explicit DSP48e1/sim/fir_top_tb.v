`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rajith Senaratna
// Create Date: 11/03/2025 03:22:15 PM
// Design Name: FIR lowpass filter 317 taps
// Module Name: fir_top_tb
// Target Devices: Arty s7 -50
// Description: Testbench for FIR top module that simulates real-time 48 kHz input 
//              streaming and logs filtered outputs to file. Generates the 100 MHz 
//              system clock and feeds one new input sample every 2083 cycles. 
//              Automatically stops after all samples are processed and FIR tail is 
//              flushed to verify full pipeline behavior and latency correctness.
//////////////////////////////////////////////////////////////////////////////////////




module fir_top_tb;

    // ------------------------------------------------------------------------
    // Parameters (EDIT NUM_SAMPLES to your input file length)
    // ------------------------------------------------------------------------
    parameter integer DATA_WIDTH     = 16;
    parameter integer N_TAPS         = 317;
    parameter integer NUM_SAMPLES    = 454560;     // <-- set to your input lines
    parameter integer CLK_HZ         = 100000000;
    parameter integer CLK_PERIOD_NS  = 10;         // 100 MHz -> 10 ns
    parameter integer FS_HZ          = 48000;     // input sample rate
    localparam integer CYCLES_PER_SAMPLE = CLK_HZ / FS_HZ; // 2083 at 100MHz/48kHz

    
    // DUT I/O
    reg                              clk;
    reg                              rst;
    reg  signed [DATA_WIDTH-1:0]     x_in;
    wire signed [DATA_WIDTH-1:0]     y_out;
    wire                             output_ready;


    // DUT Instance
    fir_top DUT (
        .clk(clk),
        .rst          (rst),
        .x_in         (x_in),
        .y_out        (y_out),
        .y_valid (output_ready)
    );


    // Input Memory
    reg signed [DATA_WIDTH-1:0] input_mem [0:NUM_SAMPLES-1];
    integer input_index = 0;

    initial begin
        $display("INFO: Loading input samples from input_clip_48k_fixed.mem ...");
        $readmemh("input_clip_48k_fixed.mem", input_mem);
        $display("INFO: Input file load request for %0d samples.", NUM_SAMPLES);
    end


    // Clock / Reset
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    initial begin
        rst = 1;
        #50;          // 50 ns reset
        rst = 0;
    end


    // Feed Inputs at 48 kHz (one new sample every CYCLES_PER_SAMPLE clocks)
 
    
    
    
    integer sample_timer = 0;

    always @(posedge clk) begin
        if (rst) begin
            input_index  <= 0;
            x_in         <= {DATA_WIDTH{1'b0}};
            sample_timer <= 0;
        end else begin
            if (sample_timer == 0) begin
                if (input_index < NUM_SAMPLES) begin
                    x_in        <= input_mem[input_index];
                    input_index <= input_index + 1;
                end
            end
            if (sample_timer == (CYCLES_PER_SAMPLE-1))
                sample_timer <= 0;
            else
                sample_timer <= sample_timer + 1;
        end
    end

    
    // Output Logging
  
    integer outfile;
    integer outputs_seen = 0;

    initial begin
        // Change this to a relative path if your simulator cannot open absolute paths
        outfile = $fopen("D:/Xilinx_Projects/FIR_Filter/fir_lowpass_317taps/golden_out_verilog.txt", "w");
        if (outfile == 0) begin
            $display("ERROR: Cannot open output file for writing.");
            $stop;
        end else begin
            $display("INFO: Opened golden_out_verilog.txt for writing.");
        end
    end


    
    reg [9:0] outready;
    
   initial begin
            outready = 0;
    end    

    always @(posedge clk) begin
        if (!rst && output_ready) begin
            outready <= outready +1;
            //$display("out_ready: ", outready);
            $fdisplay(outfile, "%h", y_out);  // hex, two's complement
            outputs_seen <= outputs_seen + 1;
            if ((outputs_seen % 1000) == 0)
                $display("INFO: Captured %0d outputs", outputs_seen);
        end
    end

    // ------------------------------------------------------------------------
    // End condition:
    // 1) Wait until all inputs sent
    // 2) Wait until at least NUM_SAMPLES - (N_TAPS-1) outputs captured
    //    (accounts for group delay suppression in many FIR cores)
    // 3) Small extra time-based flush as margin
    // ------------------------------------------------------------------------
    initial begin
        // Wait until the last input has been presented
        wait (input_index >= NUM_SAMPLES);

        // Expect roughly one valid output per input, minus group delay
        wait (outputs_seen >= (NUM_SAMPLES - (N_TAPS - 1)));

        // Extra margin: ~16 samples worth to be safe
        repeat (16 * CYCLES_PER_SAMPLE) @(posedge clk);

        $display("INFO: Done. inputs=%0d, outputs=%0d", input_index, outputs_seen);
        $fclose(outfile);
        $stop;
    end

endmodule


