# CBFlow PV xor1 Stage Makefile
# Auto-generated for PV flow

# xor1 stage with subnodes: setup, run, validate, finish

XOR1_SETUP_STAMP = $(STAMP_DIR)/xor1_setup.stamp
XOR1_RUN_STAMP = $(STAMP_DIR)/xor1_run.stamp
XOR1_VALIDATE_STAMP = $(STAMP_DIR)/xor1_validate.stamp
XOR1_FINISH_STAMP = $(STAMP_DIR)/xor1_finish.stamp

.PHONY: xor1
xor1: $(XOR1_STAMP)

$(XOR1_STAMP): $(XOR1_FINISH_STAMP)
	@echo "done xor1 stage completed"
	@touch $@

# xor1 setup subnode
$(XOR1_SETUP_STAMP): $(FILL1_STAMP)
	@echo "Running xor1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/xor_subnode_handler.tcl" setup "$(PWD)" xor1
	@echo "done xor1 setup completed"
	@touch $@

# xor1 run subnode
$(XOR1_RUN_STAMP): $(XOR1_SETUP_STAMP)
	@echo "Running xor1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/xor_subnode_handler.tcl" run "$(PWD)" xor1
	@echo "done xor1 run completed"
	@touch $@

# xor1 validate subnode
$(XOR1_VALIDATE_STAMP): $(XOR1_RUN_STAMP)
	@echo "Running xor1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/xor_subnode_handler.tcl" validate "$(PWD)" xor1
	@echo "done xor1 validate completed"
	@touch $@

# xor1 finish subnode
$(XOR1_FINISH_STAMP): $(XOR1_VALIDATE_STAMP)
	@echo "Running xor1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PV/synopsys/icv/$(ICV_VERSION)/xor_subnode_handler.tcl" finish "$(PWD)" xor1
	@echo "done xor1 finish completed"
	@touch $@

