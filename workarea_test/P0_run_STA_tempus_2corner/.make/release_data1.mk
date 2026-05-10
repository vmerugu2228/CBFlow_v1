# CBFlow STA release_data1 Stage Makefile
# Auto-generated for STA flow

# release_data1 stage with subnodes: setup, run, validate, finish

RELEASE_DATA1_SETUP_STAMP = $(STAMP_DIR)/release_data1_setup.stamp
RELEASE_DATA1_RUN_STAMP = $(STAMP_DIR)/release_data1_run.stamp
RELEASE_DATA1_VALIDATE_STAMP = $(STAMP_DIR)/release_data1_validate.stamp
RELEASE_DATA1_FINISH_STAMP = $(STAMP_DIR)/release_data1_finish.stamp

.PHONY: release_data1
release_data1: $(RELEASE_DATA1_STAMP)

$(RELEASE_DATA1_STAMP): $(RELEASE_DATA1_FINISH_STAMP)
	@echo "done release_data1 stage completed"
	@touch $@

# release_data1 setup subnode
$(RELEASE_DATA1_SETUP_STAMP): 
	@echo "Running release_data1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/release_data_subnode_handler.tcl" setup "$(PWD)" release_data1
	@echo "done release_data1 setup completed"
	@touch $@

# release_data1 run subnode
$(RELEASE_DATA1_RUN_STAMP): $(RELEASE_DATA1_SETUP_STAMP)
	@echo "Running release_data1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/release_data_subnode_handler.tcl" run "$(PWD)" release_data1
	@echo "done release_data1 run completed"
	@touch $@

# release_data1 validate subnode
$(RELEASE_DATA1_VALIDATE_STAMP): $(RELEASE_DATA1_RUN_STAMP)
	@echo "Running release_data1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/release_data_subnode_handler.tcl" validate "$(PWD)" release_data1
	@echo "done release_data1 validate completed"
	@touch $@

# release_data1 finish subnode
$(RELEASE_DATA1_FINISH_STAMP): $(RELEASE_DATA1_VALIDATE_STAMP)
	@echo "Running release_data1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/release_data_subnode_handler.tcl" finish "$(PWD)" release_data1
	@echo "done release_data1 finish completed"
	@touch $@

