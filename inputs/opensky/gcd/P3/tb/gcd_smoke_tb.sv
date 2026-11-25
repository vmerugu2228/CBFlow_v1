// gcd P3 accelerator — directed smoke test (queue: 20 jobs + read-back + irq; stream: 10;
// counters). Verilator --binary --timing with the SRAM model; prints TEST PASSED / FAILED.
`timescale 1ns/1ps
module tb;
  logic clk = 0, reset = 1;
  always #10 clk = ~clk;
  logic req_val = 0, resp_rdy = 0; logic [31:0] req_msg = 0;
  wire req_rdy, resp_val; wire [15:0] resp_msg;
  logic psel = 0, penable = 0, pwrite = 0; logic [5:0] paddr = 0; logic [31:0] pwdata = 0;
  wire pready, pslverr, irq; wire [31:0] prdata;
  gcd dut(.clk, .reset, .req_val, .req_rdy, .req_msg, .resp_val, .resp_rdy, .resp_msg,
          .s_apb_psel(psel), .s_apb_penable(penable), .s_apb_pwrite(pwrite), .s_apb_pprot(3'b0),
          .s_apb_paddr(paddr), .s_apb_pwdata(pwdata), .s_apb_pstrb(4'hF), .s_apb_pready(pready),
          .s_apb_prdata(prdata), .s_apb_pslverr(pslverr), .irq);
  int errors = 0;
  function automatic logic [15:0] ref_gcd(logic [15:0] x, logic [15:0] y);
    logic [15:0] t; while (y != 0) begin if (x < y) begin t = x; x = y; y = t; end else x = x - y; end return x;
  endfunction
  task automatic apb_wr(logic [5:0] a, logic [31:0] d);
    @(negedge clk); psel = 1; pwrite = 1; paddr = a; pwdata = d; @(negedge clk); penable = 1;
    do @(posedge clk); while (!pready); @(negedge clk); psel = 0; penable = 0; pwrite = 0;
  endtask
  task automatic apb_rd(logic [5:0] a, output logic [31:0] d);
    @(negedge clk); psel = 1; pwrite = 0; paddr = a; @(negedge clk); penable = 1;
    do @(posedge clk); while (!pready); d = prdata; @(negedge clk); psel = 0; penable = 0;
  endtask
  logic [31:0] r; logic [15:0] ja [20], jb [20];
  initial begin
    repeat (3) @(negedge clk); reset = 0;
    // queue: 20 jobs
    for (int i = 0; i < 20; i++) begin ja[i] = $urandom % 3000; jb[i] = $urandom % 3000; if (i == 3) jb[i] = 0; apb_wr(6'h10, {ja[i], jb[i]}); end
    apb_rd(6'h14, r); if (r != 20) begin errors++; $display("ERROR JOB_COUNT %0d", r); end
    apb_wr(6'h00, 32'h1);           // irq_en
    apb_wr(6'h00, 32'h5);           // start (+ irq_en)
    fork : w begin wait (irq); end begin repeat (200000) @(posedge clk); $display("ERROR queue timeout"); errors++; end join_any
    disable w;
    apb_rd(6'h20, r); if (r != 20) begin errors++; $display("ERROR RES_COUNT %0d", r); end
    for (int i = 0; i < 20; i++) begin
      apb_wr(6'h18, i); apb_rd(6'h1C, r);
      if (r[15:0] !== ref_gcd(ja[i], jb[i])) begin errors++; $display("ERROR job %0d gcd(%0d,%0d)=%0d exp %0d", i, ja[i], jb[i], r[15:0], ref_gcd(ja[i], jb[i])); end
    end
    apb_wr(6'h04, 32'h4);           // W1C irq
    apb_rd(6'h04, r); if (r[2] || irq) begin errors++; $display("ERROR irq not cleared"); end
    // stream
    for (int i = 0; i < 10; i++) begin
      logic [15:0] x = $urandom % 5000, y = $urandom % 5000;
      @(negedge clk); while (!req_rdy) @(negedge clk); req_msg = {x, y}; req_val = 1; @(negedge clk); req_val = 0;
      while (!resp_val) @(negedge clk);
      if (resp_msg !== ref_gcd(x, y)) begin errors++; $display("ERROR stream gcd(%0d,%0d)=%0d", x, y, resp_msg); end
      resp_rdy = 1; @(negedge clk); resp_rdy = 0;
    end
    apb_rd(6'h0C, r); if (r != 30) begin errors++; $display("ERROR OPCOUNT %0d", r); end
    $display("Errors: %0d", errors);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED");
    $finish;
  end
endmodule
