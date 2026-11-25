// gcd_ref_model — reference model of the gcd accelerator (user-owned; replaces
// the uvmgen stub). Stream mode: every accepted request {a, b} produces one
// response gcd(a, b), in order. Queue results are checked by the tests through
// the register model, with gcd_ref_model::gcd().
class gcd_ref_model extends uvm_object;
    `uvm_object_utils(gcd_ref_model)
    gcd_resp_item exp_resp[$];
    bit stub = 0;

    function new(string name = "gcd_ref_model"); super.new(name); endfunction

    // Euclid by subtraction, as specified: gcd(a, 0) = a, gcd(0, b) = b
    static function bit [15:0] gcd(bit [15:0] a, bit [15:0] b);
        bit [15:0] t;
        while (b != 0) begin
            if (a < b) begin t = a; a = b; b = t; end
            else a = a - b;
        end
        return a;
    endfunction

    virtual function void observe_req(gcd_req_item t);
        gcd_resp_item e = gcd_resp_item::type_id::create("e");
        e.data = gcd(t.data[31:16], t.data[15:0]);
        exp_resp.push_back(e);
    endfunction

    virtual function void observe_csr(gcd_csr_item t);
    endfunction
endclass
