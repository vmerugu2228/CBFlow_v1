# ===============================================================================
# CBFlow EMIR MAKEFILE
# Auto-generated for EMIR flow
# Generated: 2026-05-09 21:38:29
# ===============================================================================

# ===============================================================================
# EMIR VARIABLES
# ===============================================================================

# Environment variables - read from .run.cbflow.env
FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
REDHAWK_VERSION ?= v1.0.0

# Directories
STAMP_DIR = .stamps
WORK_DIR = work
LOGS_DIR = logs

# ===============================================================================
# MAIN EMIR TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete EMIR flow
.PHONY: all
all: inputs1 power_analysis1 ir_drop1 thermal_analysis1
	@echo "done EMIR flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow EMIR Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make power_analysis1   Run power_analysis1 stage"
	@echo "  make ir_drop1       Run ir_drop1 stage"
	@echo "  make thermal_analysis1   Run thermal_analysis1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete EMIR flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# EMIR STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
POWER_ANALYSIS1_STAMP = $(STAMP_DIR)/power_analysis1.stamp
IR_DROP1_STAMP = $(STAMP_DIR)/ir_drop1.stamp
THERMAL_ANALYSIS1_STAMP = $(STAMP_DIR)/thermal_analysis1.stamp

include .make/inputs1.mk
include .make/power_analysis1.mk
include .make/ir_drop1.mk
include .make/thermal_analysis1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean EMIR results
.PHONY: clean
clean:
	@echo "Cleaning EMIR files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

