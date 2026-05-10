# CBFlow POPT merge_timing1 Stage Makefile
# Auto-generated for POPT flow

# merge_timing1 stage with subnodes: setup, run, validate, finish

MERGE_TIMING1_SETUP_STAMP = $(STAMP_DIR)/merge_timing1_setup.stamp
MERGE_TIMING1_RUN_STAMP = $(STAMP_DIR)/merge_timing1_run.stamp
MERGE_TIMING1_VALIDATE_STAMP = $(STAMP_DIR)/merge_timing1_validate.stamp
MERGE_TIMING1_FINISH_STAMP = $(STAMP_DIR)/merge_timing1_finish.stamp

.PHONY: merge_timing1
merge_timing1: $(MERGE_TIMING1_STAMP)

$(MERGE_TIMING1_STAMP): $(MERGE_TIMING1_FINISH_STAMP)
	@echo "done merge_timing1 stage completed"
	@touch $@

# merge_timing1 setup subnode
$(MERGE_TIMING1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running merge_timing1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/merge_timing_subnode_handler.tcl" setup "$(PWD)" merge_timing1
	@echo "done merge_timing1 setup completed"
	@touch $@

# merge_timing1 run subnode
$(MERGE_TIMING1_RUN_STAMP): $(MERGE_TIMING1_SETUP_STAMP)
	@echo "Running merge_timing1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/merge_timing_subnode_handler.tcl" run "$(PWD)" merge_timing1
	@echo "done merge_timing1 run completed"
	@touch $@

# merge_timing1 validate subnode
$(MERGE_TIMING1_VALIDATE_STAMP): $(MERGE_TIMING1_RUN_STAMP)
	@echo "Running merge_timing1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/merge_timing_subnode_handler.tcl" validate "$(PWD)" merge_timing1
	@echo "done merge_timing1 validate completed"
	@touch $@

# merge_timing1 finish subnode
$(MERGE_TIMING1_FINISH_STAMP): $(MERGE_TIMING1_VALIDATE_STAMP)
	@echo "Running merge_timing1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/merge_timing_subnode_handler.tcl" finish "$(PWD)" merge_timing1
	@echo "done merge_timing1 finish completed"
	@touch $@

