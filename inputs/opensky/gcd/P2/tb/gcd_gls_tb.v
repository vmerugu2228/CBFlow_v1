// =============================================================================
// gcd_gls_tb — self-checking gate-level testbench for gcd (P2, opensky)
// Directed + random operand pairs through the valid/ready request interface;
// each response is compared with a reference GCD. With CBFLOW_CHECK_SRAM the
// result-log SRAM (u_sram_resp) must hold every result in order.
// Scan ports (scan_enable_0 / scan_in_0, added by SYNTH DFT) are held 0.
// Prints "TEST PASSED" / "TEST FAILED" and "Errors: <n>".
// =============================================================================
`timescale 1ns/1ps
module gcd_gls_tb;
    reg         clk = 1'b0;
    reg         reset = 1'b1;
    reg         req_val = 1'b0;
    reg  [31:0] req_msg = 32'd0;
    reg         resp_rdy = 1'b0;
    wire        req_rdy, resp_val;
    wire [15:0] resp_msg;
    reg         scan_enable_0 = 1'b0;
    reg         scan_in_0 = 1'b0;

    gcd dut (
        .clk(clk), .reset(reset),
        .req_val(req_val), .req_rdy(req_rdy), .req_msg(req_msg),
        .resp_val(resp_val), .resp_rdy(resp_rdy), .resp_msg(resp_msg),
        .scan_enable_0(scan_enable_0), .scan_in_0(scan_in_0)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer ntests = 0;
    reg [15:0] results [0:255];

    function [15:0] ref_gcd(input [15:0] x, input [15:0] y);
        reg [15:0] p, q, t;
        begin
            p = x; q = y;
            while (q != 0) begin
                if (p < q) begin t = p; p = q; q = t; end
                else p = p - q;
            end
            ref_gcd = p;
        end
    endfunction

    task run_one(input [15:0] x, input [15:0] y);
        integer cyc;
        reg [15:0] exp;
        begin
            exp = ref_gcd(x, y);
            @(negedge clk);
            while (!req_rdy) @(negedge clk);
            req_msg = {x, y};
            req_val = 1'b1;
            @(negedge clk);
            req_val = 1'b0;
            cyc = 0;
            while (!resp_val && cyc < 200000) begin @(negedge clk); cyc = cyc + 1; end
            if (!resp_val) begin
                errors = errors + 1;
                $display("ERROR: timeout gcd(%0d, %0d)", x, y);
            end else if (resp_msg !== exp) begin
                errors = errors + 1;
                $display("ERROR: gcd(%0d, %0d) = %0d, expected %0d", x, y, resp_msg, exp);
            end
            results[ntests] = exp;
            ntests = ntests + 1;
            resp_rdy = 1'b1;
            @(negedge clk);
            resp_rdy = 1'b0;
        end
    endtask

    integer i, seed;
    reg [15:0] rx, ry;
    initial begin
        seed = 32'h1234_5678;
        repeat (4) @(negedge clk);
        reset = 1'b0;
        run_one(16'd27,    16'd15);
        run_one(16'd48,    16'd18);
        run_one(16'd17,    16'd5);
        run_one(16'd0,     16'd9);
        run_one(16'd12,    16'd0);
        run_one(16'd65535, 16'd255);
        run_one(16'd4096,  16'd1024);
        run_one(16'd1,     16'd1);
        for (i = 0; i < 24; i = i + 1) begin
            rx = $random(seed) % 4096;
            ry = $random(seed) % 4096;
            run_one(rx, ry);
        end
`ifdef CBFLOW_CHECK_SRAM
        repeat (4) @(negedge clk);
        for (i = 0; i < ntests; i = i + 1)
            if (dut.u_sram_resp.mem[i][15:0] !== results[i]) begin
                errors = errors + 1;
                $display("ERROR: result log entry %0d = %0d, expected %0d", i, dut.u_sram_resp.mem[i][15:0], results[i]);
            end
`endif
        $display("Tests: %0d", ntests);
        $display("Errors: %0d", errors);
        if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
