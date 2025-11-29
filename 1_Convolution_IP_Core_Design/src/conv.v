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
localparam IDLE          = 3'd0;
localparam READ_9_PIXELS = 3'd1;
localparam READ_3_PIXELS = 3'd2;
localparam MULTIPLY      = 3'd3;
localparam ACCUMULATE    = 3'd4;
localparam WRITE         = 3'd5;
localparam DONE          = 3'd6;

integer i;

reg [2:0] state, next_state;

reg [7:0] kernel1 [8:0];             // vertical Sobel kernel
reg [7:0] kernel2 [8:0];             // horizontal Sobel kernel

reg [$clog2(IMG_WIDTH)-1:0]  x;      // current x position
reg [$clog2(IMG_HEIGHT)-1:0] y;      // current y position
reg [$clog2(IMG_WIDTH)-1:0]  next_x; // next x position
reg [$clog2(IMG_HEIGHT)-1:0] next_y; // next y position

reg [3:0] counter;                   // counter to control reading pixels

reg [7:0] buffer [0:8];              // pixel buffer

reg signed [15:0] mul1 [8:0];        // MUL result of vertical Sobel filter
reg signed [15:0] mul2 [8:0];        // MUL result of horizontal Sobel filter
reg signed [15:0] acc1;              // accumulated result of vertical Sobel filter
reg signed [15:0] acc2;              // accumulated result of horizontal Sobel filter

reg [15:0] mag;                      // magnitude
reg [7:0]  mag_clipped;              // clipped magnitude

////////////////////////////////////////////////////////////////////////////////
// Sobel Kernel Initialization
////////////////////////////////////////////////////////////////////////////////

/*
 * Initialize Sobel kernels
 *
 * The vertical Sobel kernel:
 *  [  1  0 -1 ]
 *  [  2  0 -2 ]
 *  [  1  0 -1 ]
 *
 * The horizontal Sobel kernel:
 *  [  1  2  1 ]
 *  [  0  0  0 ]
 *  [ -1 -2 -1 ]
 */
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
            next_state = start ? READ_9_PIXELS : IDLE;

        READ_9_PIXELS:
            next_state = (counter == 4'd10) ? MULTIPLY : READ_9_PIXELS;

        READ_3_PIXELS:
            next_state = (counter == 4'd4) ? MULTIPLY : READ_3_PIXELS;

        MULTIPLY:
            next_state = ACCUMULATE;

        ACCUMULATE:
            next_state = WRITE;

        WRITE:
            if (x == IMG_WIDTH - 1 && y == IMG_HEIGHT - 1)
                next_state = DONE;
            else
                next_state = (next_x == 0) ? READ_9_PIXELS : READ_3_PIXELS;

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

// next_x, next_y
always @(*) begin
    next_x = (x == IMG_WIDTH - 1) ? 0 : x + 1;
    next_y = (x == IMG_WIDTH - 1) ? y + 1 : y;
end

// x, y
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x <= 0;
        y <= 0;
    end else if (state == WRITE) begin
        x <= next_x;
        y <= next_y;
    end
end

// bram0_addr
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bram0_addr <= 32'd0;
    end else if (state == READ_9_PIXELS) begin
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
    end else if (state == READ_3_PIXELS) begin
        case (counter)
            4'd0: bram0_addr <= { (y-1) * IMG_WIDTH + (x+1), 2'b00 };
            4'd1: bram0_addr <= { (y  ) * IMG_WIDTH + (x+1), 2'b00 };
            4'd2: bram0_addr <= { (y+1) * IMG_WIDTH + (x+1), 2'b00 };
        endcase
    end else begin
        bram0_addr <= 32'd0;
    end
end

// counter
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 4'd0;
    end else if (state == READ_9_PIXELS || state == READ_3_PIXELS) begin
        counter <= counter + 4'd1;
    end else begin
        counter <= 4'd0;
    end
end

