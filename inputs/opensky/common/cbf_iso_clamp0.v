// =============================================================================
// cbf_iso_clamp0 — clamp-to-0 isolation for a W-bit bus leaving a switchable
// power domain. One sky130_fd_sc_hd__lpflow_inputiso0p_1 per bit
// (X = A & !SLEEP, is_isolation_cell), placed in the always-on parent and
// powered by the parent's primary supply. iso = 1 while the source domain is
// off (or switching). These are the cells the UPF set_isolation -instance
// strategies name; synthesis keeps them as library cells.
// =============================================================================
module cbf_iso_clamp0 #(parameter W = 1) (
    input  wire [W-1:0] a,
    input  wire         iso,
    output wire [W-1:0] y
);
    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : g_iso
            sky130_fd_sc_hd__lpflow_inputiso0p_1 u_iso (.A(a[i]), .SLEEP(iso), .X(y[i]));
        end
    endgenerate
endmodule
