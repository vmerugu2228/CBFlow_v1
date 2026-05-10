# CBFlow PNR signoff1 Stage Makefile
# Auto-generated for PNR flow

# signoff1 stage with subnodes: setup, run, validate, finish

SIGNOFF1_SETUP_STAMP = $(STAMP_DIR)/signoff1_setup.stamp
SIGNOFF1_RUN_STAMP = $(STAMP_DIR)/signoff1_run.stamp
SIGNOFF1_VALIDATE_STAMP = $(STAMP_DIR)/signoff1_validate.stamp
SIGNOFF1_FINISH_STAMP = $(STAMP_DIR)/signoff1_finish.stamp

.PHONY: signoff1
signoff1: $(SIGNOFF1_STAMP)

$(SIGNOFF1_STAMP): $(SIGNOFF1_FINISH_STAMP)
	@echo "done signoff1 stage completed"
	@touch $@

# signoff1 setup subnode
$(SIGNOFF1_SETUP_STAMP): $(PRO1_STAMP)
	@echo "Running signoff1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/signoff_subnode_handler.tcl" setup "$(PWD)" signoff1
	@echo "done signoff1 setup completed"
	@touch $@

# signoff1 run subnode
$(SIGNOFF1_RUN_STAMP): $(SIGNOFF1_SETUP_STAMP)
	@echo "Running signoff1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/signoff_subnode_handler.tcl" run "$(PWD)" signoff1
	@echo "done signoff1 run completed"
	@touch $@

# signoff1 validate subnode
$(SIGNOFF1_VALIDATE_STAMP): $(SIGNOFF1_RUN_STAMP)
	@echo "Running signoff1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/signoff_subnode_handler.tcl" validate "$(PWD)" signoff1
	@echo "done signoff1 validate completed"
	@touch $@

# signoff1 finish subnode
$(SIGNOFF1_FINISH_STAMP): $(SIGNOFF1_VALIDATE_STAMP)
	@echo "Running signoff1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/signoff_subnode_handler.tcl" finish "$(PWD)" signoff1
	@echo "done signoff1 finish completed"
	@touch $@

