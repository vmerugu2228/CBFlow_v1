// Behavioural models of the sky130 cells instantiated directly in RTL (sim only).
module sky130_fd_sc_hd__lpflow_inputiso0p_1 (input A, input SLEEP, output X);
    assign X = A & ~SLEEP;
endmodule
