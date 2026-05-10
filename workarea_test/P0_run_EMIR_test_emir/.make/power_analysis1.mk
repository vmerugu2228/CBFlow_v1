# CBFlow EMIR power_analysis1 Stage Makefile
# Auto-generated for EMIR flow

# power_analysis1 stage with subnodes: setup, run, validate, finish

POWER_ANALYSIS1_SETUP_STAMP = $(STAMP_DIR)/power_analysis1_setup.stamp
POWER_ANALYSIS1_RUN_STAMP = $(STAMP_DIR)/power_analysis1_run.stamp
POWER_ANALYSIS1_VALIDATE_STAMP = $(STAMP_DIR)/power_analysis1_validate.stamp
POWER_ANALYSIS1_FINISH_STAMP = $(STAMP_DIR)/power_analysis1_finish.stamp

.PHONY: power_analysis1
power_analysis1: $(POWER_ANALYSIS1_STAMP)

$(POWER_ANALYSIS1_STAMP): $(POWER_ANALYSIS1_FINISH_STAMP)
	@echo "done power_analysis1 stage completed"
	@touch $@

# power_analysis1 setup subnode
$(POWER_ANALYSIS1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running power_analysis1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/power_analysis_subnode_handler.tcl" setup "$(PWD)" power_analysis1
	@echo "done power_analysis1 setup completed"
	@touch $@

# power_analysis1 run subnode
$(POWER_ANALYSIS1_RUN_STAMP): $(POWER_ANALYSIS1_SETUP_STAMP)
	@echo "Running power_analysis1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/power_analysis_subnode_handler.tcl" run "$(PWD)" power_analysis1
	@echo "done power_analysis1 run completed"
	@touch $@

# power_analysis1 validate subnode
$(POWER_ANALYSIS1_VALIDATE_STAMP): $(POWER_ANALYSIS1_RUN_STAMP)
	@echo "Running power_analysis1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/power_analysis_subnode_handler.tcl" validate "$(PWD)" power_analysis1
	@echo "done power_analysis1 validate completed"
	@touch $@

# power_analysis1 finish subnode
$(POWER_ANALYSIS1_FINISH_STAMP): $(POWER_ANALYSIS1_VALIDATE_STAMP)
	@echo "Running power_analysis1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/power_analysis_subnode_handler.tcl" finish "$(PWD)" power_analysis1
	@echo "done power_analysis1 finish completed"
	@touch $@

