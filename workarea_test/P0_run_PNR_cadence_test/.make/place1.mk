# CBFlow PNR place1 Stage Makefile
# Auto-generated for PNR flow

# place1 stage with subnodes: setup, run, validate, finish

PLACE1_SETUP_STAMP = $(STAMP_DIR)/place1_setup.stamp
PLACE1_RUN_STAMP = $(STAMP_DIR)/place1_run.stamp
PLACE1_VALIDATE_STAMP = $(STAMP_DIR)/place1_validate.stamp
PLACE1_FINISH_STAMP = $(STAMP_DIR)/place1_finish.stamp

.PHONY: place1
place1: $(PLACE1_STAMP)

$(PLACE1_STAMP): $(PLACE1_FINISH_STAMP)
	@echo "done place1 stage completed"
	@touch $@

# place1 setup subnode
$(PLACE1_SETUP_STAMP): $(INIT_DESIGN1_STAMP)
	@echo "Running place1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/place_subnode_handler.tcl" setup "$(PWD)" place1
	@echo "done place1 setup completed"
	@touch $@

# place1 run subnode
$(PLACE1_RUN_STAMP): $(PLACE1_SETUP_STAMP)
	@echo "Running place1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/place_subnode_handler.tcl" run "$(PWD)" place1
	@echo "done place1 run completed"
	@touch $@

# place1 validate subnode
$(PLACE1_VALIDATE_STAMP): $(PLACE1_RUN_STAMP)
	@echo "Running place1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/place_subnode_handler.tcl" validate "$(PWD)" place1
	@echo "done place1 validate completed"
	@touch $@

# place1 finish subnode
$(PLACE1_FINISH_STAMP): $(PLACE1_VALIDATE_STAMP)
	@echo "Running place1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/cadence/innovus/$(INNOVUS_VERSION)/place_subnode_handler.tcl" finish "$(PWD)" place1
	@echo "done place1 finish completed"
	@touch $@

