# CBFlow STA timing1 Stage Makefile
# Auto-generated for STA flow

# timing1 stage with subnodes: dynamic

TIMING1_DYNAMIC_STAMP = $(STAMP_DIR)/timing1_dynamic.stamp

.PHONY: timing1
timing1: $(TIMING1_STAMP)

$(TIMING1_STAMP): $(TIMING1_DYNAMIC_STAMP)
	@echo "done timing1 stage completed"
	@touch $@

# timing1 dynamic subnode
$(TIMING1_DYNAMIC_STAMP): $(EXTRACTION1_STAMP)
	@echo "Running timing1 dynamic..."
	@mkdir -p $(STAMP_DIR) $(LOGS_DIR)
	@tclsh "$(FLOW_DIR)/cmds/STA/cadence/tempus/$(TEMPUS_VERSION)/timing_subnode_handler.tcl" dynamic "$(PWD)" timing1
	@echo "done timing1 dynamic completed"
	@touch $@

