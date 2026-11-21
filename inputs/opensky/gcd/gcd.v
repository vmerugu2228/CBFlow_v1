// =============================================================================
// gcd — 16-bit greatest-common-divisor block (Euclid, subtract-and-swap)
// CBflow open-source RTL-to-GDS proof design (project opensky, sky130hd).
// Valid/ready request and response interfaces; one result per request.
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
endmodule
