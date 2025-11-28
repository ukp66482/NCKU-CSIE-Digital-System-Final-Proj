module conv #(
    parameter IMG_WIDTH  = 32,
    parameter IMG_HEIGHT = 32
)(
    input clk,
    input rst_n,

    input  start,
    output done,

    // BRAM0 Ports
    output reg [31:0] bram0_addr,
    input      [31:0] bram0_dout,
    output            bram0_en,

    // BRAM1 Ports
    output reg [31:0] bram1_addr,
    output reg [31:0] bram1_din,
    output reg [3:0]  bram1_we
);

// state
localparam IDLE  = 3'd0;
localparam READ  = 3'd1;
localparam WRITE = 3'd2;
localparam DONE  = 3'd3;

reg [2:0] state, next_state;

reg [7:0] kernel1 [8:0]; // vertical Sobel kernel
reg [7:0] kernel2 [8:0]; // horizontal Sobel kernel

reg [$clog2(IMG_WIDTH)-1:0] x;  // current x position
reg [$clog2(IMG_HEIGHT)-1:0] y; // current y position

reg [3:0] counter;

reg signed [15:0] mul1;
reg signed [15:0] mul2;
reg signed [15:0] acc1;
reg signed [15:0] acc2;

reg [15:0] mag;         // magnitude
reg [7:0]  mag_clipped; // clipped magnitude

////////////////////////////////////////////////////////////////////////////////
// Sobel Kernel Initialization
////////////////////////////////////////////////////////////////////////////////

initial begin
    kernel1[0] =  8'd1;
    kernel1[1] =  8'd0;
    kernel1[2] = -8'd1;
    kernel1[3] =  8'd2;
    kernel1[4] =  8'd0;
    kernel1[5] = -8'd2;
    kernel1[6] =  8'd1;
    kernel1[7] =  8'd0;
    kernel1[8] = -8'd1;

    kernel2[0] =  8'd1;
    kernel2[1] =  8'd2;
    kernel2[2] =  8'd1;
    kernel2[3] =  8'd0;
    kernel2[4] =  8'd0;
    kernel2[5] =  8'd0;
    kernel2[6] = -8'd1;
    kernel2[7] = -8'd2;
    kernel2[8] = -8'd1;
end

////////////////////////////////////////////////////////////////////////////////
// FSM
////////////////////////////////////////////////////////////////////////////////

always @(*) begin
    case (state)
        IDLE:
            next_state = start ? READ : IDLE;

        READ:
            next_state = (counter == 4'd10) ? WRITE : READ;

        WRITE:
            next_state = (x == IMG_WIDTH - 2 && y == IMG_HEIGHT - 2) ? DONE : READ;

        DONE:
            next_state = start ? DONE : IDLE;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

////////////////////////////////////////////////////////////////////////////////
// Control
////////////////////////////////////////////////////////////////////////////////

// x, y
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x <= 1;
        y <= 1;
    end else if (state == WRITE) begin
        x <= (x == IMG_WIDTH - 2) ? 1 : x + 1;
        y <= (x == IMG_WIDTH - 2) ? y + 1 : y;
    end
end

// bram0_addr
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bram0_addr <= 32'd0;
    end else if (state == READ) begin
        case (counter)
            4'd0: bram0_addr <= { (y-1) * IMG_WIDTH + (x-1), 2'b00 };
            4'd1: bram0_addr <= { (y-1) * IMG_WIDTH + (x  ), 2'b00 };
            4'd2: bram0_addr <= { (y-1) * IMG_WIDTH + (x+1), 2'b00 };
            4'd3: bram0_addr <= { (y  ) * IMG_WIDTH + (x-1), 2'b00 };
            4'd4: bram0_addr <= { (y  ) * IMG_WIDTH + (x  ), 2'b00 };
            4'd5: bram0_addr <= { (y  ) * IMG_WIDTH + (x+1), 2'b00 };
            4'd6: bram0_addr <= { (y+1) * IMG_WIDTH + (x-1), 2'b00 };
            4'd7: bram0_addr <= { (y+1) * IMG_WIDTH + (x  ), 2'b00 };
            4'd8: bram0_addr <= { (y+1) * IMG_WIDTH + (x+1), 2'b00 };
        endcase
    end else begin
        bram0_addr <= 32'd0;
    end
end

// counter
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 4'd0;
    end else if (state == READ) begin
        counter <= counter + 4'd1;
    end else begin
        counter <= 4'd0;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Data Path
////////////////////////////////////////////////////////////////////////////////

// Multiplier
always @(*) begin
    mul1 = $signed(bram0_dout[8:0]) * $signed(kernel1[counter-2]);
    mul2 = $signed(bram0_dout[8:0]) * $signed(kernel2[counter-2]);
end

// Accumulator
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc1 <= 16'd0;
        acc2 <= 16'd0;
    end else if (state == READ) begin
        acc1 <= (counter >= 2) ? acc1 + mul1 : acc1;
        acc2 <= (counter >= 2) ? acc2 + mul2 : acc2;
    end else begin
        acc1 <= 16'd0;
        acc2 <= 16'd0;
    end
end

// Magnitude Calculation
always @(*) begin
    mag = ((acc1 < 0) ? -acc1 : acc1) + ((acc2 < 0) ? -acc2 : acc2); // abs(acc1) + abs(acc2)
    mag_clipped = (mag > 16'd255) ? 8'd255 : mag[7:0];
end

////////////////////////////////////////////////////////////////////////////////
// Output Logic
////////////////////////////////////////////////////////////////////////////////

// bram1_we
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bram1_we <= 4'd0;
    end else if (state == WRITE) begin
        bram1_we <= 4'b1111;
    end else begin
        bram1_we <= 4'd0;
    end
end

// bram1_addr
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bram1_addr <= 32'd0;
    end else if (state == WRITE) begin
        bram1_addr <= { (y - 1) * (IMG_WIDTH - 2) + (x - 1), 2'b00 };
    end
end

// bram1_din
always  @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bram1_din <= 32'd0;
    end else if (state == WRITE) begin
        bram1_din <= { 24'd0, mag_clipped };
    end else begin
        bram1_din <= 32'd0;
    end
end

assign bram0_en = (state == READ);
assign done = (state == DONE);

endmodule
