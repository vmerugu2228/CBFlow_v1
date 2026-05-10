# CBFlow CLP clp1 Stage Makefile
# Auto-generated for CLP flow

# clp1 stage with subnodes: setup, run, validate, finish

CLP1_SETUP_STAMP = $(STAMP_DIR)/clp1_setup.stamp
CLP1_RUN_STAMP = $(STAMP_DIR)/clp1_run.stamp
CLP1_VALIDATE_STAMP = $(STAMP_DIR)/clp1_validate.stamp
CLP1_FINISH_STAMP = $(STAMP_DIR)/clp1_finish.stamp

.PHONY: clp1
clp1: $(CLP1_STAMP)

$(CLP1_STAMP): $(CLP1_FINISH_STAMP)
	@echo "done clp1 stage completed"
	@touch $@

# clp1 setup subnode
$(CLP1_SETUP_STAMP): $(INPUTS1_STAMP)
	@echo "Running clp1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/CLP/synopsys/vc_lp/$(VC_LP_VERSION)/clp_subnode_handler.tcl" setup "$(PWD)" clp1
	@echo "done clp1 setup completed"
	@touch $@

# clp1 run subnode
$(CLP1_RUN_STAMP): $(CLP1_SETUP_STAMP)
	@echo "Running clp1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/CLP/synopsys/vc_lp/$(VC_LP_VERSION)/clp_subnode_handler.tcl" run "$(PWD)" clp1
	@echo "done clp1 run completed"
	@touch $@

# clp1 validate subnode
$(CLP1_VALIDATE_STAMP): $(CLP1_RUN_STAMP)
	@echo "Running clp1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/CLP/synopsys/vc_lp/$(VC_LP_VERSION)/clp_subnode_handler.tcl" validate "$(PWD)" clp1
	@echo "done clp1 validate completed"
	@touch $@

# clp1 finish subnode
$(CLP1_FINISH_STAMP): $(CLP1_VALIDATE_STAMP)
	@echo "Running clp1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/CLP/synopsys/vc_lp/$(VC_LP_VERSION)/clp_subnode_handler.tcl" finish "$(PWD)" clp1
	@echo "done clp1 finish completed"
	@touch $@

