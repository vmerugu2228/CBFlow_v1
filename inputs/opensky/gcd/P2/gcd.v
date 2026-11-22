// =============================================================================
// gcd — 16-bit greatest-common-divisor block (Euclid, subtract-and-swap)
// CBflow open-source RTL-to-GDS proof design (project opensky, sky130hd).
// Valid/ready request and response interfaces; one result per request.
// P2: two 1 KB SRAM macros (sky130_sram_1kbyte_1rw1r_32x256_8) log every
// accepted request's operands and every accepted result (256-entry rings).
// Same ports as P0 / P1.
// =============================================================================
module gcd (
    input  wire        clk,
    input  wire        reset,
    // request: two 16-bit operands {a, b}
    input  wire        req_val,
    output wire        req_rdy,
    input  wire [31:0] req_msg,
    // response: gcd(a, b)
    output wire        resp_val,
    input  wire        resp_rdy,
    output wire [15:0] resp_msg
);
    localparam IDLE = 2'd0, CALC = 2'd1, DONE = 2'd2;

    reg [1:0]  state;
    reg [15:0] a, b;

    wire a_lt_b = (a < b);
    wire b_zero = (b == 16'd0);

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            a     <= 16'd0;
            b     <= 16'd0;
        end else begin
            case (state)
                IDLE: if (req_val) begin
                          a     <= req_msg[31:16];
                          b     <= req_msg[15:0];
                          state <= CALC;
                      end
                CALC: if (a_lt_b) begin
                          a <= b;                 // swap so a >= b
                          b <= a;
                      end else if (!b_zero) begin
                          a <= a - b;
                      end else begin
                          state <= DONE;
                      end
                DONE: if (resp_rdy) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    assign req_rdy  = (state == IDLE);
    assign resp_val = (state == DONE);
    assign resp_msg = a;

    // ── SRAM logs ───────────────────────────────────────────────────────
    wire req_fire  = req_val  && req_rdy;
    wire resp_fire = resp_val && resp_rdy;
    reg [7:0] req_ptr, resp_ptr;

    always @(posedge clk) begin
        if (reset) begin
            req_ptr  <= 8'd0;
            resp_ptr <= 8'd0;
        end else begin
            if (req_fire)  req_ptr  <= req_ptr  + 8'd1;
            if (resp_fire) resp_ptr <= resp_ptr + 8'd1;
        end
    end

    // operand log: {a, b} of each accepted request (port 0 write; port 1 idle)
    sky130_sram_1kbyte_1rw1r_32x256_8 u_sram_req (
        .clk0(clk), .csb0(~req_fire), .web0(1'b0), .wmask0(4'hF),
        .addr0(req_ptr), .din0(req_msg), .dout0(),
        .clk1(clk), .csb1(1'b1), .addr1(8'd0), .dout1()
    );

    // result log: gcd of each accepted response
    sky130_sram_1kbyte_1rw1r_32x256_8 u_sram_resp (
        .clk0(clk), .csb0(~resp_fire), .web0(1'b0), .wmask0(4'hF),
        .addr0(resp_ptr), .din0({16'd0, a}), .dout0(),
        .clk1(clk), .csb1(1'b1), .addr1(8'd0), .dout1()
    );
endmodule
