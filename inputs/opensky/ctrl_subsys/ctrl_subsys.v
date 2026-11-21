// =============================================================================
// ctrl_subsys (DL2) — host-bus front end + gcd (DL3) macro.
// Host word address map (addr[7:6] selects the target):
//   00_xxxxxx  local:  0x00 GCD_OPERANDS {a,b} (W, starts)  0x01 GCD_RESULT (R)
//                      0x02 STATUS {.., req_pending, gcd_done} 0x03 SCRATCH (RW)
//                      0x04 PWR_CTRL (RW)  bit0 gcd_iso   bit1 gcd_pwr_en
//                                          bit2 mac_iso   bit3 mac_pwr_en
//                      Power-down: set *_iso, then clear *_pwr_en.
//                      Power-up:   set *_pwr_en, wait, then clear *_iso.
//   01_xxxxxx  ai_subsys window (forwarded on the ai_* port, 6-bit address)
// =============================================================================
module ctrl_subsys (
    input  wire        clk,
    input  wire        rst_n,
    // host bus
    input  wire        host_we,
    input  wire        host_re,
    input  wire [7:0]  host_addr,
    input  wire [31:0] host_wdata,
    output reg  [31:0] host_rdata,
    output wire        irq,
    // power control (PD_GCD lives here; PD_MAC in ai_subsys; switches off-chip)
    output wire        gcd_pwr_en,
    output wire        mac_pwr_en,
    output wire        mac_iso,
    // ai_subsys bus
    output wire        ai_sel,
    output wire        ai_we,
    output wire [5:0]  ai_addr,
    output wire [31:0] ai_wdata,
    input  wire [31:0] ai_rdata
);
    wire local_hit = (host_addr[7:6] == 2'b00);
    wire ai_hit    = (host_addr[7:6] == 2'b01);

    assign ai_sel   = ai_hit & (host_we | host_re);
    assign ai_we    = host_we;
    assign ai_addr  = host_addr[5:0];
    assign ai_wdata = host_wdata;

    // gcd request / response handshake
    reg         req_val;
    reg  [31:0] req_msg;
    reg  [15:0] result;
    reg         done;
    reg  [31:0] scratch;
    reg  [3:0]  pwr_ctrl;           // reset: both domains on, not isolated
    wire        req_rdy, resp_val;
    wire [15:0] resp_msg;
    // raw outputs of the switchable gcd domain, isolated below
    wire        req_rdy_sw, resp_val_sw;
    wire [15:0] resp_msg_sw;
    wire        gcd_iso = pwr_ctrl[0];

    assign gcd_pwr_en = pwr_ctrl[1];
    assign mac_iso    = pwr_ctrl[2];
    assign mac_pwr_en = pwr_ctrl[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_val <= 1'b0; req_msg <= 32'd0; result <= 16'd0;
            done <= 1'b0; scratch <= 32'd0; pwr_ctrl <= 4'b1010;
        end else begin
            if (req_val && req_rdy) req_val <= 1'b0;
            if (resp_val) begin result <= resp_msg; done <= 1'b1; end
            if (host_we && local_hit) begin
                case (host_addr[5:0])
                    6'h00: begin req_msg <= host_wdata; req_val <= 1'b1; done <= 1'b0; end
                    6'h03: scratch <= host_wdata;
                    6'h04: pwr_ctrl <= host_wdata[3:0];
                    default: ;
                endcase
            end
        end
    end

    assign irq = done;

    // read path: local registers immediately, ai_subsys data one cycle later
    reg ai_rd_q;
    reg [31:0] local_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ai_rd_q <= 1'b0; local_q <= 32'd0; end
        else begin
            ai_rd_q <= host_re & ai_hit;
            case (host_addr[5:0])
                6'h00: local_q <= req_msg;
                6'h01: local_q <= {16'd0, result};
                6'h02: local_q <= {30'd0, req_val, done};
                6'h03: local_q <= scratch;
                6'h04: local_q <= {28'd0, pwr_ctrl};
                default: local_q <= 32'd0;
            endcase
        end
    end
    always @(*) host_rdata = ai_rd_q ? ai_rdata : local_q;

    // gcd (DL3) — switchable domain PD_GCD (supply VPWR_GCD)
    gcd u_gcd (
        .clk      (clk),
        .reset    (~rst_n),
        .req_val  (req_val),
        .req_rdy  (req_rdy_sw),
        .req_msg  (req_msg),
        .resp_val (resp_val_sw),
        .resp_rdy (1'b1),
        .resp_msg (resp_msg_sw)
    );

    // Isolation of every PD_GCD output (UPF strategy iso_gcd)
    cbf_iso_clamp0 #(.W(18)) u_iso_gcd (
        .a   ({req_rdy_sw, resp_val_sw, resp_msg_sw}),
        .iso (gcd_iso),
        .y   ({req_rdy,    resp_val,    resp_msg})
    );
endmodule
