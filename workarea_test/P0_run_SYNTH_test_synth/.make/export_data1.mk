# CBFlow SYNTH export_data1 Stage Makefile
# Auto-generated for SYNTH flow

# export_data1 stage with subnodes: setup, run, validate, finish

EXPORT_DATA1_SETUP_STAMP = $(STAMP_DIR)/export_data1_setup.stamp
EXPORT_DATA1_RUN_STAMP = $(STAMP_DIR)/export_data1_run.stamp
EXPORT_DATA1_VALIDATE_STAMP = $(STAMP_DIR)/export_data1_validate.stamp
EXPORT_DATA1_FINISH_STAMP = $(STAMP_DIR)/export_data1_finish.stamp

.PHONY: export_data1
export_data1: $(EXPORT_DATA1_STAMP)

$(EXPORT_DATA1_STAMP): $(EXPORT_DATA1_FINISH_STAMP)
	@echo "done export_data1 stage completed"
	@touch $@

# export_data1 setup subnode
$(EXPORT_DATA1_SETUP_STAMP): $(SYNTHESIS1_STAMP)
	@echo "Running export_data1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/export_data_subnode_handler.tcl" setup "$(PWD)" export_data1
	@echo "done export_data1 setup completed"
	@touch $@

# export_data1 run subnode
$(EXPORT_DATA1_RUN_STAMP): $(EXPORT_DATA1_SETUP_STAMP)
	@echo "Running export_data1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/export_data_subnode_handler.tcl" run "$(PWD)" export_data1
	@echo "done export_data1 run completed"
	@touch $@

# export_data1 validate subnode
$(EXPORT_DATA1_VALIDATE_STAMP): $(EXPORT_DATA1_RUN_STAMP)
	@echo "Running export_data1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/export_data_subnode_handler.tcl" validate "$(PWD)" export_data1
	@echo "done export_data1 validate completed"
	@touch $@

# export_data1 finish subnode
$(EXPORT_DATA1_FINISH_STAMP): $(EXPORT_DATA1_VALIDATE_STAMP)
	@echo "Running export_data1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/export_data_subnode_handler.tcl" finish "$(PWD)" export_data1
	@echo "done export_data1 finish completed"
	@touch $@

