# CBFlow LEC setup1 Stage Makefile
# Auto-generated for LEC flow

# setup1 stage with subnodes: setup, run, validate, finish

SETUP1_SETUP_STAMP = $(STAMP_DIR)/setup1_setup.stamp
SETUP1_RUN_STAMP = $(STAMP_DIR)/setup1_run.stamp
SETUP1_VALIDATE_STAMP = $(STAMP_DIR)/setup1_validate.stamp
SETUP1_FINISH_STAMP = $(STAMP_DIR)/setup1_finish.stamp

.PHONY: setup1
setup1: $(SETUP1_STAMP)

$(SETUP1_STAMP): $(SETUP1_FINISH_STAMP)
	@echo "done setup1 stage completed"
	@touch $@

# setup1 setup subnode
$(SETUP1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running setup1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/setup_subnode_handler.tcl" setup "$(PWD)" setup1
	@echo "done setup1 setup completed"
	@touch $@

# setup1 run subnode
$(SETUP1_RUN_STAMP): $(SETUP1_SETUP_STAMP)
	@echo "Running setup1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/setup_subnode_handler.tcl" run "$(PWD)" setup1
	@echo "done setup1 run completed"
	@touch $@

# setup1 validate subnode
$(SETUP1_VALIDATE_STAMP): $(SETUP1_RUN_STAMP)
	@echo "Running setup1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/setup_subnode_handler.tcl" validate "$(PWD)" setup1
	@echo "done setup1 validate completed"
	@touch $@

# setup1 finish subnode
$(SETUP1_FINISH_STAMP): $(SETUP1_VALIDATE_STAMP)
	@echo "Running setup1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/setup_subnode_handler.tcl" finish "$(PWD)" setup1
	@echo "done setup1 finish completed"
	@touch $@

