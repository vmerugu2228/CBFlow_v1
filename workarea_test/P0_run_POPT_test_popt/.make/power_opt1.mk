# CBFlow POPT power_opt1 Stage Makefile
# Auto-generated for POPT flow

# power_opt1 stage with subnodes: setup, run, validate, finish

POWER_OPT1_SETUP_STAMP = $(STAMP_DIR)/power_opt1_setup.stamp
POWER_OPT1_RUN_STAMP = $(STAMP_DIR)/power_opt1_run.stamp
POWER_OPT1_VALIDATE_STAMP = $(STAMP_DIR)/power_opt1_validate.stamp
POWER_OPT1_FINISH_STAMP = $(STAMP_DIR)/power_opt1_finish.stamp

.PHONY: power_opt1
power_opt1: $(POWER_OPT1_STAMP)

$(POWER_OPT1_STAMP): $(POWER_OPT1_FINISH_STAMP)
	@echo "done power_opt1 stage completed"
	@touch $@

# power_opt1 setup subnode
$(POWER_OPT1_SETUP_STAMP): $(MERGE_TIMING1_STAMP)
	@echo "Running power_opt1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/power_opt_subnode_handler.tcl" setup "$(PWD)" power_opt1
	@echo "done power_opt1 setup completed"
	@touch $@

# power_opt1 run subnode
$(POWER_OPT1_RUN_STAMP): $(POWER_OPT1_SETUP_STAMP)
	@echo "Running power_opt1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/power_opt_subnode_handler.tcl" run "$(PWD)" power_opt1
	@echo "done power_opt1 run completed"
	@touch $@

# power_opt1 validate subnode
$(POWER_OPT1_VALIDATE_STAMP): $(POWER_OPT1_RUN_STAMP)
	@echo "Running power_opt1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/power_opt_subnode_handler.tcl" validate "$(PWD)" power_opt1
	@echo "done power_opt1 validate completed"
	@touch $@

# power_opt1 finish subnode
$(POWER_OPT1_FINISH_STAMP): $(POWER_OPT1_VALIDATE_STAMP)
	@echo "Running power_opt1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/power_opt_subnode_handler.tcl" finish "$(PWD)" power_opt1
	@echo "done power_opt1 finish completed"
	@touch $@

