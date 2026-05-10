# CBFlow PV perc1 Stage Makefile
# Auto-generated for PV flow

# perc1 stage with subnodes: setup, run, validate, finish

PERC1_SETUP_STAMP = $(STAMP_DIR)/perc1_setup.stamp
PERC1_RUN_STAMP = $(STAMP_DIR)/perc1_run.stamp
PERC1_VALIDATE_STAMP = $(STAMP_DIR)/perc1_validate.stamp
PERC1_FINISH_STAMP = $(STAMP_DIR)/perc1_finish.stamp

.PHONY: perc1
perc1: $(PERC1_STAMP)

$(PERC1_STAMP): $(PERC1_FINISH_STAMP)
	@echo "done perc1 stage completed"
	@touch $@

# perc1 setup subnode
$(PERC1_SETUP_STAMP): $(FILL1_STAMP)
	@echo "Running perc1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/perc_subnode_handler.tcl" setup "$(PWD)" perc1
	@echo "done perc1 setup completed"
	@touch $@

# perc1 run subnode
$(PERC1_RUN_STAMP): $(PERC1_SETUP_STAMP)
	@echo "Running perc1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/perc_subnode_handler.tcl" run "$(PWD)" perc1
	@echo "done perc1 run completed"
	@touch $@

# perc1 validate subnode
$(PERC1_VALIDATE_STAMP): $(PERC1_RUN_STAMP)
	@echo "Running perc1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/perc_subnode_handler.tcl" validate "$(PWD)" perc1
	@echo "done perc1 validate completed"
	@touch $@

# perc1 finish subnode
$(PERC1_FINISH_STAMP): $(PERC1_VALIDATE_STAMP)
	@echo "Running perc1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/perc_subnode_handler.tcl" finish "$(PWD)" perc1
	@echo "done perc1 finish completed"
	@touch $@

