# CBFlow STA reporting1 Stage Makefile
# Auto-generated for STA flow

# reporting1 stage with subnodes: setup, run, validate, finish

REPORTING1_SETUP_STAMP = $(STAMP_DIR)/reporting1_setup.stamp
REPORTING1_RUN_STAMP = $(STAMP_DIR)/reporting1_run.stamp
REPORTING1_VALIDATE_STAMP = $(STAMP_DIR)/reporting1_validate.stamp
REPORTING1_FINISH_STAMP = $(STAMP_DIR)/reporting1_finish.stamp

.PHONY: reporting1
reporting1: $(REPORTING1_STAMP)

$(REPORTING1_STAMP): $(REPORTING1_FINISH_STAMP)
	@echo "done reporting1 stage completed"
	@touch $@

# reporting1 setup subnode
$(REPORTING1_SETUP_STAMP): $(TIMING1_STAMP)
	@echo "Running reporting1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/reporting_subnode_handler.tcl" setup "$(PWD)" reporting1
	@echo "done reporting1 setup completed"
	@touch $@

# reporting1 run subnode
$(REPORTING1_RUN_STAMP): $(REPORTING1_SETUP_STAMP)
	@echo "Running reporting1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/reporting_subnode_handler.tcl" run "$(PWD)" reporting1
	@echo "done reporting1 run completed"
	@touch $@

# reporting1 validate subnode
$(REPORTING1_VALIDATE_STAMP): $(REPORTING1_RUN_STAMP)
	@echo "Running reporting1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/reporting_subnode_handler.tcl" validate "$(PWD)" reporting1
	@echo "done reporting1 validate completed"
	@touch $@

# reporting1 finish subnode
$(REPORTING1_FINISH_STAMP): $(REPORTING1_VALIDATE_STAMP)
	@echo "Running reporting1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/reporting_subnode_handler.tcl" finish "$(PWD)" reporting1
	@echo "done reporting1 finish completed"
	@touch $@

