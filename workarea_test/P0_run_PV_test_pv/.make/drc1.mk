# CBFlow PV drc1 Stage Makefile
# Auto-generated for PV flow

# drc1 stage with subnodes: setup, run, validate, finish

DRC1_SETUP_STAMP = $(STAMP_DIR)/drc1_setup.stamp
DRC1_RUN_STAMP = $(STAMP_DIR)/drc1_run.stamp
DRC1_VALIDATE_STAMP = $(STAMP_DIR)/drc1_validate.stamp
DRC1_FINISH_STAMP = $(STAMP_DIR)/drc1_finish.stamp

.PHONY: drc1
drc1: $(DRC1_STAMP)

$(DRC1_STAMP): $(DRC1_FINISH_STAMP)
	@echo "done drc1 stage completed"
	@touch $@

# drc1 setup subnode
$(DRC1_SETUP_STAMP): $(FILL1_STAMP)
	@echo "Running drc1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/drc_subnode_handler.tcl" setup "$(PWD)" drc1
	@echo "done drc1 setup completed"
	@touch $@

# drc1 run subnode
$(DRC1_RUN_STAMP): $(DRC1_SETUP_STAMP)
	@echo "Running drc1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/drc_subnode_handler.tcl" run "$(PWD)" drc1
	@echo "done drc1 run completed"
	@touch $@

# drc1 validate subnode
$(DRC1_VALIDATE_STAMP): $(DRC1_RUN_STAMP)
	@echo "Running drc1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/drc_subnode_handler.tcl" validate "$(PWD)" drc1
	@echo "done drc1 validate completed"
	@touch $@

# drc1 finish subnode
$(DRC1_FINISH_STAMP): $(DRC1_VALIDATE_STAMP)
	@echo "Running drc1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/drc_subnode_handler.tcl" finish "$(PWD)" drc1
	@echo "done drc1 finish completed"
	@touch $@

