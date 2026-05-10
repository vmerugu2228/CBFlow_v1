# CBFlow PV fill1 Stage Makefile
# Auto-generated for PV flow

# fill1 stage with subnodes: setup, run, validate, finish

FILL1_SETUP_STAMP = $(STAMP_DIR)/fill1_setup.stamp
FILL1_RUN_STAMP = $(STAMP_DIR)/fill1_run.stamp
FILL1_VALIDATE_STAMP = $(STAMP_DIR)/fill1_validate.stamp
FILL1_FINISH_STAMP = $(STAMP_DIR)/fill1_finish.stamp

.PHONY: fill1
fill1: $(FILL1_STAMP)

$(FILL1_STAMP): $(FILL1_FINISH_STAMP)
	@echo "done fill1 stage completed"
	@touch $@

# fill1 setup subnode
$(FILL1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running fill1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/fill_subnode_handler.tcl" setup "$(PWD)" fill1
	@echo "done fill1 setup completed"
	@touch $@

# fill1 run subnode
$(FILL1_RUN_STAMP): $(FILL1_SETUP_STAMP)
	@echo "Running fill1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/fill_subnode_handler.tcl" run "$(PWD)" fill1
	@echo "done fill1 run completed"
	@touch $@

# fill1 validate subnode
$(FILL1_VALIDATE_STAMP): $(FILL1_RUN_STAMP)
	@echo "Running fill1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/fill_subnode_handler.tcl" validate "$(PWD)" fill1
	@echo "done fill1 validate completed"
	@touch $@

# fill1 finish subnode
$(FILL1_FINISH_STAMP): $(FILL1_VALIDATE_STAMP)
	@echo "Running fill1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/fill_subnode_handler.tcl" finish "$(PWD)" fill1
	@echo "done fill1 finish completed"
	@touch $@

