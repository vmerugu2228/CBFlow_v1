# CBFlow SYNTH synthesis1 Stage Makefile
# Auto-generated for SYNTH flow

# synthesis1 stage with subnodes: setup, run, validate, finish

SYNTHESIS1_SETUP_STAMP = $(STAMP_DIR)/synthesis1_setup.stamp
SYNTHESIS1_RUN_STAMP = $(STAMP_DIR)/synthesis1_run.stamp
SYNTHESIS1_VALIDATE_STAMP = $(STAMP_DIR)/synthesis1_validate.stamp
SYNTHESIS1_FINISH_STAMP = $(STAMP_DIR)/synthesis1_finish.stamp

.PHONY: synthesis1
synthesis1: $(SYNTHESIS1_STAMP)

$(SYNTHESIS1_STAMP): $(SYNTHESIS1_FINISH_STAMP)
	@echo "done synthesis1 stage completed"
	@touch $@

# synthesis1 setup subnode
$(SYNTHESIS1_SETUP_STAMP): $(INIT_DESIGN1_STAMP)
	@echo "Running synthesis1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/synthesis_subnode_handler.tcl" setup "$(PWD)" synthesis1
	@echo "done synthesis1 setup completed"
	@touch $@

# synthesis1 run subnode
$(SYNTHESIS1_RUN_STAMP): $(SYNTHESIS1_SETUP_STAMP)
	@echo "Running synthesis1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/synthesis_subnode_handler.tcl" run "$(PWD)" synthesis1
	@echo "done synthesis1 run completed"
	@touch $@

# synthesis1 validate subnode
$(SYNTHESIS1_VALIDATE_STAMP): $(SYNTHESIS1_RUN_STAMP)
	@echo "Running synthesis1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/synthesis_subnode_handler.tcl" validate "$(PWD)" synthesis1
	@echo "done synthesis1 validate completed"
	@touch $@

# synthesis1 finish subnode
$(SYNTHESIS1_FINISH_STAMP): $(SYNTHESIS1_VALIDATE_STAMP)
	@echo "Running synthesis1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/$(FC_VERSION)/synthesis_subnode_handler.tcl" finish "$(PWD)" synthesis1
	@echo "done synthesis1 finish completed"
	@touch $@

