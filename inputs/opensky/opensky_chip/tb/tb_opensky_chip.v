// opensky_chip smoke test — GCD through ctrl_subsys + one MAC readout through ai_subsys.
// Run: cbflow-oss exec -- sh -c "iverilog -g2005 -o sim.vvp tb_opensky_chip.v sim_cells.v <all block .v + common/cbf_iso_clamp0.v> && vvp -n sim.vvp"
`timescale 1ns/1ps
module tb_opensky_chip;
  reg clk=0, rst_n=0, we=0, re=0; reg [7:0] addr=0; reg [31:0] wd=0; wire [31:0] rd; wire irq; wire gcd_pwr_en, mac_pwr_en;
  opensky_chip dut(.clk(clk),.rst_n(rst_n),.host_we(we),.host_re(re),.host_addr(addr),.host_wdata(wd),.host_rdata(rd),.irq(irq),.gcd_pwr_en(gcd_pwr_en),.mac_pwr_en(mac_pwr_en));
  always #5 clk=~clk;
  task wr(input [7:0] a, input [31:0] d); begin @(negedge clk); we=1; addr=a; wd=d; @(negedge clk); we=0; end endtask
  task rdw(input [7:0] a, output [31:0] d); begin @(negedge clk); re=1; addr=a; @(negedge clk); d=rd; re=0; end endtask
  reg [31:0] v; integer k, errs=0;
  initial begin
    repeat(3) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
    // GCD(48,18)=6
    wr(8'h00, {16'd48,16'd18});
    wait(irq); rdw(8'h01, v); $display("GCD(48,18) = %0d", v); if (v!==6) errs=errs+1;
    // MAC: row r operand = r+1, column c operand = 2 -> after 3 steps acc[r][c] = 3*2*(r+1)
    wr(8'h40, 32'h04030201); wr(8'h41, 32'h08070605); wr(8'h42, 32'h0c0b0a09); wr(8'h43, 32'h100f0e0d);
    for (k=0;k<4;k=k+1) wr(8'h44+k, 32'h02020202);
    wr(8'h48, 32'h2);                       // clear
    repeat(3) wr(8'h48, 32'h1);             // 3 steps (operands static -> every PE sees a*b each step once propagated)
    repeat(40) wr(8'h48, 32'h1);            // let the wavefront fill the array
    wr(8'h48, 32'h4);                       // drain one row: bottom row (r=15) moves out
    rdw(8'h50, v); $display("RESULT word0 = 0x%08x  acc[15][0]=%0d (expect 29*15*2=870)", v, v[23:0]); if (v[23:0]!==870) errs=errs+1;
    rdw(8'h49, v); $display("STATUS steps = %0d", v[31:16]);
    if (v[31:16] != 43) errs=errs+1;
    // Low power: isolate PD_MAC -> its outputs clamp to 0; release -> data back
    rdw(8'h04, v); $display("PWR_CTRL reset = 0x%0h (expect a: both pwr_en=1, iso=0)", v[3:0]); if (v[3:0]!==4'ha) errs=errs+1;
    wr(8'h04, 32'he);                      // mac_iso=1 (gcd on, mac on, mac isolated)
    rdw(8'h50, v); $display("MAC isolated  : word0 = 0x%08x (expect 0)", v); if (v!==0) errs=errs+1;
    wr(8'h04, 32'h6);                      // mac_pwr_en=0 while isolated -> switch-off request
    if (mac_pwr_en!==1'b0) errs=errs+1; $display("mac_pwr_en = %b (expect 0)", mac_pwr_en);
    wr(8'h04, 32'he); wr(8'h04, 32'ha);    // power up, then release isolation
    rdw(8'h50, v); $display("MAC released  : acc = %0d (expect 870)", v[23:0]); if (v[23:0]!==870) errs=errs+1;
    if (errs==0) $display("SIM PASS"); else $display("SIM FAIL (%0d errors)", errs); $finish;
  end
endmodule
