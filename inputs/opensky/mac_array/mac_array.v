// =============================================================================
// mac_array — N x N output-stationary systolic MAC array (int8 x int8 -> ACC_W)
// CBflow open-source RTL-to-GDS proof design, large block (project opensky,
// sky130hd). Default N=16 -> 256 PEs, ~150k standard cells after synthesis.
//
// Operation:
//   clear     : zero every accumulator
//   en        : a_in (row operands) flow left->right, b_in (column operands)
//               flow top->bottom; each PE accumulates a*b
//   drain     : accumulators shift down one row per cycle; the bottom row
//               appears on acc_out (N cycles to read the full matrix)
// =============================================================================
module mac_pe #(parameter W = 8, parameter ACC_W = 24) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    en,
    input  wire                    clear,
    input  wire                    drain,
    input  wire signed [W-1:0]     a_in,
    input  wire signed [W-1:0]     b_in,
    input  wire        [ACC_W-1:0] acc_in,     // from the PE above (drain chain)
    output reg  signed [W-1:0]     a_out,
    output reg  signed [W-1:0]     b_out,
    output reg         [ACC_W-1:0] acc
);
    wire signed [2*W-1:0] prod = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= {W{1'b0}};
            b_out <= {W{1'b0}};
            acc   <= {ACC_W{1'b0}};
        end else begin
            if (en) begin
                a_out <= a_in;
                b_out <= b_in;
            end
            if (clear)
                acc <= {ACC_W{1'b0}};
            else if (drain)
                acc <= acc_in;
            else if (en)
                acc <= acc + {{(ACC_W-2*W){prod[2*W-1]}}, prod};
        end
    end
endmodule

module mac_array #(parameter N = 16, parameter W = 8, parameter ACC_W = 24) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               en,
    input  wire               clear,
    input  wire               drain,
    input  wire [N*W-1:0]     a_in,      // one operand per row
    input  wire [N*W-1:0]     b_in,      // one operand per column
    output wire [N*ACC_W-1:0] acc_out    // bottom row during drain
);
    // Horizontal (a), vertical (b) and drain (acc) interconnect.
    wire [W-1:0]     a_w   [0:N-1][0:N];
    wire [W-1:0]     b_w   [0:N][0:N-1];
    wire [ACC_W-1:0] acc_w [0:N][0:N-1];

    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : g_row_in
            assign a_w[r][0] = a_in[r*W +: W];
        end
        for (c = 0; c < N; c = c + 1) begin : g_col_io
            assign b_w[0][c]           = b_in[c*W +: W];
            assign acc_w[0][c]         = {ACC_W{1'b0}};
            assign acc_out[c*ACC_W +: ACC_W] = acc_w[N][c];
        end
        for (r = 0; r < N; r = r + 1) begin : g_r
            for (c = 0; c < N; c = c + 1) begin : g_c
                mac_pe #(.W(W), .ACC_W(ACC_W)) u_pe (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .en     (en),
                    .clear  (clear),
                    .drain  (drain),
                    .a_in   (a_w[r][c]),
                    .b_in   (b_w[r][c]),
                    .acc_in (acc_w[r][c]),
                    .a_out  (a_w[r][c+1]),
                    .b_out  (b_w[r+1][c]),
                    .acc    (acc_w[r+1][c])
                );
            end
        end
    endgenerate
endmodule
