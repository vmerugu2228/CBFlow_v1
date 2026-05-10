# CBFlow PV lvs1 Stage Makefile
# Auto-generated for PV flow

# lvs1 stage with subnodes: setup, run, validate, finish

LVS1_SETUP_STAMP = $(STAMP_DIR)/lvs1_setup.stamp
LVS1_RUN_STAMP = $(STAMP_DIR)/lvs1_run.stamp
LVS1_VALIDATE_STAMP = $(STAMP_DIR)/lvs1_validate.stamp
LVS1_FINISH_STAMP = $(STAMP_DIR)/lvs1_finish.stamp

.PHONY: lvs1
lvs1: $(LVS1_STAMP)

$(LVS1_STAMP): $(LVS1_FINISH_STAMP)
	@echo "done lvs1 stage completed"
	@touch $@

# lvs1 setup subnode
$(LVS1_SETUP_STAMP): $(FILL1_STAMP)
	@echo "Running lvs1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/lvs_subnode_handler.tcl" setup "$(PWD)" lvs1
	@echo "done lvs1 setup completed"
	@touch $@

# lvs1 run subnode
$(LVS1_RUN_STAMP): $(LVS1_SETUP_STAMP)
	@echo "Running lvs1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/lvs_subnode_handler.tcl" run "$(PWD)" lvs1
	@echo "done lvs1 run completed"
	@touch $@

# lvs1 validate subnode
$(LVS1_VALIDATE_STAMP): $(LVS1_RUN_STAMP)
	@echo "Running lvs1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/lvs_subnode_handler.tcl" validate "$(PWD)" lvs1
	@echo "done lvs1 validate completed"
	@touch $@

# lvs1 finish subnode
$(LVS1_FINISH_STAMP): $(LVS1_VALIDATE_STAMP)
	@echo "Running lvs1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/lvs_subnode_handler.tcl" finish "$(PWD)" lvs1
	@echo "done lvs1 finish completed"
	@touch $@

