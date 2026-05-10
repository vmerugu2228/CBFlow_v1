# ===============================================================================
# CBFlow POPT MAKEFILE
# Auto-generated for POPT flow
# Generated: 2026-05-09 21:38:47
# ===============================================================================

# ===============================================================================
# POPT VARIABLES
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
# MAIN POPT TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete POPT flow
.PHONY: all
all: inputs1 merge_timing1 power_opt1 post_merge1 release_data1
	@echo "done POPT flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow POPT Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make merge_timing1   Run merge_timing1 stage"
	@echo "  make power_opt1     Run power_opt1 stage"
	@echo "  make post_merge1    Run post_merge1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete POPT flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# POPT STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
MERGE_TIMING1_STAMP = $(STAMP_DIR)/merge_timing1.stamp
POWER_OPT1_STAMP = $(STAMP_DIR)/power_opt1.stamp
POST_MERGE1_STAMP = $(STAMP_DIR)/post_merge1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/merge_timing1.mk
include .make/power_opt1.mk
include .make/post_merge1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean POPT results
.PHONY: clean
clean:
	@echo "Cleaning POPT files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

