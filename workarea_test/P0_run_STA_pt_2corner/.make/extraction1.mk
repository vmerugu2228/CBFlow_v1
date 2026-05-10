# CBFlow STA extraction1 Stage Makefile
# Auto-generated for STA flow

# extraction1 stage with subnodes: setup, run, validate, finish

EXTRACTION1_SETUP_STAMP = $(STAMP_DIR)/extraction1_setup.stamp
EXTRACTION1_RUN_STAMP = $(STAMP_DIR)/extraction1_run.stamp
EXTRACTION1_VALIDATE_STAMP = $(STAMP_DIR)/extraction1_validate.stamp
EXTRACTION1_FINISH_STAMP = $(STAMP_DIR)/extraction1_finish.stamp

.PHONY: extraction1
extraction1: $(EXTRACTION1_STAMP)

$(EXTRACTION1_STAMP): $(EXTRACTION1_FINISH_STAMP)
	@echo "done extraction1 stage completed"
	@touch $@

# extraction1 setup subnode
$(EXTRACTION1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running extraction1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/synopsys/pt/$(PT_VERSION)/extraction_subnode_handler.tcl" setup "$(PWD)" extraction1
	@echo "done extraction1 setup completed"
	@touch $@

# extraction1 run subnode
$(EXTRACTION1_RUN_STAMP): $(EXTRACTION1_SETUP_STAMP)
	@echo "Running extraction1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/synopsys/pt/$(PT_VERSION)/extraction_subnode_handler.tcl" run "$(PWD)" extraction1
	@echo "done extraction1 run completed"
	@touch $@

# extraction1 validate subnode
$(EXTRACTION1_VALIDATE_STAMP): $(EXTRACTION1_RUN_STAMP)
	@echo "Running extraction1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/synopsys/pt/$(PT_VERSION)/extraction_subnode_handler.tcl" validate "$(PWD)" extraction1
	@echo "done extraction1 validate completed"
	@touch $@

# extraction1 finish subnode
$(EXTRACTION1_FINISH_STAMP): $(EXTRACTION1_VALIDATE_STAMP)
	@echo "Running extraction1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/synopsys/pt/$(PT_VERSION)/extraction_subnode_handler.tcl" finish "$(PWD)" extraction1
	@echo "done extraction1 finish completed"
	@touch $@

