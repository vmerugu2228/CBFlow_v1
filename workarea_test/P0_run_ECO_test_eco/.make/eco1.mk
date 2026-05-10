# CBFlow ECO eco1 Stage Makefile
# Auto-generated for ECO flow

# eco1 stage with subnodes: setup, run, validate, finish

ECO1_SETUP_STAMP = $(STAMP_DIR)/eco1_setup.stamp
ECO1_RUN_STAMP = $(STAMP_DIR)/eco1_run.stamp
ECO1_VALIDATE_STAMP = $(STAMP_DIR)/eco1_validate.stamp
ECO1_FINISH_STAMP = $(STAMP_DIR)/eco1_finish.stamp

.PHONY: eco1
eco1: $(ECO1_STAMP)

$(ECO1_STAMP): $(ECO1_FINISH_STAMP)
	@echo "done eco1 stage completed"
	@touch $@

# eco1 setup subnode
$(ECO1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running eco1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/eco_subnode_handler.tcl" setup "$(PWD)" eco1
	@echo "done eco1 setup completed"
	@touch $@

# eco1 run subnode
$(ECO1_RUN_STAMP): $(ECO1_SETUP_STAMP)
	@echo "Running eco1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/eco_subnode_handler.tcl" run "$(PWD)" eco1
	@echo "done eco1 run completed"
	@touch $@

# eco1 validate subnode
$(ECO1_VALIDATE_STAMP): $(ECO1_RUN_STAMP)
	@echo "Running eco1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/eco_subnode_handler.tcl" validate "$(PWD)" eco1
	@echo "done eco1 validate completed"
	@touch $@

# eco1 finish subnode
$(ECO1_FINISH_STAMP): $(ECO1_VALIDATE_STAMP)
	@echo "Running eco1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/eco_subnode_handler.tcl" finish "$(PWD)" eco1
	@echo "done eco1 finish completed"
	@touch $@

