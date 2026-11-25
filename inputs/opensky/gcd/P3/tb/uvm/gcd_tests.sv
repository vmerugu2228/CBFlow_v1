// gcd_tests — tests of the gcd accelerator vPlan (user-owned). gcd_mbist_test
// (F9, M4) is not written: it needs the MBIST collar (DFT phase 5), so the
// uvmgen stub keeps failing it.

// ── sequences ───────────────────────────────────────────────────────────────
// stream requests with operand classes biased to the corners (F1)
class gcd_req_corner_seq extends uvm_sequence #(gcd_req_item);
    `uvm_object_utils(gcd_req_corner_seq)
    int unsigned count = 100;
    int unsigned max_operand = 16'hFFFF;
    bit no_delay = 0;
    function new(string name = "gcd_req_corner_seq"); super.new(name); endfunction
    task body();
        repeat (count) begin
            gcd_req_item t = gcd_req_item::type_id::create("t");
            int unsigned kind = $urandom_range(9);
            start_item(t);
            t.c_delay.constraint_mode(!no_delay);    // back-to-back: no idle-delay distribution
            if (!t.randomize() with {
                    data[31:16] <= max_operand; data[15:0] <= max_operand;
                    kind == 0 -> data[31:16] == 0;
                    kind == 1 -> data[15:0] == 0;
                    kind == 2 -> data[31:16] == data[15:0];
                    kind == 3 -> data[31:16] < data[15:0];
                    no_delay  -> delay == 0; })
                `uvm_fatal("RAND", "randomize failed")
            finish_item(t);
        end
    endtask
endclass

// many back-to-back requests without the constraint solver (each randomize()
// is a z3 call — the 16-bit counter-wrap check needs 65k operations)
class gcd_req_fast_seq extends uvm_sequence #(gcd_req_item);
    `uvm_object_utils(gcd_req_fast_seq)
    int unsigned count = 1000;
    int unsigned max_operand = 3;
    function new(string name = "gcd_req_fast_seq"); super.new(name); endfunction
    task body();
        repeat (count) begin
            gcd_req_item t = gcd_req_item::type_id::create("t");
            start_item(t);
            t.data = {16'($urandom_range(max_operand)), 16'($urandom_range(max_operand))};
            t.delay = 0;
            finish_item(t);
        end
    endtask
endclass

// one raw APB access (bypasses the register model — RO writes, etc.)
class gcd_csr_raw_seq extends uvm_sequence #(gcd_csr_item);
    `uvm_object_utils(gcd_csr_raw_seq)
    bit write; bit [5:0] addr; bit [31:0] data;
    function new(string name = "gcd_csr_raw_seq"); super.new(name); endfunction
    task body();
        gcd_csr_item t = gcd_csr_item::type_id::create("t");
        start_item(t); t.write = write; t.addr = addr; t.data = data; finish_item(t);
        data = t.data;
    endtask
endclass

