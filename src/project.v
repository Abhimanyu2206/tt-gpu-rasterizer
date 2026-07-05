`default_nettype none

// ==========================================================================
// 1. MAIN TINY TAPEOUT WRAPPER MODULE
// ==========================================================================
module tt_um_gpu_rasterizer (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IO pads: Input path
    output wire [7:0] uio_out,  // IO pads: Output path
    output wire [7:0] uio_oe,   // IO pads: Output Enable
    input  wire       ena,      // always 1 when active
    input  wire       clk,      // clock
    input  wire       rst_n     // active low reset
);
    // Safely disable bidirectional IO lanes
    assign uio_out = 8'b0; 
    assign uio_oe  = 8'b0;
    wire _unused = &{ena, uio_in};

    // State Encoding
    localparam IDLE=0, L0=1, L1=2, L2=3, RENDER=4, DONE=5;
    reg [2:0] state;
    
    // Registers for 4-bit Vertices and Shader Configuration
    reg [3:0] x0, y0, x1, y1, x2, y2;
    reg [1:0] shader_mode;
    
    // Scanner Coordinates
    reg [3:0] px, py;

    // Bounding Box Outputs
    wire [3:0] xmin, xmax, ymin, ymax;
    
    // Instantiate Bounding Box Hardware Block
    bounding_box bbox (
        .x0(x0), .y0(y0), 
        .x1(x1), .y1(y1), 
        .x2(x2), .y2(y2), 
        .xmin(xmin), .xmax(xmax), 
        .ymin(ymin), .ymax(ymax)
    );

    // Edge Setup Coefficients
    wire signed [5:0] A0, B0, A1, B1, A2, B2;
    wire signed [9:0] C0, C1, C2;
    
    // Instantiate Edge Coefficient Multipliers Structurally
    edge_setup es0 ({1'b0,x0}, {1'b0,y0}, {1'b0,x1}, {1'b0,y1}, A0, B0, C0);
    edge_setup es1 ({1'b0,x1}, {1'b0,y1}, {1'b0,x2}, {1'b0,y2}, A1, B1, C1);
    edge_setup es2 ({1'b0,x2}, {1'b0,y2}, {1'b0,x0}, {1'b0,y0}, A2, B2, C2);

    // Edge Evaluator Matrix Results
    wire signed [11:0] E0, E1, E2;
    
    // Instantiate 3x Parallel Math Execution Lanes
    edge_eval ee0 (A0, B0, C0, {1'b0,px}, {1'b0,py}, E0);
    edge_eval ee1 (A1, B1, C1, {1'b0,px}, {1'b0,py}, E1);
    edge_eval ee2 (A2, B2, C2, {1'b0,px}, {1'b0,py}, E2);

    // Pixel Coverage Verification
    wire is_inside = (E0 >= 0) && (E1 >= 0) && (E2 >= 0);

    // Control Command FSM Sequential Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; px <= 0; py <= 0;
            x0<=0; y0<=0; x1<=0; y1<=0; x2<=0; y2<=0; shader_mode<=0;
        end else begin
            case (state)
                IDLE: if (ui_in[7]) begin x0<=ui_in[3:0]; y0<=ui_in[6:4]; state<=L0; end
                L0:   if (!ui_in[7]) state<=L1;
                L1:   if (ui_in[7]) begin x1<=ui_in[3:0]; y1<=ui_in[6:4]; state<=L2; end
                L2:   if (!ui_in[7]) begin 
                    x2 <= ui_in[3:0]; 
                    y2 <= ui_in[6:4]; 
                    shader_mode <= ui_in[6:5]; 
                    px <= xmin; 
                    py <= ymin; 
                    state <= RENDER; 
                end
                RENDER: begin
                    if (px >= xmax) begin
                        px <= xmin;
                        if (py >= ymax) state <= DONE;
                        else py <= py + 1'b1;
                    end else px <= px + 1'b1;
                end
                DONE: if (ui_in[7]) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    // Combinational Fragment Color Shader Selection Engine
    reg [5:0] color;
    always @(*) begin
        if ((state == RENDER) && is_inside) begin
            case (shader_mode)
                2'b01:   color = (px[0] ^ py[0]) ? 6'b111111 : 6'b000000; // Checkerboard
                2'b10:   color = 6'b110000;                               // Solid Color
                default: color = {px[2:1], py[2:1], px[0]^py[0], 1'b1};   // Gradient
            endcase
        end else color = 6'b000000;
    end

    // Drive Output Interface Matrix
    assign uo_out = {(state == RENDER), (state == DONE), color};

endmodule

// ==========================================================================
// 2. GEOMETRIC BOUNDING BOX ENGINE
// ==========================================================================
module bounding_box (
    input  wire [3:0] x0, y0, x1, y1, x2, y2,
    output reg  [3:0] xmin, xmax, ymin, ymax
);
    always @(*) begin
        xmin = (x0 <= x1) ? ((x0 <= x2) ? x0 : x2) : ((x1 <= x2) ? x1 : x2);
        xmax = (x0 >= x1) ? ((x0 >= x2) ? x0 : x2) : ((x1 >= x2) ? x1 : x2);
        ymin = (y0 <= y1) ? ((y0 <= y2) ? y0 : y2) : ((y1 <= y2) ? y1 : y2);
        ymax = (y0 >= y1) ? ((y0 >= y2) ? y0 : y2) : ((y1 >= y2) ? y1 : y2);
    end
endmodule

// ==========================================================================
// 3. GEOMETRIC LINE SLOPE SETUP UNIT
// ==========================================================================
module edge_setup (
    input  wire signed [4:0] v0_x, input  wire signed [4:0] v0_y,
    input  wire signed [4:0] v1_x, input  wire signed [4:0] v1_y,
    output wire signed [5:0] A,    output wire signed [5:0] B,
    output wire signed [9:0] C
);
    assign A = v0_y - v1_y;
    assign B = v1_x - v0_x;
    assign C = (v0_x * v1_y) - (v1_x * v0_y);
endmodule

// ==========================================================================
// 4. PARALLEL POLYNOMIAL EDGE EVALUATION LANE
// ==========================================================================
module edge_eval (
    input  wire signed [5:0] A, input wire signed [5:0] B, input wire signed [9:0] C,
    input  wire signed [4:0] px, input wire signed [4:0] py,
    output wire signed [11:0] E
);
    assign E = (A * px) + (B * py) + C;
endmodule
