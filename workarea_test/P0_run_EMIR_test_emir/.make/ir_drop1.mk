# CBFlow EMIR ir_drop1 Stage Makefile
# Auto-generated for EMIR flow

# ir_drop1 stage with subnodes: setup, run, validate, finish

IR_DROP1_SETUP_STAMP = $(STAMP_DIR)/ir_drop1_setup.stamp
IR_DROP1_RUN_STAMP = $(STAMP_DIR)/ir_drop1_run.stamp
IR_DROP1_VALIDATE_STAMP = $(STAMP_DIR)/ir_drop1_validate.stamp
IR_DROP1_FINISH_STAMP = $(STAMP_DIR)/ir_drop1_finish.stamp

.PHONY: ir_drop1
ir_drop1: $(IR_DROP1_STAMP)

$(IR_DROP1_STAMP): $(IR_DROP1_FINISH_STAMP)
	@echo "done ir_drop1 stage completed"
	@touch $@

# ir_drop1 setup subnode
$(IR_DROP1_SETUP_STAMP): $(POWER_ANALYSIS1_STAMP)
	@echo "Running ir_drop1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/ir_drop_subnode_handler.tcl" setup "$(PWD)" ir_drop1
	@echo "done ir_drop1 setup completed"
	@touch $@

# ir_drop1 run subnode
$(IR_DROP1_RUN_STAMP): $(IR_DROP1_SETUP_STAMP)
	@echo "Running ir_drop1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/ir_drop_subnode_handler.tcl" run "$(PWD)" ir_drop1
	@echo "done ir_drop1 run completed"
	@touch $@

# ir_drop1 validate subnode
$(IR_DROP1_VALIDATE_STAMP): $(IR_DROP1_RUN_STAMP)
	@echo "Running ir_drop1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/ir_drop_subnode_handler.tcl" validate "$(PWD)" ir_drop1
	@echo "done ir_drop1 validate completed"
	@touch $@

# ir_drop1 finish subnode
$(IR_DROP1_FINISH_STAMP): $(IR_DROP1_VALIDATE_STAMP)
	@echo "Running ir_drop1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/EMIR/synopsys/redhawk/$(REDHAWK_VERSION)/ir_drop_subnode_handler.tcl" finish "$(PWD)" ir_drop1
	@echo "done ir_drop1 finish completed"
	@touch $@

