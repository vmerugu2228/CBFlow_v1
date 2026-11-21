// =============================================================================
// opensky_chip (DL1) — full-chip top. Integrates the two DL2 subsystems
// (ctrl_subsys, ai_subsys) as hard macros behind a 32-bit host bus.
// =============================================================================
module opensky_chip (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        host_we,
    input  wire        host_re,
    input  wire [7:0]  host_addr,
    input  wire [31:0] host_wdata,
    output wire [31:0] host_rdata,
    output wire        irq,
    // requests to the off-chip switches of VPWR_GCD / VPWR_MAC
    output wire        gcd_pwr_en,
    output wire        mac_pwr_en
);
    // Reset synchronizer (async assert, sync de-assert) shared by both subsystems.
    reg [1:0] rst_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};
    wire rst_n_sync = rst_sync[1];

    wire        ai_sel, ai_we;
    wire [5:0]  ai_addr;
    wire [31:0] ai_wdata, ai_rdata;
    wire        mac_iso;

    ctrl_subsys u_ctrl_subsys (
        .clk        (clk),
        .rst_n      (rst_n_sync),
        .host_we    (host_we),
        .host_re    (host_re),
        .host_addr  (host_addr),
        .host_wdata (host_wdata),
        .host_rdata (host_rdata),
        .irq        (irq),
        .gcd_pwr_en (gcd_pwr_en),
        .mac_pwr_en (mac_pwr_en),
        .mac_iso    (mac_iso),
        .ai_sel     (ai_sel),
        .ai_we      (ai_we),
        .ai_addr    (ai_addr),
        .ai_wdata   (ai_wdata),
        .ai_rdata   (ai_rdata)
    );

    ai_subsys u_ai_subsys (
        .clk   (clk),
        .rst_n (rst_n_sync),
        .sel   (ai_sel),
        .we    (ai_we),
        .addr  (ai_addr),
        .wdata (ai_wdata),
        .rdata (ai_rdata),
        .mac_iso (mac_iso)
    );
endmodule
