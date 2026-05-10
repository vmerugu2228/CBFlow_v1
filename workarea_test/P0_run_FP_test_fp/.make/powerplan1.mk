# CBFlow FP powerplan1 Stage Makefile
# Auto-generated for FP flow

# powerplan1 stage with subnodes: setup, run, validate, finish

POWERPLAN1_SETUP_STAMP = $(STAMP_DIR)/powerplan1_setup.stamp
POWERPLAN1_RUN_STAMP = $(STAMP_DIR)/powerplan1_run.stamp
POWERPLAN1_VALIDATE_STAMP = $(STAMP_DIR)/powerplan1_validate.stamp
POWERPLAN1_FINISH_STAMP = $(STAMP_DIR)/powerplan1_finish.stamp

.PHONY: powerplan1
powerplan1: $(POWERPLAN1_STAMP)

$(POWERPLAN1_STAMP): $(POWERPLAN1_FINISH_STAMP)
	@echo "done powerplan1 stage completed"
	@touch $@

# powerplan1 setup subnode
$(POWERPLAN1_SETUP_STAMP): $(FLOORPLAN1_STAMP)
	@echo "Running powerplan1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/powerplan_subnode_handler.tcl" setup "$(PWD)" powerplan1
	@echo "done powerplan1 setup completed"
	@touch $@

# powerplan1 run subnode
$(POWERPLAN1_RUN_STAMP): $(POWERPLAN1_SETUP_STAMP)
	@echo "Running powerplan1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/powerplan_subnode_handler.tcl" run "$(PWD)" powerplan1
	@echo "done powerplan1 run completed"
	@touch $@

# powerplan1 validate subnode
$(POWERPLAN1_VALIDATE_STAMP): $(POWERPLAN1_RUN_STAMP)
	@echo "Running powerplan1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/powerplan_subnode_handler.tcl" validate "$(PWD)" powerplan1
	@echo "done powerplan1 validate completed"
	@touch $@

# powerplan1 finish subnode
$(POWERPLAN1_FINISH_STAMP): $(POWERPLAN1_VALIDATE_STAMP)
	@echo "Running powerplan1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/powerplan_subnode_handler.tcl" finish "$(PWD)" powerplan1
	@echo "done powerplan1 finish completed"
	@touch $@

