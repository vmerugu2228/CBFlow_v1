# CBFlow FCFP commit_blocks1 Stage Makefile
# Auto-generated for FCFP flow

# commit_blocks1 stage with subnodes: setup, run, validate, finish

COMMIT_BLOCKS1_SETUP_STAMP = $(STAMP_DIR)/commit_blocks1_setup.stamp
COMMIT_BLOCKS1_RUN_STAMP = $(STAMP_DIR)/commit_blocks1_run.stamp
COMMIT_BLOCKS1_VALIDATE_STAMP = $(STAMP_DIR)/commit_blocks1_validate.stamp
COMMIT_BLOCKS1_FINISH_STAMP = $(STAMP_DIR)/commit_blocks1_finish.stamp

.PHONY: commit_blocks1
commit_blocks1: $(COMMIT_BLOCKS1_STAMP)

$(COMMIT_BLOCKS1_STAMP): $(COMMIT_BLOCKS1_FINISH_STAMP)
	@echo "done commit_blocks1 stage completed"
	@touch $@

# commit_blocks1 setup subnode
$(COMMIT_BLOCKS1_SETUP_STAMP): $(INIT_DESIGN1_STAMP)
	@echo "Running commit_blocks1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/commit_blocks_subnode_handler.tcl" setup "$(PWD)" commit_blocks1
	@echo "done commit_blocks1 setup completed"
	@touch $@

# commit_blocks1 run subnode
$(COMMIT_BLOCKS1_RUN_STAMP): $(COMMIT_BLOCKS1_SETUP_STAMP)
	@echo "Running commit_blocks1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/commit_blocks_subnode_handler.tcl" run "$(PWD)" commit_blocks1
	@echo "done commit_blocks1 run completed"
	@touch $@

# commit_blocks1 validate subnode
$(COMMIT_BLOCKS1_VALIDATE_STAMP): $(COMMIT_BLOCKS1_RUN_STAMP)
	@echo "Running commit_blocks1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/commit_blocks_subnode_handler.tcl" validate "$(PWD)" commit_blocks1
	@echo "done commit_blocks1 validate completed"
	@touch $@

# commit_blocks1 finish subnode
$(COMMIT_BLOCKS1_FINISH_STAMP): $(COMMIT_BLOCKS1_VALIDATE_STAMP)
	@echo "Running commit_blocks1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/commit_blocks_subnode_handler.tcl" finish "$(PWD)" commit_blocks1
	@echo "done commit_blocks1 finish completed"
	@touch $@

