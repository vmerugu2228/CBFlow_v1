# CBFlow FCFP top_compile1 Stage Makefile
# Auto-generated for FCFP flow

# top_compile1 stage with subnodes: setup, run, validate, finish

TOP_COMPILE1_SETUP_STAMP = $(STAMP_DIR)/top_compile1_setup.stamp
TOP_COMPILE1_RUN_STAMP = $(STAMP_DIR)/top_compile1_run.stamp
TOP_COMPILE1_VALIDATE_STAMP = $(STAMP_DIR)/top_compile1_validate.stamp
TOP_COMPILE1_FINISH_STAMP = $(STAMP_DIR)/top_compile1_finish.stamp

.PHONY: top_compile1
top_compile1: $(TOP_COMPILE1_STAMP)

$(TOP_COMPILE1_STAMP): $(TOP_COMPILE1_FINISH_STAMP)
	@echo "done top_compile1 stage completed"
	@touch $@

# top_compile1 setup subnode
$(TOP_COMPILE1_SETUP_STAMP): $(PLACE_PINS1_STAMP)
	@echo "Running top_compile1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/top_compile_subnode_handler.tcl" setup "$(PWD)" top_compile1
	@echo "done top_compile1 setup completed"
	@touch $@

# top_compile1 run subnode
$(TOP_COMPILE1_RUN_STAMP): $(TOP_COMPILE1_SETUP_STAMP)
	@echo "Running top_compile1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/top_compile_subnode_handler.tcl" run "$(PWD)" top_compile1
	@echo "done top_compile1 run completed"
	@touch $@

# top_compile1 validate subnode
$(TOP_COMPILE1_VALIDATE_STAMP): $(TOP_COMPILE1_RUN_STAMP)
	@echo "Running top_compile1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/top_compile_subnode_handler.tcl" validate "$(PWD)" top_compile1
	@echo "done top_compile1 validate completed"
	@touch $@

# top_compile1 finish subnode
$(TOP_COMPILE1_FINISH_STAMP): $(TOP_COMPILE1_VALIDATE_STAMP)
	@echo "Running top_compile1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/top_compile_subnode_handler.tcl" finish "$(PWD)" top_compile1
	@echo "done top_compile1 finish completed"
	@touch $@

