# CBFlow SYNTH_PNR route1 Stage Makefile
# Auto-generated for SYNTH_PNR flow

# route1 stage with subnodes: setup, run, validate, finish

ROUTE1_SETUP_STAMP = $(STAMP_DIR)/route1_setup.stamp
ROUTE1_RUN_STAMP = $(STAMP_DIR)/route1_run.stamp
ROUTE1_VALIDATE_STAMP = $(STAMP_DIR)/route1_validate.stamp
ROUTE1_FINISH_STAMP = $(STAMP_DIR)/route1_finish.stamp

.PHONY: route1
route1: $(ROUTE1_STAMP)

$(ROUTE1_STAMP): $(ROUTE1_FINISH_STAMP)
	@echo "done route1 stage completed"
	@touch $@

# route1 setup subnode
$(ROUTE1_SETUP_STAMP): $(CTS_OPT1_STAMP)
	@echo "Running route1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/route_subnode_handler.tcl" setup "$(PWD)" route1
	@echo "done route1 setup completed"
	@touch $@

# route1 run subnode
$(ROUTE1_RUN_STAMP): $(ROUTE1_SETUP_STAMP)
	@echo "Running route1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/route_subnode_handler.tcl" run "$(PWD)" route1
	@echo "done route1 run completed"
	@touch $@

# route1 validate subnode
$(ROUTE1_VALIDATE_STAMP): $(ROUTE1_RUN_STAMP)
	@echo "Running route1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/route_subnode_handler.tcl" validate "$(PWD)" route1
	@echo "done route1 validate completed"
	@touch $@

# route1 finish subnode
$(ROUTE1_FINISH_STAMP): $(ROUTE1_VALIDATE_STAMP)
	@echo "Running route1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/route_subnode_handler.tcl" finish "$(PWD)" route1
	@echo "done route1 finish completed"
	@touch $@

