# CBFlow FCFP timing_budget1 Stage Makefile
# Auto-generated for FCFP flow

# timing_budget1 stage with subnodes: setup, run, validate, finish

TIMING_BUDGET1_SETUP_STAMP = $(STAMP_DIR)/timing_budget1_setup.stamp
TIMING_BUDGET1_RUN_STAMP = $(STAMP_DIR)/timing_budget1_run.stamp
TIMING_BUDGET1_VALIDATE_STAMP = $(STAMP_DIR)/timing_budget1_validate.stamp
TIMING_BUDGET1_FINISH_STAMP = $(STAMP_DIR)/timing_budget1_finish.stamp

.PHONY: timing_budget1
timing_budget1: $(TIMING_BUDGET1_STAMP)

$(TIMING_BUDGET1_STAMP): $(TIMING_BUDGET1_FINISH_STAMP)
	@echo "done timing_budget1 stage completed"
	@touch $@

# timing_budget1 setup subnode
$(TIMING_BUDGET1_SETUP_STAMP): $(TOP_COMPILE1_STAMP)
	@echo "Running timing_budget1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/timing_budget_subnode_handler.tcl" setup "$(PWD)" timing_budget1
	@echo "done timing_budget1 setup completed"
	@touch $@

# timing_budget1 run subnode
$(TIMING_BUDGET1_RUN_STAMP): $(TIMING_BUDGET1_SETUP_STAMP)
	@echo "Running timing_budget1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/timing_budget_subnode_handler.tcl" run "$(PWD)" timing_budget1
	@echo "done timing_budget1 run completed"
	@touch $@

# timing_budget1 validate subnode
$(TIMING_BUDGET1_VALIDATE_STAMP): $(TIMING_BUDGET1_RUN_STAMP)
	@echo "Running timing_budget1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/timing_budget_subnode_handler.tcl" validate "$(PWD)" timing_budget1
	@echo "done timing_budget1 validate completed"
	@touch $@

# timing_budget1 finish subnode
$(TIMING_BUDGET1_FINISH_STAMP): $(TIMING_BUDGET1_VALIDATE_STAMP)
	@echo "Running timing_budget1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/timing_budget_subnode_handler.tcl" finish "$(PWD)" timing_budget1
	@echo "done timing_budget1 finish completed"
	@touch $@

