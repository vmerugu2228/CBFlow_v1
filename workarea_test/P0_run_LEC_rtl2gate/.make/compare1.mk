# CBFlow LEC compare1 Stage Makefile
# Auto-generated for LEC flow

# compare1 stage with subnodes: setup, run, validate, finish

COMPARE1_SETUP_STAMP = $(STAMP_DIR)/compare1_setup.stamp
COMPARE1_RUN_STAMP = $(STAMP_DIR)/compare1_run.stamp
COMPARE1_VALIDATE_STAMP = $(STAMP_DIR)/compare1_validate.stamp
COMPARE1_FINISH_STAMP = $(STAMP_DIR)/compare1_finish.stamp

.PHONY: compare1
compare1: $(COMPARE1_STAMP)

$(COMPARE1_STAMP): $(COMPARE1_FINISH_STAMP)
	@echo "done compare1 stage completed"
	@touch $@

# compare1 setup subnode
$(COMPARE1_SETUP_STAMP): $(SETUP1_STAMP)
	@echo "Running compare1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/compare_subnode_handler.tcl" setup "$(PWD)" compare1
	@echo "done compare1 setup completed"
	@touch $@

# compare1 run subnode
$(COMPARE1_RUN_STAMP): $(COMPARE1_SETUP_STAMP)
	@echo "Running compare1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/compare_subnode_handler.tcl" run "$(PWD)" compare1
	@echo "done compare1 run completed"
	@touch $@

# compare1 validate subnode
$(COMPARE1_VALIDATE_STAMP): $(COMPARE1_RUN_STAMP)
	@echo "Running compare1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/compare_subnode_handler.tcl" validate "$(PWD)" compare1
	@echo "done compare1 validate completed"
	@touch $@

# compare1 finish subnode
$(COMPARE1_FINISH_STAMP): $(COMPARE1_VALIDATE_STAMP)
	@echo "Running compare1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/compare_subnode_handler.tcl" finish "$(PWD)" compare1
	@echo "done compare1 finish completed"
	@touch $@

