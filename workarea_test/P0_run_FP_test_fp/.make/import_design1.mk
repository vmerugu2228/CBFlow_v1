# CBFlow FP import_design1 Stage Makefile
# Auto-generated for FP flow

# import_design1 stage with subnodes: setup, run, validate, finish

IMPORT_DESIGN1_SETUP_STAMP = $(STAMP_DIR)/import_design1_setup.stamp
IMPORT_DESIGN1_RUN_STAMP = $(STAMP_DIR)/import_design1_run.stamp
IMPORT_DESIGN1_VALIDATE_STAMP = $(STAMP_DIR)/import_design1_validate.stamp
IMPORT_DESIGN1_FINISH_STAMP = $(STAMP_DIR)/import_design1_finish.stamp

.PHONY: import_design1
import_design1: $(IMPORT_DESIGN1_STAMP)

$(IMPORT_DESIGN1_STAMP): $(IMPORT_DESIGN1_FINISH_STAMP)
	@echo "done import_design1 stage completed"
	@touch $@

# import_design1 setup subnode
$(IMPORT_DESIGN1_SETUP_STAMP): $(INIT_DESIGN1_STAMP)
	@echo "Running import_design1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/import_design_subnode_handler.tcl" setup "$(PWD)" import_design1
	@echo "done import_design1 setup completed"
	@touch $@

# import_design1 run subnode
$(IMPORT_DESIGN1_RUN_STAMP): $(IMPORT_DESIGN1_SETUP_STAMP)
	@echo "Running import_design1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/import_design_subnode_handler.tcl" run "$(PWD)" import_design1
	@echo "done import_design1 run completed"
	@touch $@

# import_design1 validate subnode
$(IMPORT_DESIGN1_VALIDATE_STAMP): $(IMPORT_DESIGN1_RUN_STAMP)
	@echo "Running import_design1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/import_design_subnode_handler.tcl" validate "$(PWD)" import_design1
	@echo "done import_design1 validate completed"
	@touch $@

# import_design1 finish subnode
$(IMPORT_DESIGN1_FINISH_STAMP): $(IMPORT_DESIGN1_VALIDATE_STAMP)
	@echo "Running import_design1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FP/synopsys/fc/$(FC_VERSION)/import_design_subnode_handler.tcl" finish "$(PWD)" import_design1
	@echo "done import_design1 finish completed"
	@touch $@

