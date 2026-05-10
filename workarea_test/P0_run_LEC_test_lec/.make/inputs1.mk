# CBFlow LEC inputs1 Stage Makefile
# Auto-generated for LEC flow

# inputs1 stage with subnodes: setup, netlist_golden, netlist_revised, constraints, validate, finish

INPUTS1_SETUP_STAMP = $(STAMP_DIR)/inputs1_setup.stamp
INPUTS1_NETLIST_GOLDEN_STAMP = $(STAMP_DIR)/inputs1_netlist_golden.stamp
INPUTS1_NETLIST_REVISED_STAMP = $(STAMP_DIR)/inputs1_netlist_revised.stamp
INPUTS1_CONSTRAINTS_STAMP = $(STAMP_DIR)/inputs1_constraints.stamp
INPUTS1_VALIDATE_STAMP = $(STAMP_DIR)/inputs1_validate.stamp
INPUTS1_FINISH_STAMP = $(STAMP_DIR)/inputs1_finish.stamp

.PHONY: inputs1
inputs1: $(INPUTS1_STAMP)

$(INPUTS1_STAMP): $(INPUTS1_SETUP_STAMP) $(INPUTS1_NETLIST_GOLDEN_STAMP) $(INPUTS1_NETLIST_REVISED_STAMP) $(INPUTS1_CONSTRAINTS_STAMP) $(INPUTS1_VALIDATE_STAMP) $(INPUTS1_FINISH_STAMP)
	@echo "done inputs1 stage completed"
	@touch $@

# inputs1 setup subnode
$(INPUTS1_SETUP_STAMP): 
	@echo "Running inputs1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/inputs_subnode_handler.tcl" setup "$(PWD)" inputs1
	@echo "done inputs1 setup completed"
	@touch $@

# inputs1 netlist_golden subnode
$(INPUTS1_NETLIST_GOLDEN_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 netlist_golden..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/inputs_subnode_handler.tcl" netlist_golden "$(PWD)" inputs1
	@echo "done inputs1 netlist_golden completed"
	@touch $@

# inputs1 netlist_revised subnode
$(INPUTS1_NETLIST_REVISED_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 netlist_revised..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/inputs_subnode_handler.tcl" netlist_revised "$(PWD)" inputs1
	@echo "done inputs1 netlist_revised completed"
	@touch $@

# inputs1 constraints subnode
$(INPUTS1_CONSTRAINTS_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 constraints..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/inputs_subnode_handler.tcl" constraints "$(PWD)" inputs1
	@echo "done inputs1 constraints completed"
	@touch $@

# inputs1 validate subnode
$(INPUTS1_VALIDATE_STAMP): $(INPUTS1_NETLIST_GOLDEN_STAMP) $(INPUTS1_NETLIST_REVISED_STAMP) $(INPUTS1_CONSTRAINTS_STAMP)
	@echo "Running inputs1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/inputs_subnode_handler.tcl" validate "$(PWD)" inputs1
	@echo "done inputs1 validate completed"
	@touch $@

# inputs1 finish subnode
$(INPUTS1_FINISH_STAMP): $(INPUTS1_VALIDATE_STAMP)
	@echo "Running inputs1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/inputs_subnode_handler.tcl" finish "$(PWD)" inputs1
	@echo "done inputs1 finish completed"
	@touch $@

