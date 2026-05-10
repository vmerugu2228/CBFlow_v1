# CBFlow SYNTH_PNR cts1 Stage Makefile
# Auto-generated for SYNTH_PNR flow

# cts1 stage with subnodes: setup, run, validate, finish

CTS1_SETUP_STAMP = $(STAMP_DIR)/cts1_setup.stamp
CTS1_RUN_STAMP = $(STAMP_DIR)/cts1_run.stamp
CTS1_VALIDATE_STAMP = $(STAMP_DIR)/cts1_validate.stamp
CTS1_FINISH_STAMP = $(STAMP_DIR)/cts1_finish.stamp

.PHONY: cts1
cts1: $(CTS1_STAMP)

$(CTS1_STAMP): $(CTS1_FINISH_STAMP)
	@echo "done cts1 stage completed"
	@touch $@

# cts1 setup subnode
$(CTS1_SETUP_STAMP): $(PLACE1_STAMP)
	@echo "Running cts1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/cts_subnode_handler.tcl" setup "$(PWD)" cts1
	@echo "done cts1 setup completed"
	@touch $@

# cts1 run subnode
$(CTS1_RUN_STAMP): $(CTS1_SETUP_STAMP)
	@echo "Running cts1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/cts_subnode_handler.tcl" run "$(PWD)" cts1
	@echo "done cts1 run completed"
	@touch $@

# cts1 validate subnode
$(CTS1_VALIDATE_STAMP): $(CTS1_RUN_STAMP)
	@echo "Running cts1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/cts_subnode_handler.tcl" validate "$(PWD)" cts1
	@echo "done cts1 validate completed"
	@touch $@

# cts1 finish subnode
$(CTS1_FINISH_STAMP): $(CTS1_VALIDATE_STAMP)
	@echo "Running cts1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/cts_subnode_handler.tcl" finish "$(PWD)" cts1
	@echo "done cts1 finish completed"
	@touch $@

