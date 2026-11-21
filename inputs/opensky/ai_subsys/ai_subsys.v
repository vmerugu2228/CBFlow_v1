// =============================================================================
// ai_subsys (DL2) — AI accelerator subsystem around the mac_array (DL3) macro.
// Register-mapped from the host bus (word addresses, 32-bit data):
//   0x00-0x03  A operand vector  (N*W = 128 bits, one byte per row)      W
//   0x04-0x07  B operand vector  (one byte per column)                   W
//   0x08       CTRL  bit0 en(step)  bit1 clear  bit2 drain  (1-cycle)    W
//   0x09       STATUS bit0 busy-cycle counter != 0, [31:16] step count  R
//   0x10-0x1B  RESULT window — bottom-row accumulators, 12 x 32 bits     R
// =============================================================================
module ai_subsys #(parameter N = 16, parameter W = 8, parameter ACC_W = 24) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sel,
    input  wire        we,
    input  wire [5:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        mac_iso      // 1 = PD_MAC off/switching: clamp its outputs
);
    localparam AW = N*W;            // 128
    localparam RW = N*ACC_W;        // 384
    localparam RWORDS = RW / 32;    // 12

    reg  [AW-1:0] a_vec, b_vec;
    reg           en_p, clear_p, drain_p;
    reg  [15:0]   steps;
    wire [RW-1:0] acc_out;
    wire [RW-1:0] acc_out_sw;       // raw PD_MAC outputs, isolated below

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_vec <= {AW{1'b0}};  b_vec <= {AW{1'b0}};
            en_p <= 1'b0; clear_p <= 1'b0; drain_p <= 1'b0;
            steps <= 16'd0;
        end else begin
            en_p <= 1'b0; clear_p <= 1'b0; drain_p <= 1'b0;
            if (sel && we) begin
                for (i = 0; i < AW/32; i = i + 1) begin
                    if (addr == i)          a_vec[i*32 +: 32] <= wdata;
                    if (addr == i + AW/32)  b_vec[i*32 +: 32] <= wdata;
                end
                if (addr == 6'h08) begin
                    en_p    <= wdata[0];
                    clear_p <= wdata[1];
                    drain_p <= wdata[2];
                    if (wdata[1])      steps <= 16'd0;
                    else if (wdata[0]) steps <= steps + 16'd1;
                end
            end
        end
    end

    // Registered read mux (keeps the 384-bit result bus off the host path).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rdata <= 32'd0;
        else if (sel && !we) begin
            if (addr == 6'h09)
                rdata <= {steps, 15'd0, (steps != 16'd0)};
            else if (addr >= 6'h10 && addr < 6'h10 + RWORDS)
                rdata <= acc_out[(addr - 6'h10)*32 +: 32];
            else
                rdata <= 32'd0;
        end
    end

    // mac_array (DL3) — switchable domain PD_MAC (supply VPWR_MAC)
    mac_array #(.N(N), .W(W), .ACC_W(ACC_W)) u_mac_array (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en_p),
        .clear   (clear_p),
        .drain   (drain_p),
        .a_in    (a_vec),
        .b_in    (b_vec),
        .acc_out (acc_out_sw)
    );

    // Isolation of every PD_MAC output (UPF strategy iso_mac)
    cbf_iso_clamp0 #(.W(RW)) u_iso_mac (.a(acc_out_sw), .iso(mac_iso), .y(acc_out));
endmodule
