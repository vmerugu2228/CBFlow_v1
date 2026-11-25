// gcd_coverage — functional coverage of the gcd accelerator (user-owned;
// replaces the uvmgen stub). Coverpoint names are the vPlan coverage items;
// CBflow reads their bins from the merged coverage database.
//   F1 operands_zero operands_equal a_lt_b     F2 resp_stall back_to_back_req
//   F3 reg_read_all reg_write_ctrl             F4 queue_len_1 queue_len_max queue_rerun
//   F5 res_addr_all                            F6 irq_set irq_clear irq_masked
//   F7 count_clear count_wrap                  F8 start_with_req_pending
//   F9 mbist_pass_both — needs the MBIST collar (DFT phase 5): not implemented
class gcd_coverage extends uvm_component;
    `uvm_component_utils(gcd_coverage)
    uvm_reg_block regmodel;
    gcd_regs_ral_pkg::gcd_regs rm;
    uvm_tlm_analysis_fifo #(gcd_req_item)  req_fifo;
    uvm_tlm_analysis_fifo #(gcd_resp_item) resp_fifo;
    uvm_tlm_analysis_fifo #(gcd_csr_item)  csr_fifo;
    virtual gcd_req_if  req_vif;
    virtual gcd_resp_if resp_vif;

    // sampled values
    int unsigned zk, eq, lt;                 // operand classes of a request
    int unsigned stall, gap;                 // response stall / request gap (cycles)
    int unsigned rd_idx, ctrl_f;             // register read index / CTRL field written
    int unsigned qlen, rerun, res_addr;
    bit irq_rd, irq_w1c, irq_msk, cnt_clr, wrapped, pend;

    // queue / counter tracking
    int unsigned pushed, last_len;
    bit irq_en;
    longint unsigned ops_since_clr;

    covergroup cg_ops;
        operands_zero:  coverpoint zk  { bins a_zero = {1}; bins b_zero = {2}; bins both_zero = {3}; }
        operands_equal: coverpoint eq  { bins equal = {1}; }
        a_lt_b:         coverpoint lt  { bins a_lt_b = {1}; bins a_ge_b = {0}; }
    endgroup
    covergroup cg_stream;
        resp_stall:       coverpoint stall { bins none = {0}; bins short_stall = {[1:3]}; bins long_stall = {[4:1000000]}; }
        back_to_back_req: coverpoint gap   { bins back_to_back = {0}; bins idle = {[1:1000000]}; }
    endgroup
    covergroup cg_regs;
        reg_read_all:   coverpoint rd_idx { bins ctrl = {0}; bins status = {1}; bins result = {2}; bins opcount = {3};
                                            bins job_count = {5}; bins res_addr = {6}; bins res_data = {7}; bins res_count = {8}; }
        reg_write_ctrl: coverpoint ctrl_f { bins irq_en = {0}; bins cnt_clr = {1}; bins start = {2}; bins q_clr = {3}; }
    endgroup
    covergroup cg_queue;
        queue_len_1:   coverpoint qlen  { bins one = {1}; }
        queue_len_max: coverpoint qlen  { bins full = {256}; }
        queue_rerun:   coverpoint rerun { bins rerun = {1}; }
    endgroup
    covergroup cg_res;
        res_addr_all: coverpoint res_addr { bins addr[] = {[0:255]}; }
    endgroup
    covergroup cg_irq;
        irq_set:    coverpoint irq_rd  { bins set = {1}; }
        irq_clear:  coverpoint irq_w1c { bins cleared = {1}; }
        irq_masked: coverpoint irq_msk { bins masked = {1}; }
    endgroup
    covergroup cg_count;
        count_clear: coverpoint cnt_clr { bins cleared = {1}; }
        count_wrap:  coverpoint wrapped { bins wrapped = {1}; }
    endgroup
    covergroup cg_arb;
        start_with_req_pending: coverpoint pend { bins pending = {1}; }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_ops = new(); cg_stream = new(); cg_regs = new(); cg_queue = new();
        cg_res = new(); cg_irq = new(); cg_count = new(); cg_arb = new();
    endfunction

    function void build_phase(uvm_phase phase);
        req_fifo = new("req_fifo", this); resp_fifo = new("resp_fifo", this); csr_fifo = new("csr_fifo", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        if (!$cast(rm, regmodel)) `uvm_fatal("COV", "register model is not gcd_regs")
        if (!uvm_config_db #(virtual gcd_req_if)::get(null, "uvm_test_top.env.req_agt", "vif", req_vif))
            `uvm_fatal("COV", "req vif")
        if (!uvm_config_db #(virtual gcd_resp_if)::get(null, "uvm_test_top.env.resp_agt", "vif", resp_vif))
            `uvm_fatal("COV", "resp vif")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            forever begin gcd_req_item t;  req_fifo.get(t);  sample_req(t); end
            forever begin gcd_resp_item t; resp_fifo.get(t); ops_since_clr++; end
            forever begin gcd_csr_item t;  csr_fifo.get(t);  sample_csr(t); end
            watch_stream();
        join
    endtask

    // response stall and request gap, cycle by cycle (sampled at the rising
    // edge, as the DUT sees them)
    task watch_stream();
        int unsigned s = 0, g = 0;
        forever begin
            @(posedge resp_vif.clk);
            if (resp_vif.rst) continue;
            if (resp_vif.valid && !resp_vif.ready) s++;
            if (resp_vif.valid && resp_vif.ready) begin stall = s; cg_stream.sample(); s = 0; end
            if (req_vif.valid && req_vif.ready) begin gap = g; cg_stream.sample(); g = 0; end
            else if (!req_vif.valid) g++;
        end
    endtask

    function void sample_req(gcd_req_item t);
        bit [15:0] a = t.data[31:16], b = t.data[15:0];
        zk = {a == 0, b == 0} == 2'b10 ? 1 : {a == 0, b == 0} == 2'b01 ? 2 : (a == 0 && b == 0) ? 3 : 0;
        eq = (a == b && a != 0);
        lt = (a < b);
        cg_ops.sample();
    endfunction

    function void sample_csr(gcd_csr_item t);
        uvm_reg r = rm.default_map.get_reg_by_offset(t.addr, !t.write);
        if (r == null) return;
        if (!t.write) begin
            rd_idx = (t.addr >> 2); cg_regs.sample();
            if (r == rm.STATUS && t.data[2]) begin
                irq_rd = 1; irq_msk = !irq_en; cg_irq.sample(); irq_rd = 0; irq_msk = 0;
            end
            if (r == rm.OPCOUNT) begin wrapped = (ops_since_clr >= 65536); cg_count.sample(); wrapped = 0; end
            return;
        end
        if (r == rm.CTRL) begin
            for (int f = 0; f < 4; f++) if (t.data[f]) begin ctrl_f = f; cg_regs.sample(); end
            irq_en = t.data[0];
            if (t.data[1]) begin cnt_clr = 1; cg_count.sample(); cnt_clr = 0; ops_since_clr = 0; end
            if (t.data[3]) pushed = 0;
            if (t.data[2]) begin
                // the request driver holds valid while the engine is busy
                pend = req_vif.valid && !req_vif.ready; cg_arb.sample(); pend = 0;
                rerun = (pushed == 0 && last_len != 0);
                qlen = pushed ? (pushed > 256 ? 256 : pushed) : 0;
                if (pushed) last_len = qlen;
                cg_queue.sample(); rerun = 0;
                ops_since_clr += last_len;
                pushed = 0;
            end
        end else if (r == rm.JOB_DATA) begin
            pushed++;
        end else if (r == rm.STATUS && t.data[2]) begin
            irq_w1c = 1; cg_irq.sample(); irq_w1c = 0;
        end else if (r == rm.RES_ADDR) begin
            res_addr = t.data[7:0]; cg_res.sample();
        end
    endfunction
endclass
