# CBFlow FP place_pins1 Stage Makefile
# Auto-generated for FP flow

# place_pins1 stage with subnodes: setup, run, validate, finish

PLACE_PINS1_SETUP_STAMP = $(STAMP_DIR)/place_pins1_setup.stamp
PLACE_PINS1_RUN_STAMP = $(STAMP_DIR)/place_pins1_run.stamp
PLACE_PINS1_VALIDATE_STAMP = $(STAMP_DIR)/place_pins1_validate.stamp
PLACE_PINS1_FINISH_STAMP = $(STAMP_DIR)/place_pins1_finish.stamp

.PHONY: place_pins1
place_pins1: $(PLACE_PINS1_STAMP)

$(PLACE_PINS1_STAMP): $(PLACE_PINS1_FINISH_STAMP)
	@echo "done place_pins1 stage completed"
	@touch $@

# place_pins1 setup subnode
$(PLACE_PINS1_SETUP_STAMP): $(POWERPLAN1_STAMP)
	@echo "Running place_pins1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/place_pins_subnode_handler.tcl" setup "$(PWD)" place_pins1
	@echo "done place_pins1 setup completed"
	@touch $@

# place_pins1 run subnode
$(PLACE_PINS1_RUN_STAMP): $(PLACE_PINS1_SETUP_STAMP)
	@echo "Running place_pins1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/place_pins_subnode_handler.tcl" run "$(PWD)" place_pins1
	@echo "done place_pins1 run completed"
	@touch $@

# place_pins1 validate subnode
$(PLACE_PINS1_VALIDATE_STAMP): $(PLACE_PINS1_RUN_STAMP)
	@echo "Running place_pins1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/place_pins_subnode_handler.tcl" validate "$(PWD)" place_pins1
	@echo "done place_pins1 validate completed"
	@touch $@

# place_pins1 finish subnode
$(PLACE_PINS1_FINISH_STAMP): $(PLACE_PINS1_VALIDATE_STAMP)
	@echo "Running place_pins1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/place_pins_subnode_handler.tcl" finish "$(PWD)" place_pins1
	@echo "done place_pins1 finish completed"
	@touch $@

