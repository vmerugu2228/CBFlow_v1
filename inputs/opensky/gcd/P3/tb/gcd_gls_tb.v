// =============================================================================
// gcd_gls_tb — self-checking gate-level testbench for the gcd accelerator (P3)
// Queue mode: 24 jobs pushed through APB JOB_DATA, CTRL.start, completion by
// the irq pin, every result read back through RES_ADDR / RES_DATA (both SRAMs:
// job fetch + result write / read); stream mode: 16 requests through
// valid/ready; OPCOUNT checked. Scan ports added by SYNTH DFT are held 0.
// Plain Verilog-2005 (iverilog). Prints "TEST PASSED" / "TEST FAILED".
// =============================================================================
`timescale 1ns/1ps
module gcd_gls_tb;
    reg         clk = 1'b0;
    reg         reset = 1'b1;
    reg         req_val = 1'b0, resp_rdy = 1'b0;
    reg  [31:0] req_msg = 32'd0;
    wire        req_rdy, resp_val;
    wire [15:0] resp_msg;
    reg         psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
    reg  [5:0]  paddr = 6'd0;
    reg  [31:0] pwdata = 32'd0;
    wire        pready, pslverr, irq;
    wire [31:0] prdata;
    reg         scan_enable_0 = 1'b0, scan_in_0 = 1'b0, scan_in_1 = 1'b0;
    wire        scan_out_0, scan_out_1;

    gcd dut (
        .clk(clk), .reset(reset),
        .req_val(req_val), .req_rdy(req_rdy), .req_msg(req_msg),
        .resp_val(resp_val), .resp_rdy(resp_rdy), .resp_msg(resp_msg),
        .s_apb_psel(psel), .s_apb_penable(penable), .s_apb_pwrite(pwrite), .s_apb_pprot(3'b000),
        .s_apb_paddr(paddr), .s_apb_pwdata(pwdata), .s_apb_pstrb(4'hF), .s_apb_pready(pready),
        .s_apb_prdata(prdata), .s_apb_pslverr(pslverr), .irq(irq),
        .scan_enable_0(scan_enable_0), .scan_in_0(scan_in_0), .scan_in_1(scan_in_1),
        .scan_out_0(scan_out_0), .scan_out_1(scan_out_1)
    );

    always #10 clk = ~clk;

    integer errors = 0, i, w;
    reg [31:0] r;
    reg [15:0] ja [0:23];
    reg [15:0] jb [0:23];
    reg [15:0] x, y;

    function [15:0] ref_gcd(input [15:0] a, input [15:0] b);
        reg [15:0] p, q, t;
        begin
            p = a; q = b;
            while (q != 0) begin
                if (p < q) begin t = p; p = q; q = t; end
                else p = p - q;
            end
            ref_gcd = p;
        end
    endfunction

    task apb_wr(input [5:0] a, input [31:0] d);
        begin
            @(negedge clk); psel = 1; pwrite = 1; paddr = a; pwdata = d;
            @(negedge clk); penable = 1;
            @(posedge clk); while (!pready) @(posedge clk);
            @(negedge clk); psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_rd(input [5:0] a, output [31:0] d);
        begin
            @(negedge clk); psel = 1; pwrite = 0; paddr = a;
            @(negedge clk); penable = 1;
            @(posedge clk); while (!pready) @(posedge clk);
            d = prdata;
            @(negedge clk); psel = 0; penable = 0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset = 0;
        // queue: 24 jobs
        apb_wr(6'h00, 32'h8);                                   // q_clr
        for (i = 0; i < 24; i = i + 1) begin
            ja[i] = $random % 2000; jb[i] = $random % 2000;
            if (i == 5) jb[i] = 0;
            if (i == 6) ja[i] = jb[i];
            apb_wr(6'h10, {ja[i], jb[i]});
        end
        apb_rd(6'h14, r);
        if (r != 24) begin errors = errors + 1; $display("ERROR JOB_COUNT %0d", r); end
        apb_wr(6'h00, 32'h2);                                   // cnt_clr
        apb_wr(6'h00, 32'h5);                                   // start + irq_en
        w = 0;
        while (!irq && w < 400000) begin @(posedge clk); w = w + 1; end
        if (!irq) begin errors = errors + 1; $display("ERROR no irq at queue completion"); end
        apb_rd(6'h20, r);
        if (r != 24) begin errors = errors + 1; $display("ERROR RES_COUNT %0d", r); end
        for (i = 0; i < 24; i = i + 1) begin
            apb_wr(6'h18, i);
            apb_rd(6'h1C, r);
            if (r[15:0] !== ref_gcd(ja[i], jb[i])) begin
                errors = errors + 1;
                $display("ERROR job %0d gcd(%0d,%0d)=%0d expected %0d", i, ja[i], jb[i], r[15:0], ref_gcd(ja[i], jb[i]));
            end
        end
        apb_wr(6'h04, 32'h4);                                   // W1C irq
        apb_rd(6'h04, r);
        if (r[2] || irq) begin errors = errors + 1; $display("ERROR irq not cleared"); end
        // stream: 16 requests
        for (i = 0; i < 16; i = i + 1) begin
            x = $random % 3000; y = $random % 3000;
            @(negedge clk); while (!req_rdy) @(negedge clk);
            req_msg = {x, y}; req_val = 1;
            @(negedge clk); req_val = 0;
            w = 0;
            while (!resp_val && w < 100000) begin @(negedge clk); w = w + 1; end
            if (resp_msg !== ref_gcd(x, y)) begin
                errors = errors + 1; $display("ERROR stream gcd(%0d,%0d)=%0d", x, y, resp_msg);
            end
            resp_rdy = 1; @(negedge clk); resp_rdy = 0;
        end
        apb_rd(6'h0C, r);
        if (r != 40) begin errors = errors + 1; $display("ERROR OPCOUNT %0d (expected 40)", r); end
        $display("Tests: 41 checks");
        $display("Errors: %0d", errors);
        if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
