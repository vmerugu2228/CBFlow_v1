# CBFlow FP floorplan1 Stage Makefile
# Auto-generated for FP flow

# floorplan1 stage with subnodes: setup, run, validate, finish

FLOORPLAN1_SETUP_STAMP = $(STAMP_DIR)/floorplan1_setup.stamp
FLOORPLAN1_RUN_STAMP = $(STAMP_DIR)/floorplan1_run.stamp
FLOORPLAN1_VALIDATE_STAMP = $(STAMP_DIR)/floorplan1_validate.stamp
FLOORPLAN1_FINISH_STAMP = $(STAMP_DIR)/floorplan1_finish.stamp

.PHONY: floorplan1
floorplan1: $(FLOORPLAN1_STAMP)

$(FLOORPLAN1_STAMP): $(FLOORPLAN1_FINISH_STAMP)
	@echo "done floorplan1 stage completed"
	@touch $@

# floorplan1 setup subnode
$(FLOORPLAN1_SETUP_STAMP): $(IMPORT_DESIGN1_STAMP)
	@echo "Running floorplan1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/floorplan_subnode_handler.tcl" setup "$(PWD)" floorplan1
	@echo "done floorplan1 setup completed"
	@touch $@

# floorplan1 run subnode
$(FLOORPLAN1_RUN_STAMP): $(FLOORPLAN1_SETUP_STAMP)
	@echo "Running floorplan1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/floorplan_subnode_handler.tcl" run "$(PWD)" floorplan1
	@echo "done floorplan1 run completed"
	@touch $@

# floorplan1 validate subnode
$(FLOORPLAN1_VALIDATE_STAMP): $(FLOORPLAN1_RUN_STAMP)
	@echo "Running floorplan1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/floorplan_subnode_handler.tcl" validate "$(PWD)" floorplan1
	@echo "done floorplan1 validate completed"
	@touch $@

# floorplan1 finish subnode
$(FLOORPLAN1_FINISH_STAMP): $(FLOORPLAN1_VALIDATE_STAMP)
	@echo "Running floorplan1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/floorplan_subnode_handler.tcl" finish "$(PWD)" floorplan1
	@echo "done floorplan1 finish completed"
	@touch $@

