# CBFlow LEC analyze1 Stage Makefile
# Auto-generated for LEC flow

# analyze1 stage with subnodes: setup, run, validate, finish

ANALYZE1_SETUP_STAMP = $(STAMP_DIR)/analyze1_setup.stamp
ANALYZE1_RUN_STAMP = $(STAMP_DIR)/analyze1_run.stamp
ANALYZE1_VALIDATE_STAMP = $(STAMP_DIR)/analyze1_validate.stamp
ANALYZE1_FINISH_STAMP = $(STAMP_DIR)/analyze1_finish.stamp

.PHONY: analyze1
analyze1: $(ANALYZE1_STAMP)

$(ANALYZE1_STAMP): $(ANALYZE1_FINISH_STAMP)
	@echo "done analyze1 stage completed"
	@touch $@

# analyze1 setup subnode
$(ANALYZE1_SETUP_STAMP): $(COMPARE1_STAMP)
	@echo "Running analyze1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/analyze_subnode_handler.tcl" setup "$(PWD)" analyze1
	@echo "done analyze1 setup completed"
	@touch $@

# analyze1 run subnode
$(ANALYZE1_RUN_STAMP): $(ANALYZE1_SETUP_STAMP)
	@echo "Running analyze1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/analyze_subnode_handler.tcl" run "$(PWD)" analyze1
	@echo "done analyze1 run completed"
	@touch $@

# analyze1 validate subnode
$(ANALYZE1_VALIDATE_STAMP): $(ANALYZE1_RUN_STAMP)
	@echo "Running analyze1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/analyze_subnode_handler.tcl" validate "$(PWD)" analyze1
	@echo "done analyze1 validate completed"
	@touch $@

# analyze1 finish subnode
$(ANALYZE1_FINISH_STAMP): $(ANALYZE1_VALIDATE_STAMP)
	@echo "Running analyze1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/LEC/synopsys/formality/$(FORMALITY_VERSION)/analyze_subnode_handler.tcl" finish "$(PWD)" analyze1
	@echo "done analyze1 finish completed"
	@touch $@

