# CBFlow PNR pro1 Stage Makefile
# Auto-generated for PNR flow

# pro1 stage with subnodes: setup, run, validate, finish

PRO1_SETUP_STAMP = $(STAMP_DIR)/pro1_setup.stamp
PRO1_RUN_STAMP = $(STAMP_DIR)/pro1_run.stamp
PRO1_VALIDATE_STAMP = $(STAMP_DIR)/pro1_validate.stamp
PRO1_FINISH_STAMP = $(STAMP_DIR)/pro1_finish.stamp

.PHONY: pro1
pro1: $(PRO1_STAMP)

$(PRO1_STAMP): $(PRO1_FINISH_STAMP)
	@echo "done pro1 stage completed"
	@touch $@

# pro1 setup subnode
$(PRO1_SETUP_STAMP): $(ROUTE1_STAMP)
	@echo "Running pro1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/pro_subnode_handler.tcl" setup "$(PWD)" pro1
	@echo "done pro1 setup completed"
	@touch $@

# pro1 run subnode
$(PRO1_RUN_STAMP): $(PRO1_SETUP_STAMP)
	@echo "Running pro1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/pro_subnode_handler.tcl" run "$(PWD)" pro1
	@echo "done pro1 run completed"
	@touch $@

# pro1 validate subnode
$(PRO1_VALIDATE_STAMP): $(PRO1_RUN_STAMP)
	@echo "Running pro1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/pro_subnode_handler.tcl" validate "$(PWD)" pro1
	@echo "done pro1 validate completed"
	@touch $@

# pro1 finish subnode
$(PRO1_FINISH_STAMP): $(PRO1_VALIDATE_STAMP)
	@echo "Running pro1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/PNR/synopsys/fc/$(FC_VERSION)/pro_subnode_handler.tcl" finish "$(PWD)" pro1
	@echo "done pro1 finish completed"
	@touch $@

