# CBFlow PV erc1 Stage Makefile
# Auto-generated for PV flow

# erc1 stage with subnodes: setup, run, validate, finish

ERC1_SETUP_STAMP = $(STAMP_DIR)/erc1_setup.stamp
ERC1_RUN_STAMP = $(STAMP_DIR)/erc1_run.stamp
ERC1_VALIDATE_STAMP = $(STAMP_DIR)/erc1_validate.stamp
ERC1_FINISH_STAMP = $(STAMP_DIR)/erc1_finish.stamp

.PHONY: erc1
erc1: $(ERC1_STAMP)

$(ERC1_STAMP): $(ERC1_FINISH_STAMP)
	@echo "done erc1 stage completed"
	@touch $@

# erc1 setup subnode
$(ERC1_SETUP_STAMP): $(FILL1_STAMP)
	@echo "Running erc1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/erc_subnode_handler.tcl" setup "$(PWD)" erc1
	@echo "done erc1 setup completed"
	@touch $@

# erc1 run subnode
$(ERC1_RUN_STAMP): $(ERC1_SETUP_STAMP)
	@echo "Running erc1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/erc_subnode_handler.tcl" run "$(PWD)" erc1
	@echo "done erc1 run completed"
	@touch $@

# erc1 validate subnode
$(ERC1_VALIDATE_STAMP): $(ERC1_RUN_STAMP)
	@echo "Running erc1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/erc_subnode_handler.tcl" validate "$(PWD)" erc1
	@echo "done erc1 validate completed"
	@touch $@

# erc1 finish subnode
$(ERC1_FINISH_STAMP): $(ERC1_VALIDATE_STAMP)
	@echo "Running erc1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/erc_subnode_handler.tcl" finish "$(PWD)" erc1
	@echo "done erc1 finish completed"
	@touch $@

