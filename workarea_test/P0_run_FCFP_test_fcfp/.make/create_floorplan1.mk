# CBFlow FCFP create_floorplan1 Stage Makefile
# Auto-generated for FCFP flow

# create_floorplan1 stage with subnodes: setup, run, validate, finish

CREATE_FLOORPLAN1_SETUP_STAMP = $(STAMP_DIR)/create_floorplan1_setup.stamp
CREATE_FLOORPLAN1_RUN_STAMP = $(STAMP_DIR)/create_floorplan1_run.stamp
CREATE_FLOORPLAN1_VALIDATE_STAMP = $(STAMP_DIR)/create_floorplan1_validate.stamp
CREATE_FLOORPLAN1_FINISH_STAMP = $(STAMP_DIR)/create_floorplan1_finish.stamp

.PHONY: create_floorplan1
create_floorplan1: $(CREATE_FLOORPLAN1_STAMP)

$(CREATE_FLOORPLAN1_STAMP): $(CREATE_FLOORPLAN1_FINISH_STAMP)
	@echo "done create_floorplan1 stage completed"
	@touch $@

# create_floorplan1 setup subnode
$(CREATE_FLOORPLAN1_SETUP_STAMP): $(INIT_COMPILE1_STAMP)
	@echo "Running create_floorplan1 setup..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_floorplan_subnode_handler.tcl" setup "$(PWD)" create_floorplan1
	@echo "done create_floorplan1 setup completed"
	@touch $@

# create_floorplan1 run subnode
$(CREATE_FLOORPLAN1_RUN_STAMP): $(CREATE_FLOORPLAN1_SETUP_STAMP)
	@echo "Running create_floorplan1 run..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_floorplan_subnode_handler.tcl" run "$(PWD)" create_floorplan1
	@echo "done create_floorplan1 run completed"
	@touch $@

# create_floorplan1 validate subnode
$(CREATE_FLOORPLAN1_VALIDATE_STAMP): $(CREATE_FLOORPLAN1_RUN_STAMP)
	@echo "Running create_floorplan1 validate..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_floorplan_subnode_handler.tcl" validate "$(PWD)" create_floorplan1
	@echo "done create_floorplan1 validate completed"
	@touch $@

# create_floorplan1 finish subnode
$(CREATE_FLOORPLAN1_FINISH_STAMP): $(CREATE_FLOORPLAN1_VALIDATE_STAMP)
	@echo "Running create_floorplan1 finish..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/FCFP/synopsys/fc/$(FC_VERSION)/create_floorplan_subnode_handler.tcl" finish "$(PWD)" create_floorplan1
	@echo "done create_floorplan1 finish completed"
	@touch $@

