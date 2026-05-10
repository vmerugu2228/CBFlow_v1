# CBFlow ECO export_db1 Stage Makefile
# Auto-generated for ECO flow

# export_db1 stage with subnodes: setup, run, validate, finish

EXPORT_DB1_SETUP_STAMP = $(STAMP_DIR)/export_db1_setup.stamp
EXPORT_DB1_RUN_STAMP = $(STAMP_DIR)/export_db1_run.stamp
EXPORT_DB1_VALIDATE_STAMP = $(STAMP_DIR)/export_db1_validate.stamp
EXPORT_DB1_FINISH_STAMP = $(STAMP_DIR)/export_db1_finish.stamp

.PHONY: export_db1
export_db1: $(EXPORT_DB1_STAMP)

$(EXPORT_DB1_STAMP): $(EXPORT_DB1_FINISH_STAMP)
	@echo "done export_db1 stage completed"
	@touch $@

# export_db1 setup subnode
$(EXPORT_DB1_SETUP_STAMP): $(ECO1_STAMP)
	@echo "Running export_db1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/export_db_subnode_handler.tcl" setup "$(PWD)" export_db1
	@echo "done export_db1 setup completed"
	@touch $@

# export_db1 run subnode
$(EXPORT_DB1_RUN_STAMP): $(EXPORT_DB1_SETUP_STAMP)
	@echo "Running export_db1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/export_db_subnode_handler.tcl" run "$(PWD)" export_db1
	@echo "done export_db1 run completed"
	@touch $@

# export_db1 validate subnode
$(EXPORT_DB1_VALIDATE_STAMP): $(EXPORT_DB1_RUN_STAMP)
	@echo "Running export_db1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/export_db_subnode_handler.tcl" validate "$(PWD)" export_db1
	@echo "done export_db1 validate completed"
	@touch $@

# export_db1 finish subnode
$(EXPORT_DB1_FINISH_STAMP): $(EXPORT_DB1_VALIDATE_STAMP)
	@echo "Running export_db1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/export_db_subnode_handler.tcl" finish "$(PWD)" export_db1
	@echo "done export_db1 finish completed"
	@touch $@

