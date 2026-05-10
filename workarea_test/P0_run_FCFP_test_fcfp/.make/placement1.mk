# CBFlow FCFP placement1 Stage Makefile
# Auto-generated for FCFP flow

# placement1 stage with subnodes: setup, run, validate, finish

PLACEMENT1_SETUP_STAMP = $(STAMP_DIR)/placement1_setup.stamp
PLACEMENT1_RUN_STAMP = $(STAMP_DIR)/placement1_run.stamp
PLACEMENT1_VALIDATE_STAMP = $(STAMP_DIR)/placement1_validate.stamp
PLACEMENT1_FINISH_STAMP = $(STAMP_DIR)/placement1_finish.stamp

.PHONY: placement1
placement1: $(PLACEMENT1_STAMP)

$(PLACEMENT1_STAMP): $(PLACEMENT1_FINISH_STAMP)
	@echo "done placement1 stage completed"
	@touch $@

# placement1 setup subnode
$(PLACEMENT1_SETUP_STAMP): $(SHAPING1_STAMP)
	@echo "Running placement1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/placement_subnode_handler.tcl" setup "$(PWD)" placement1
	@echo "done placement1 setup completed"
	@touch $@

# placement1 run subnode
$(PLACEMENT1_RUN_STAMP): $(PLACEMENT1_SETUP_STAMP)
	@echo "Running placement1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/placement_subnode_handler.tcl" run "$(PWD)" placement1
	@echo "done placement1 run completed"
	@touch $@

# placement1 validate subnode
$(PLACEMENT1_VALIDATE_STAMP): $(PLACEMENT1_RUN_STAMP)
	@echo "Running placement1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/placement_subnode_handler.tcl" validate "$(PWD)" placement1
	@echo "done placement1 validate completed"
	@touch $@

# placement1 finish subnode
$(PLACEMENT1_FINISH_STAMP): $(PLACEMENT1_VALIDATE_STAMP)
	@echo "Running placement1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/placement_subnode_handler.tcl" finish "$(PWD)" placement1
	@echo "done placement1 finish completed"
	@touch $@

