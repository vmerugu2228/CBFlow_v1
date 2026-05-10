# CBFlow FCFP create_power1 Stage Makefile
# Auto-generated for FCFP flow

# create_power1 stage with subnodes: setup, run, validate, finish

CREATE_POWER1_SETUP_STAMP = $(STAMP_DIR)/create_power1_setup.stamp
CREATE_POWER1_RUN_STAMP = $(STAMP_DIR)/create_power1_run.stamp
CREATE_POWER1_VALIDATE_STAMP = $(STAMP_DIR)/create_power1_validate.stamp
CREATE_POWER1_FINISH_STAMP = $(STAMP_DIR)/create_power1_finish.stamp

.PHONY: create_power1
create_power1: $(CREATE_POWER1_STAMP)

$(CREATE_POWER1_STAMP): $(CREATE_POWER1_FINISH_STAMP)
	@echo "done create_power1 stage completed"
	@touch $@

# create_power1 setup subnode
$(CREATE_POWER1_SETUP_STAMP): $(PLACEMENT1_STAMP)
	@echo "Running create_power1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_power_subnode_handler.tcl" setup "$(PWD)" create_power1
	@echo "done create_power1 setup completed"
	@touch $@

# create_power1 run subnode
$(CREATE_POWER1_RUN_STAMP): $(CREATE_POWER1_SETUP_STAMP)
	@echo "Running create_power1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_power_subnode_handler.tcl" run "$(PWD)" create_power1
	@echo "done create_power1 run completed"
	@touch $@

# create_power1 validate subnode
$(CREATE_POWER1_VALIDATE_STAMP): $(CREATE_POWER1_RUN_STAMP)
	@echo "Running create_power1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_power_subnode_handler.tcl" validate "$(PWD)" create_power1
	@echo "done create_power1 validate completed"
	@touch $@

# create_power1 finish subnode
$(CREATE_POWER1_FINISH_STAMP): $(CREATE_POWER1_VALIDATE_STAMP)
	@echo "Running create_power1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_power_subnode_handler.tcl" finish "$(PWD)" create_power1
	@echo "done create_power1 finish completed"
	@touch $@

