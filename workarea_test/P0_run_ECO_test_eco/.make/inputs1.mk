# CBFlow ECO inputs1 Stage Makefile
# Auto-generated for ECO flow

# inputs1 stage with subnodes: setup, netlist, def, sdc, library, validate, finish

INPUTS1_SETUP_STAMP = $(STAMP_DIR)/inputs1_setup.stamp
INPUTS1_NETLIST_STAMP = $(STAMP_DIR)/inputs1_netlist.stamp
INPUTS1_DEF_STAMP = $(STAMP_DIR)/inputs1_def.stamp
INPUTS1_SDC_STAMP = $(STAMP_DIR)/inputs1_sdc.stamp
INPUTS1_LIBRARY_STAMP = $(STAMP_DIR)/inputs1_library.stamp
INPUTS1_VALIDATE_STAMP = $(STAMP_DIR)/inputs1_validate.stamp
INPUTS1_FINISH_STAMP = $(STAMP_DIR)/inputs1_finish.stamp

.PHONY: inputs1
inputs1: $(INPUTS1_STAMP)

$(INPUTS1_STAMP): $(INPUTS1_SETUP_STAMP) $(INPUTS1_NETLIST_STAMP) $(INPUTS1_DEF_STAMP) $(INPUTS1_SDC_STAMP) $(INPUTS1_LIBRARY_STAMP) $(INPUTS1_VALIDATE_STAMP) $(INPUTS1_FINISH_STAMP)
	@echo "done inputs1 stage completed"
	@touch $@

# inputs1 setup subnode
$(INPUTS1_SETUP_STAMP): 
	@echo "Running inputs1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" setup "$(PWD)" inputs1
	@echo "done inputs1 setup completed"
	@touch $@

# inputs1 netlist subnode
$(INPUTS1_NETLIST_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 netlist..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" netlist "$(PWD)" inputs1
	@echo "done inputs1 netlist completed"
	@touch $@

# inputs1 def subnode
$(INPUTS1_DEF_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 def..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" def "$(PWD)" inputs1
	@echo "done inputs1 def completed"
	@touch $@

# inputs1 sdc subnode
$(INPUTS1_SDC_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 sdc..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" sdc "$(PWD)" inputs1
	@echo "done inputs1 sdc completed"
	@touch $@

# inputs1 library subnode
$(INPUTS1_LIBRARY_STAMP): $(INPUTS1_SETUP_STAMP)
	@echo "Running inputs1 library..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" library "$(PWD)" inputs1
	@echo "done inputs1 library completed"
	@touch $@

# inputs1 validate subnode
$(INPUTS1_VALIDATE_STAMP): $(INPUTS1_NETLIST_STAMP) $(INPUTS1_DEF_STAMP) $(INPUTS1_SDC_STAMP) $(INPUTS1_LIBRARY_STAMP)
	@echo "Running inputs1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" validate "$(PWD)" inputs1
	@echo "done inputs1 validate completed"
	@touch $@

# inputs1 finish subnode
$(INPUTS1_FINISH_STAMP): $(INPUTS1_VALIDATE_STAMP)
	@echo "Running inputs1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/ECO/synopsys/fc/$(FC_VERSION)/inputs_subnode_handler.tcl" finish "$(PWD)" inputs1
	@echo "done inputs1 finish completed"
	@touch $@

