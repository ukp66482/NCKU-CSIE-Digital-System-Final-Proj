`timescale 1ns/1ps
`define CYCLE 10
`define MAX_CYCLE 1000000

module testfixture;

// conv ports
reg clk = 0;
reg rst_n = 0;
reg start = 0;
reg done;
reg bram0_en;
reg [31:0] bram0_addr;
reg [31:0] bram0_dout;
reg [3:0]  bram1_we;
reg [31:0] bram1_addr;
reg [31:0] bram1_din;

// BRAM
reg [31:0] bram0 [65535:0];
reg [31:0] bram1 [65535:0];
reg [31:0] golden_data [65535:0];

integer error = 0;
integer cycle_count = 0;

initial begin
`ifdef tb1
    `define IMG_HEIGHT 182
    `define IMG_WIDTH 242
    $readmemh("bram0.hex", bram0);
    $readmemh("bram1.hex", bram1);
    $readmemh("golden.hex", golden_data);
`else
    `define IMG_HEIGHT 18
    `define IMG_WIDTH 18
    $readmemh("bram0.hex", bram0);
    $readmemh("bram1.hex", bram1);
    $readmemh("golden.hex", golden_data);
`endif
end

conv #(
    .IMG_WIDTH  (`IMG_WIDTH),
    .IMG_HEIGHT (`IMG_HEIGHT)
) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .start       (start),
    .done        (done),
    .bram0_addr  (bram0_addr),
    .bram0_dout  (bram0_dout),
    .bram0_en    (bram0_en),
    .bram1_addr  (bram1_addr),
    .bram1_din   (bram1_din),
    .bram1_we    (bram1_we)
);

// bram0
always @(posedge clk) begin
    if (bram0_en) begin
        bram0_dout <= bram0[bram0_addr[17:2]];
    end
end

// bram1
always @(posedge clk) begin
    if (|bram1_we) begin
        bram1[bram1_addr[17:2]] <= bram1_din;
    end
end

always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
end

// check result
initial begin
    wait (done == 1);
    #(`CYCLE*2); // wait for write back
    for (integer i = 0; i < 65536; i = i + 1) begin
        if (bram1[i] !== golden_data[i]) begin
            $display("Test Failed at address %h(%d): expected %h, got %h", i << 2, i, golden_data[i], bram1[i]);
            error = error + 1;
        end
    end

    if (error == 0) begin
		$display("                   //////////////////////////               ");
		$display("                   /                        /       |\__||  ");
		$display("                   /  Congratulations !!    /      / O.O  | ");
		$display("                   /                        /    /_____   | ");
		$display("                   /  Simulation PASS !!    /   /^ ^ ^ \\  |");
		$display("                   /                        /  |^ ^ ^ ^ |w| ");
		$display("                   //////////////////////////   \\m___m__|_|");
        $display("Total Cycles: %d", cycle_count);
		$display("\n");
    end else begin
		$display("There are %d errors!\n", error);
		$display("                   //////////////////////////               ");
		$display("                   /                        /       |\__||  ");
		$display("                   /  OOPS !!               /      / X.X  | ");
		$display("                   /                        /    /_____   | ");
		$display("                   /  Simulation Failed !!  /   /^ ^ ^ \\  |");
		$display("                   /                        /  |^ ^ ^ ^ |w| ");
		$display("                   //////////////////////////   \\m___m__|_|");
		$display("\n");
    end
    $finish;
end

always #(`CYCLE/2) clk = ~clk;

initial begin
    #(`CYCLE*2) rst_n = 1;
end

initial begin
    #(`CYCLE*5) start = 1;
    #(`CYCLE)   start = 0;
end

initial begin
    #(`CYCLE*`MAX_CYCLE);
    $display("Error: Simulation Timeout!");
    $finish;
end

initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, testfixture);
end

endmodule