// buffer
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        buffer[0] <= 8'd0;
        buffer[1] <= 8'd0;
        buffer[2] <= 8'd0;
        buffer[3] <= 8'd0;
        buffer[4] <= 8'd0;
        buffer[5] <= 8'd0;
        buffer[6] <= 8'd0;
        buffer[7] <= 8'd0;
        buffer[8] <= 8'd0;
    end else if (state == READ_9_PIXELS) begin
        case (counter)
            4'd2:  buffer[0] <= (x == 0 || y == 0                         ) ? 8'd0 : bram0_dout[7:0];
            4'd3:  buffer[1] <= (y == 0                                   ) ? 8'd0 : bram0_dout[7:0];
            4'd4:  buffer[2] <= (x == IMG_WIDTH - 1 || y == 0             ) ? 8'd0 : bram0_dout[7:0];
            4'd5:  buffer[3] <= (x == 0                                   ) ? 8'd0 : bram0_dout[7:0];
            4'd6:  buffer[4] <= bram0_dout[7:0];
            4'd7:  buffer[5] <= (x == IMG_WIDTH - 1                       ) ? 8'd0 : bram0_dout[7:0];
            4'd8:  buffer[6] <= (x == 0 || y == IMG_HEIGHT - 1            ) ? 8'd0 : bram0_dout[7:0];
            4'd9:  buffer[7] <= (y == IMG_HEIGHT - 1                      ) ? 8'd0 : bram0_dout[7:0];
            4'd10: buffer[8] <= (x == IMG_WIDTH - 1 || y == IMG_HEIGHT - 1) ? 8'd0 : bram0_dout[7:0];
        endcase
    end else if (state == READ_3_PIXELS) begin
        case (counter)
            4'd2: buffer[2] <= (x == IMG_WIDTH - 1 || y == 0             ) ? 8'd0 : bram0_dout[7:0];
            4'd3: buffer[5] <= (x == IMG_WIDTH - 1                       ) ? 8'd0 : bram0_dout[7:0];
            4'd4: buffer[8] <= (x == IMG_WIDTH - 1 || y == IMG_HEIGHT - 1) ? 8'd0 : bram0_dout[7:0];
        endcase
    end else if (state == WRITE) begin
        buffer[0] <= buffer[1];
        buffer[1] <= buffer[2];
        buffer[3] <= buffer[4];
        buffer[4] <= buffer[5];
        buffer[6] <= buffer[7];
        buffer[7] <= buffer[8];
    end
end

////////////////////////////////////////////////////////////////////////////////
// Data Path
////////////////////////////////////////////////////////////////////////////////

// mul1, mul2
always @(posedge clk) begin
    for (i = 0; i < 9; i = i + 1) begin
        mul1[i] <= $signed({ 1'b0, buffer[i] }) * $signed(kernel1[i]);
        mul2[i] <= $signed({ 1'b0, buffer[i] }) * $signed(kernel2[i]);
    end
end

// acc1, acc2
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc1 <= 16'd0;
        acc2 <= 16'd0;
    end else if (state == ACCUMULATE) begin
        acc1 <= mul1[0] + mul1[1] + mul1[2]
                + mul1[3] + mul1[4] + mul1[5]
                + mul1[6] + mul1[7] + mul1[8];

        acc2 <= mul2[0] + mul2[1] + mul2[2]
                + mul2[3] + mul2[4] + mul2[5]
                + mul2[6] + mul2[7] + mul2[8];
    end else begin
        acc1 <= 16'd0;
        acc2 <= 16'd0;
    end
end

// Magnitude Calculation
always @(*) begin
    // abs(acc1) + abs(acc2)
    mag = ((acc1 < 0) ? -acc1 : acc1) + ((acc2 < 0) ? -acc2 : acc2);

    // Clip to 8 bits
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
        bram1_addr <= { y * IMG_WIDTH + x, 2'b00 };
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

assign bram0_en = (state == READ_9_PIXELS || state == READ_3_PIXELS);
assign done = (state == DONE);

endmodule
