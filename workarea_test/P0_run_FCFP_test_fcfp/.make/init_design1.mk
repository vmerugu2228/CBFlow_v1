# CBFlow FCFP init_design1 Stage Makefile
# Auto-generated for FCFP flow

# init_design1 stage with subnodes: setup, run, validate, finish

INIT_DESIGN1_SETUP_STAMP = $(STAMP_DIR)/init_design1_setup.stamp
INIT_DESIGN1_RUN_STAMP = $(STAMP_DIR)/init_design1_run.stamp
INIT_DESIGN1_VALIDATE_STAMP = $(STAMP_DIR)/init_design1_validate.stamp
INIT_DESIGN1_FINISH_STAMP = $(STAMP_DIR)/init_design1_finish.stamp

.PHONY: init_design1
init_design1: $(INIT_DESIGN1_STAMP)

$(INIT_DESIGN1_STAMP): $(INIT_DESIGN1_FINISH_STAMP)
	@echo "done init_design1 stage completed"
	@touch $@

# init_design1 setup subnode
$(INIT_DESIGN1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running init_design1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_design_subnode_handler.tcl" setup "$(PWD)" init_design1
	@echo "done init_design1 setup completed"
	@touch $@

# init_design1 run subnode
$(INIT_DESIGN1_RUN_STAMP): $(INIT_DESIGN1_SETUP_STAMP)
	@echo "Running init_design1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_design_subnode_handler.tcl" run "$(PWD)" init_design1
	@echo "done init_design1 run completed"
	@touch $@

# init_design1 validate subnode
$(INIT_DESIGN1_VALIDATE_STAMP): $(INIT_DESIGN1_RUN_STAMP)
	@echo "Running init_design1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_design_subnode_handler.tcl" validate "$(PWD)" init_design1
	@echo "done init_design1 validate completed"
	@touch $@

# init_design1 finish subnode
$(INIT_DESIGN1_FINISH_STAMP): $(INIT_DESIGN1_VALIDATE_STAMP)
	@echo "Running init_design1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/init_design_subnode_handler.tcl" finish "$(PWD)" init_design1
	@echo "done init_design1 finish completed"
	@touch $@