// ── test base: register / queue helpers ─────────────────────────────────────
class gcd_test_base extends gcd_base_test;
    `uvm_component_utils(gcd_test_base)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task wr(uvm_reg r, bit [31:0] v);
        uvm_status_e st;
        r.write(st, v);
        if (st != UVM_IS_OK) `uvm_error("REG", $sformatf("write %s failed", r.get_name()))
    endtask
    task rd(uvm_reg r, output bit [31:0] v);
        uvm_status_e st; uvm_reg_data_t d;
        r.read(st, d); v = d;
        if (st != UVM_IS_OK) `uvm_error("REG", $sformatf("read %s failed", r.get_name()))
    endtask
    task expect_reg(uvm_reg r, bit [31:0] exp, string what);
        bit [31:0] v; rd(r, v);
        if (v !== exp) `uvm_error("CHECK", $sformatf("%s: %s = 0x%0h, expected 0x%0h", what, r.get_name(), v, exp))
    endtask
    // every accepted request answered (a sequence returns when its last
    // request is accepted — that operation may still be computing)
    task drain();
        while (env.sb.outstanding()) env.wait_cycles(1);
    endtask
    task stream(int unsigned n, int unsigned max_operand = 16'hFFFF, bit no_delay = 0);
        gcd_req_corner_seq s = gcd_req_corner_seq::type_id::create("s");
        s.count = n; s.max_operand = max_operand; s.no_delay = no_delay;
        s.start(env.req_agt.sqr);
        drain();
    endtask
    // push jobs, returning them
    task push_jobs(int unsigned n, ref bit [31:0] jobs[$]);
        repeat (n) begin
            bit [31:0] j = {16'($urandom_range(4000)), 16'($urandom_range(4000))};
            if ($urandom_range(7) == 0) j[15:0] = 0;
            jobs.push_back(j);
            wr(env.regmodel.JOB_DATA, j);
        end
    endtask
    // CTRL.start, then wait for the queue to finish (STATUS.q_busy low)
    task run_queue(bit irq_en = 0);
        bit [31:0] st;
        wr(env.regmodel.CTRL, {29'd0, 1'b1, 1'b0, irq_en});
        do begin env.wait_cycles(50); rd(env.regmodel.STATUS, st); end while (st[3]);
    endtask
    // RES_COUNT and every result against the model
    task check_results(bit [31:0] jobs[$]);
        int unsigned n = (jobs.size() > 256) ? 256 : jobs.size();
        expect_reg(env.regmodel.RES_COUNT, n, "results written");
        for (int i = 0; i < n; i++) begin
            bit [31:0] v;
            wr(env.regmodel.RES_ADDR, i);
            rd(env.regmodel.RES_DATA, v);
            if (v[15:0] !== gcd_ref_model::gcd(jobs[i][31:16], jobs[i][15:0]))
                `uvm_error("QUEUE", $sformatf("job %0d gcd(%0d,%0d): result %0d, expected %0d", i,
                           jobs[i][31:16], jobs[i][15:0], v[15:0], gcd_ref_model::gcd(jobs[i][31:16], jobs[i][15:0])))
        end
    endtask
endclass

// ── F1 gcd compute ──────────────────────────────────────────────────────────
class gcd_random_test extends gcd_test_base;
    `uvm_component_utils(gcd_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task body();
        stream(300);
        stream(100, 255);          // small operands: equal / zero / a<b often
    endtask
endclass

// ── F2 stream handshakes ────────────────────────────────────────────────────
class gcd_backpressure_test extends gcd_test_base;
    `uvm_component_utils(gcd_backpressure_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function void configure(); cfg.resp_ready_pct = 30; endfunction
    task body();
        stream(150, 1000, 1);      // back-to-back requests, response stalled 70 % of cycles
        stream(50, 1000, 0);
    endtask
endclass

// ── F3 register access ──────────────────────────────────────────────────────
class gcd_reg_reset_test extends gcd_test_base;
    `uvm_component_utils(gcd_reg_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task body();
        uvm_reg_hw_reset_seq s = uvm_reg_hw_reset_seq::type_id::create("s");
        s.model = env.regmodel;
        s.start(null);
    endtask
endclass

class gcd_reg_access_test extends gcd_test_base;
    `uvm_component_utils(gcd_reg_access_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task body();
        bit [31:0] v;
        uvm_reg regs[$];
        // RW fields hold what was written
        repeat (10) begin
            bit [7:0] a = $urandom;
            wr(env.regmodel.RES_ADDR, a); expect_reg(env.regmodel.RES_ADDR, a, "RES_ADDR rw");
        end
        wr(env.regmodel.CTRL, 32'h1); expect_reg(env.regmodel.CTRL, 32'h1, "CTRL.irq_en set");
        // single-pulse fields read back 0
        wr(env.regmodel.CTRL, 32'hB); expect_reg(env.regmodel.CTRL, 32'h1, "CTRL pulses self-clear");
        wr(env.regmodel.CTRL, 32'h0); expect_reg(env.regmodel.CTRL, 32'h0, "CTRL.irq_en clear");
        // read-only registers ignore writes
        begin
            gcd_csr_raw_seq s = gcd_csr_raw_seq::type_id::create("s");
            s.write = 1; s.addr = 6'h0C; s.data = 32'hFFFF; s.start(env.csr_agt.sqr);
            expect_reg(env.regmodel.OPCOUNT, 0, "OPCOUNT is read-only");
            s.write = 1; s.addr = 6'h14; s.data = 32'h1FF; s.start(env.csr_agt.sqr);
            expect_reg(env.regmodel.JOB_COUNT, 0, "JOB_COUNT is read-only");
        end
        // every readable register
        env.regmodel.get_registers(regs);
        foreach (regs[i]) if (regs[i].get_rights() != "WO") rd(regs[i], v);
    endtask
endclass

// ── F4 / F5 job queue + result read-back ────────────────────────────────────
class gcd_queue_test extends gcd_test_base;
    `uvm_component_utils(gcd_queue_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task body();
        for (int k = 0; k < 4; k++) begin
            bit [31:0] jobs[$];
            int unsigned n = (k == 0) ? 1 : $urandom_range(2, 40);
            wr(env.regmodel.CTRL, 32'h8);                     // q_clr
            push_jobs(n, jobs);
            expect_reg(env.regmodel.JOB_COUNT, n, "jobs loaded");
            run_queue();
            check_results(jobs);
            if (k == 3) begin                                  // re-run the same queue
                run_queue();
                check_results(jobs);
            end
        end
    endtask
endclass

class gcd_queue_full_test extends gcd_test_base;
    `uvm_component_utils(gcd_queue_full_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task body();
        bit [31:0] jobs[$];
        wr(env.regmodel.CTRL, 32'h8);
        push_jobs(260, jobs);                                  // 4 beyond the 256-job queue: dropped
        expect_reg(env.regmodel.JOB_COUNT, 256, "queue full");
        run_queue();
        check_results(jobs);
    endtask
endclass

// ── F6 interrupt ────────────────────────────────────────────────────────────
class gcd_irq_test extends gcd_test_base;
    `uvm_component_utils(gcd_irq_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task body();
        bit [31:0] st, jobs[$];
        // masked: STATUS.irq set by a stream result, the pin stays low
        wr(env.regmodel.CTRL, 32'h0);
        stream(1);
        env.wait_cycles(5);
        rd(env.regmodel.STATUS, st);
        if (!st[2]) `uvm_error("IRQ", "STATUS.irq not set by a stream result")
        if (env.misc_vif.irq) `uvm_error("IRQ", "irq pin high while CTRL.irq_en = 0")
        // enabled: the pin follows STATUS.irq
        wr(env.regmodel.CTRL, 32'h1);
        env.wait_cycles(2);
        if (!env.misc_vif.irq) `uvm_error("IRQ", "irq pin low with STATUS.irq and CTRL.irq_en set")
        // W1C clears it
        wr(env.regmodel.STATUS, 32'h4);
        env.wait_cycles(2);
        rd(env.regmodel.STATUS, st);
        if (st[2] || env.misc_vif.irq) `uvm_error("IRQ", "STATUS.irq / pin not cleared by W1C")
        // queue completion raises it
        wr(env.regmodel.CTRL, 32'h9);                          // q_clr + irq_en
        push_jobs(5, jobs);
        wr(env.regmodel.CTRL, 32'h5);                          // start + irq_en
        fork
            begin wait (env.misc_vif.irq); end
            begin env.wait_cycles(20000); `uvm_error("IRQ", "no irq at queue completion") end
        join_any
        disable fork;
        check_results(jobs);
        wr(env.regmodel.STATUS, 32'h4);
    endtask
endclass

// ── F7 counters ─────────────────────────────────────────────────────────────
class gcd_opcount_test extends gcd_test_base;
    `uvm_component_utils(gcd_opcount_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function void configure(); cfg.timeout_cycles = 4000000; endfunction
    task body();
        bit [31:0] jobs[$];
        wr(env.regmodel.CTRL, 32'h2);                          // cnt_clr
        expect_reg(env.regmodel.OPCOUNT, 0, "cleared");
        stream(37);
        wr(env.regmodel.CTRL, 32'h8); push_jobs(5, jobs); run_queue();
        expect_reg(env.regmodel.OPCOUNT, 42, "37 requests + 5 jobs");
        wr(env.regmodel.CTRL, 32'h2);
        expect_reg(env.regmodel.OPCOUNT, 0, "cnt_clr");
        // 16-bit wrap: 65536 + 3 operations
        // in 1000-item sequences: per-sequence bookkeeping grows with its item count
        for (int k = 0; k < 66; k++) begin
            gcd_req_fast_seq f = gcd_req_fast_seq::type_id::create("f");
            f.count = (k < 65) ? 1000 : 539; f.start(env.req_agt.sqr);
        end
        drain();
        expect_reg(env.regmodel.OPCOUNT, 3, "wrapped");
    endtask
endclass

// ── F8 stream / queue arbitration ───────────────────────────────────────────
class gcd_mixed_test extends gcd_test_base;
    `uvm_component_utils(gcd_mixed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function void configure(); cfg.resp_ready_pct = 50; endfunction
    task body();
        for (int k = 0; k < 5; k++) begin
            bit [31:0] jobs[$];
            wr(env.regmodel.CTRL, 32'h8);
            push_jobs($urandom_range(3, 20), jobs);
            // a start written while stream requests keep the engine busy must
            // still run the queue once the engine is free
            fork
                stream(30, 4000, 1);
                begin env.wait_cycles($urandom_range(20, 200)); wr(env.regmodel.CTRL, 32'h4); end
            join
            begin
                bit [31:0] st; int unsigned w = 0;
                do begin env.wait_cycles(50); rd(env.regmodel.STATUS, st); w++; end while (st[3] && w < 400);
            end
            check_results(jobs);
        end
    endtask
endclass
