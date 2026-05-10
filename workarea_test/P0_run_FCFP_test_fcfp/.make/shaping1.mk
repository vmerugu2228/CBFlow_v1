# CBFlow FCFP shaping1 Stage Makefile
# Auto-generated for FCFP flow

# shaping1 stage with subnodes: setup, run, validate, finish

SHAPING1_SETUP_STAMP = $(STAMP_DIR)/shaping1_setup.stamp
SHAPING1_RUN_STAMP = $(STAMP_DIR)/shaping1_run.stamp
SHAPING1_VALIDATE_STAMP = $(STAMP_DIR)/shaping1_validate.stamp
SHAPING1_FINISH_STAMP = $(STAMP_DIR)/shaping1_finish.stamp

.PHONY: shaping1
shaping1: $(SHAPING1_STAMP)

$(SHAPING1_STAMP): $(SHAPING1_FINISH_STAMP)
	@echo "done shaping1 stage completed"
	@touch $@

# shaping1 setup subnode
$(SHAPING1_SETUP_STAMP): $(CREATE_FLOORPLAN1_STAMP)
	@echo "Running shaping1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/shaping_subnode_handler.tcl" setup "$(PWD)" shaping1
	@echo "done shaping1 setup completed"
	@touch $@

# shaping1 run subnode
$(SHAPING1_RUN_STAMP): $(SHAPING1_SETUP_STAMP)
	@echo "Running shaping1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/shaping_subnode_handler.tcl" run "$(PWD)" shaping1
	@echo "done shaping1 run completed"
	@touch $@

# shaping1 validate subnode
$(SHAPING1_VALIDATE_STAMP): $(SHAPING1_RUN_STAMP)
	@echo "Running shaping1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/shaping_subnode_handler.tcl" validate "$(PWD)" shaping1
	@echo "done shaping1 validate completed"
	@touch $@

# shaping1 finish subnode
$(SHAPING1_FINISH_STAMP): $(SHAPING1_VALIDATE_STAMP)
	@echo "Running shaping1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/shaping_subnode_handler.tcl" finish "$(PWD)" shaping1
	@echo "done shaping1 finish completed"
	@touch $@

