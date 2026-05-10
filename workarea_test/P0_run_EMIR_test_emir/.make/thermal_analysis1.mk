# CBFlow EMIR thermal_analysis1 Stage Makefile
# Auto-generated for EMIR flow

# thermal_analysis1 stage with subnodes: setup, run, validate, finish

THERMAL_ANALYSIS1_SETUP_STAMP = $(STAMP_DIR)/thermal_analysis1_setup.stamp
THERMAL_ANALYSIS1_RUN_STAMP = $(STAMP_DIR)/thermal_analysis1_run.stamp
THERMAL_ANALYSIS1_VALIDATE_STAMP = $(STAMP_DIR)/thermal_analysis1_validate.stamp
THERMAL_ANALYSIS1_FINISH_STAMP = $(STAMP_DIR)/thermal_analysis1_finish.stamp

.PHONY: thermal_analysis1
thermal_analysis1: $(THERMAL_ANALYSIS1_STAMP)

$(THERMAL_ANALYSIS1_STAMP): $(THERMAL_ANALYSIS1_FINISH_STAMP)
	@echo "done thermal_analysis1 stage completed"
	@touch $@

# thermal_analysis1 setup subnode
$(THERMAL_ANALYSIS1_SETUP_STAMP): $(IR_DROP1_STAMP)
	@echo "Running thermal_analysis1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/thermal_analysis_subnode_handler.tcl" setup "$(PWD)" thermal_analysis1
	@echo "done thermal_analysis1 setup completed"
	@touch $@

# thermal_analysis1 run subnode
$(THERMAL_ANALYSIS1_RUN_STAMP): $(THERMAL_ANALYSIS1_SETUP_STAMP)
	@echo "Running thermal_analysis1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/thermal_analysis_subnode_handler.tcl" run "$(PWD)" thermal_analysis1
	@echo "done thermal_analysis1 run completed"
	@touch $@

# thermal_analysis1 validate subnode
$(THERMAL_ANALYSIS1_VALIDATE_STAMP): $(THERMAL_ANALYSIS1_RUN_STAMP)
	@echo "Running thermal_analysis1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/thermal_analysis_subnode_handler.tcl" validate "$(PWD)" thermal_analysis1
	@echo "done thermal_analysis1 validate completed"
	@touch $@

# thermal_analysis1 finish subnode
$(THERMAL_ANALYSIS1_FINISH_STAMP): $(THERMAL_ANALYSIS1_VALIDATE_STAMP)
	@echo "Running thermal_analysis1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/thermal_analysis_subnode_handler.tcl" finish "$(PWD)" thermal_analysis1
	@echo "done thermal_analysis1 finish completed"
	@touch $@

