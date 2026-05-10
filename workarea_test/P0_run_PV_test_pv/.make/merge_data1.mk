# CBFlow PV merge_data1 Stage Makefile
# Auto-generated for PV flow

# merge_data1 stage with subnodes: setup, run, validate, finish

MERGE_DATA1_SETUP_STAMP = $(STAMP_DIR)/merge_data1_setup.stamp
MERGE_DATA1_RUN_STAMP = $(STAMP_DIR)/merge_data1_run.stamp
MERGE_DATA1_VALIDATE_STAMP = $(STAMP_DIR)/merge_data1_validate.stamp
MERGE_DATA1_FINISH_STAMP = $(STAMP_DIR)/merge_data1_finish.stamp

.PHONY: merge_data1
merge_data1: $(MERGE_DATA1_STAMP)

$(MERGE_DATA1_STAMP): $(MERGE_DATA1_FINISH_STAMP)
	@echo "done merge_data1 stage completed"
	@touch $@

# merge_data1 setup subnode
$(MERGE_DATA1_SETUP_STAMP): $(DRC1_STAMP) $(LVS1_STAMP) $(PERC1_STAMP) $(ERC1_STAMP) $(XOR1_STAMP)
	@echo "Running merge_data1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/merge_data_subnode_handler.tcl" setup "$(PWD)" merge_data1
	@echo "done merge_data1 setup completed"
	@touch $@

# merge_data1 run subnode
$(MERGE_DATA1_RUN_STAMP): $(MERGE_DATA1_SETUP_STAMP)
	@echo "Running merge_data1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/merge_data_subnode_handler.tcl" run "$(PWD)" merge_data1
	@echo "done merge_data1 run completed"
	@touch $@

# merge_data1 validate subnode
$(MERGE_DATA1_VALIDATE_STAMP): $(MERGE_DATA1_RUN_STAMP)
	@echo "Running merge_data1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/merge_data_subnode_handler.tcl" validate "$(PWD)" merge_data1
	@echo "done merge_data1 validate completed"
	@touch $@

# merge_data1 finish subnode
$(MERGE_DATA1_FINISH_STAMP): $(MERGE_DATA1_VALIDATE_STAMP)
	@echo "Running merge_data1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/merge_data_subnode_handler.tcl" finish "$(PWD)" merge_data1
	@echo "done merge_data1 finish completed"
	@touch $@

