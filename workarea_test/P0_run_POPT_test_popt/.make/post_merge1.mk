# CBFlow POPT post_merge1 Stage Makefile
# Auto-generated for POPT flow

# post_merge1 stage with subnodes: setup, run, validate, finish

POST_MERGE1_SETUP_STAMP = $(STAMP_DIR)/post_merge1_setup.stamp
POST_MERGE1_RUN_STAMP = $(STAMP_DIR)/post_merge1_run.stamp
POST_MERGE1_VALIDATE_STAMP = $(STAMP_DIR)/post_merge1_validate.stamp
POST_MERGE1_FINISH_STAMP = $(STAMP_DIR)/post_merge1_finish.stamp

.PHONY: post_merge1
post_merge1: $(POST_MERGE1_STAMP)

$(POST_MERGE1_STAMP): $(POST_MERGE1_FINISH_STAMP)
	@echo "done post_merge1 stage completed"
	@touch $@

# post_merge1 setup subnode
$(POST_MERGE1_SETUP_STAMP): $(POWER_OPT1_STAMP)
	@echo "Running post_merge1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/post_merge_subnode_handler.tcl" setup "$(PWD)" post_merge1
	@echo "done post_merge1 setup completed"
	@touch $@

# post_merge1 run subnode
$(POST_MERGE1_RUN_STAMP): $(POST_MERGE1_SETUP_STAMP)
	@echo "Running post_merge1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/post_merge_subnode_handler.tcl" run "$(PWD)" post_merge1
	@echo "done post_merge1 run completed"
	@touch $@

# post_merge1 validate subnode
$(POST_MERGE1_VALIDATE_STAMP): $(POST_MERGE1_RUN_STAMP)
	@echo "Running post_merge1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/post_merge_subnode_handler.tcl" validate "$(PWD)" post_merge1
	@echo "done post_merge1 validate completed"
	@touch $@

# post_merge1 finish subnode
$(POST_MERGE1_FINISH_STAMP): $(POST_MERGE1_VALIDATE_STAMP)
	@echo "Running post_merge1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/POPT/synopsys/pt/$(PT_VERSION)/post_merge_subnode_handler.tcl" finish "$(PWD)" post_merge1
	@echo "done post_merge1 finish completed"
	@touch $@

