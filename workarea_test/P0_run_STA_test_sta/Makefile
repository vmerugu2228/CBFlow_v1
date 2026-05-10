# ===============================================================================
# CBFlow STA MAKEFILE
# Auto-generated for STA flow
# Generated: 2026-05-09 21:37:53
# ===============================================================================

# ===============================================================================
# STA VARIABLES
# ===============================================================================

# Environment variables - read from .run.cbflow.env
FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
PT_VERSION ?= v1.0.0

# Directories
STAMP_DIR = .stamps
WORK_DIR = work
LOGS_DIR = logs

# ===============================================================================
# MAIN STA TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete STA flow
.PHONY: all
all: inputs1 extraction1 timing1 reporting1 release_data1
	@echo "done STA flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow STA Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make extraction1    Run extraction1 stage"
	@echo "  make timing1        Run timing1 stage"
	@echo "  make reporting1     Run reporting1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete STA flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# STA STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
EXTRACTION1_STAMP = $(STAMP_DIR)/extraction1.stamp
TIMING1_STAMP = $(STAMP_DIR)/timing1.stamp
REPORTING1_STAMP = $(STAMP_DIR)/reporting1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/extraction1.mk
include .make/timing1.mk
include .make/reporting1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean STA results
.PHONY: clean
clean:
	@echo "Cleaning STA files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

