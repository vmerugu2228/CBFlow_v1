# ===============================================================================
# CBFlow PV MAKEFILE
# Auto-generated for PV flow
# Generated: 2026-05-09 21:38:38
# ===============================================================================

# ===============================================================================
# PV VARIABLES
# ===============================================================================

# Environment variables - read from .run.cbflow.env
FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
ICV_VERSION ?= v1.0.0

# Directories
STAMP_DIR = .stamps
WORK_DIR = work
LOGS_DIR = logs

# ===============================================================================
# MAIN PV TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete PV flow
.PHONY: all
all: inputs1 fill1 drc1 lvs1 perc1 erc1 xor1 merge_data1 release_data1
	@echo "done PV flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow PV Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make fill1          Run fill1 stage"
	@echo "  make drc1           Run drc1 stage"
	@echo "  make lvs1           Run lvs1 stage"
	@echo "  make perc1          Run perc1 stage"
	@echo "  make erc1           Run erc1 stage"
	@echo "  make xor1           Run xor1 stage"
	@echo "  make merge_data1    Run merge_data1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete PV flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# PV STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
FILL1_STAMP = $(STAMP_DIR)/fill1.stamp
DRC1_STAMP = $(STAMP_DIR)/drc1.stamp
LVS1_STAMP = $(STAMP_DIR)/lvs1.stamp
PERC1_STAMP = $(STAMP_DIR)/perc1.stamp
ERC1_STAMP = $(STAMP_DIR)/erc1.stamp
XOR1_STAMP = $(STAMP_DIR)/xor1.stamp
MERGE_DATA1_STAMP = $(STAMP_DIR)/merge_data1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/fill1.mk
include .make/drc1.mk
include .make/lvs1.mk
include .make/perc1.mk
include .make/erc1.mk
include .make/xor1.mk
include .make/merge_data1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean PV results
.PHONY: clean
clean:
	@echo "Cleaning PV files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

