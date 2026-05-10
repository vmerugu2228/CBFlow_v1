# CBFlow PNR cts_opt1 Stage Makefile
# Auto-generated for PNR flow

# cts_opt1 stage with subnodes: setup, run, validate, finish

CTS_OPT1_SETUP_STAMP = $(STAMP_DIR)/cts_opt1_setup.stamp
CTS_OPT1_RUN_STAMP = $(STAMP_DIR)/cts_opt1_run.stamp
CTS_OPT1_VALIDATE_STAMP = $(STAMP_DIR)/cts_opt1_validate.stamp
CTS_OPT1_FINISH_STAMP = $(STAMP_DIR)/cts_opt1_finish.stamp

.PHONY: cts_opt1
cts_opt1: $(CTS_OPT1_STAMP)

$(CTS_OPT1_STAMP): $(CTS_OPT1_FINISH_STAMP)
	@echo "done cts_opt1 stage completed"
	@touch $@

# cts_opt1 setup subnode
$(CTS_OPT1_SETUP_STAMP): $(CTS1_STAMP)
	@echo "Running cts_opt1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/cts_opt_subnode_handler.tcl" setup "$(PWD)" cts_opt1
	@echo "done cts_opt1 setup completed"
	@touch $@

# cts_opt1 run subnode
$(CTS_OPT1_RUN_STAMP): $(CTS_OPT1_SETUP_STAMP)
	@echo "Running cts_opt1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/cts_opt_subnode_handler.tcl" run "$(PWD)" cts_opt1
	@echo "done cts_opt1 run completed"
	@touch $@

# cts_opt1 validate subnode
$(CTS_OPT1_VALIDATE_STAMP): $(CTS_OPT1_RUN_STAMP)
	@echo "Running cts_opt1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/cts_opt_subnode_handler.tcl" validate "$(PWD)" cts_opt1
	@echo "done cts_opt1 validate completed"
	@touch $@

# cts_opt1 finish subnode
$(CTS_OPT1_FINISH_STAMP): $(CTS_OPT1_VALIDATE_STAMP)
	@echo "Running cts_opt1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/cts_opt_subnode_handler.tcl" finish "$(PWD)" cts_opt1
	@echo "done cts_opt1 finish completed"
	@touch $@

