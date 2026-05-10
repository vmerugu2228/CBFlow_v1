# CBFlow FCFP init_compile1 Stage Makefile
# Auto-generated for FCFP flow

# init_compile1 stage with subnodes: setup, run, validate, finish

INIT_COMPILE1_SETUP_STAMP = $(STAMP_DIR)/init_compile1_setup.stamp
INIT_COMPILE1_RUN_STAMP = $(STAMP_DIR)/init_compile1_run.stamp
INIT_COMPILE1_VALIDATE_STAMP = $(STAMP_DIR)/init_compile1_validate.stamp
INIT_COMPILE1_FINISH_STAMP = $(STAMP_DIR)/init_compile1_finish.stamp

.PHONY: init_compile1
init_compile1: $(INIT_COMPILE1_STAMP)

$(INIT_COMPILE1_STAMP): $(INIT_COMPILE1_FINISH_STAMP)
	@echo "done init_compile1 stage completed"
	@touch $@

# init_compile1 setup subnode
$(INIT_COMPILE1_SETUP_STAMP): $(COMMIT_BLOCKS1_STAMP)
	@echo "Running init_compile1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_compile_subnode_handler.tcl" setup "$(PWD)" init_compile1
	@echo "done init_compile1 setup completed"
	@touch $@

# init_compile1 run subnode
$(INIT_COMPILE1_RUN_STAMP): $(INIT_COMPILE1_SETUP_STAMP)
	@echo "Running init_compile1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_compile_subnode_handler.tcl" run "$(PWD)" init_compile1
	@echo "done init_compile1 run completed"
	@touch $@

# init_compile1 validate subnode
$(INIT_COMPILE1_VALIDATE_STAMP): $(INIT_COMPILE1_RUN_STAMP)
	@echo "Running init_compile1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_compile_subnode_handler.tcl" validate "$(PWD)" init_compile1
	@echo "done init_compile1 validate completed"
	@touch $@

# init_compile1 finish subnode
$(INIT_COMPILE1_FINISH_STAMP): $(INIT_COMPILE1_VALIDATE_STAMP)
	@echo "Running init_compile1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_compile_subnode_handler.tcl" finish "$(PWD)" init_compile1
	@echo "done init_compile1 finish completed"
	@touch $@

