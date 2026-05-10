# CBFlow SYNTH_PNR inputs1 Stage Makefile
# Auto-generated for SYNTH_PNR flow

# inputs1 stage with subnodes: setup, rtl, sdc, upf, validate, finish

INPUTS1_SETUP_STAMP = $(STAMP_DIR)/inputs1_setup.stamp
INPUTS1_RTL_STAMP = $(STAMP_DIR)/inputs1_rtl.stamp
INPUTS1_SDC_STAMP = $(STAMP_DIR)/inputs1_sdc.stamp
INPUTS1_UPF_STAMP = $(STAMP_DIR)/inputs1_upf.stamp
INPUTS1_VALIDATE_STAMP = $(STAMP_DIR)/inputs1_validate.stamp
INPUTS1_FINISH_STAMP = $(STAMP_DIR)/inputs1_finish.stamp

.PHONY: inputs1
inputs1: $(INPUTS1_STAMP)

$(INPUTS1_STAMP): $(INPUTS1_SETUP_STAMP) $(INPUTS1_RTL_STAMP) $(INPUTS1_SDC_STAMP) $(INPUTS1_UPF_STAMP) $(INPUTS1_VALIDATE_STAMP) $(INPUTS1_FINISH_STAMP)
	@echo "done inputs1 stage completed"
	@touch $@

# inputs1 setup subnode
$(INPUTS1_SETUP_STAMP): 
	@echo "Running inputs1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" setup "$(PWD)" inputs1
	@echo "done inputs1 setup completed"
	@touch $@

# inputs1 rtl subnode
$(INPUTS1_RTL_STAMP): 
	@echo "Running inputs1 rtl..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" rtl "$(PWD)" inputs1
	@echo "done inputs1 rtl completed"
	@touch $@

# inputs1 sdc subnode
$(INPUTS1_SDC_STAMP): 
	@echo "Running inputs1 sdc..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" sdc "$(PWD)" inputs1
	@echo "done inputs1 sdc completed"
	@touch $@

# inputs1 upf subnode
$(INPUTS1_UPF_STAMP): 
	@echo "Running inputs1 upf..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" upf "$(PWD)" inputs1
	@echo "done inputs1 upf completed"
	@touch $@

# inputs1 validate subnode
$(INPUTS1_VALIDATE_STAMP): $(INPUTS1_SETUP_STAMP) $(INPUTS1_RTL_STAMP) $(INPUTS1_SDC_STAMP) $(INPUTS1_UPF_STAMP)
	@echo "Running inputs1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" validate "$(PWD)" inputs1
	@echo "done inputs1 validate completed"
	@touch $@

# inputs1 finish subnode
$(INPUTS1_FINISH_STAMP): $(INPUTS1_VALIDATE_STAMP)
	@echo "Running inputs1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" finish "$(PWD)" inputs1
	@echo "done inputs1 finish completed"
	@touch $@

