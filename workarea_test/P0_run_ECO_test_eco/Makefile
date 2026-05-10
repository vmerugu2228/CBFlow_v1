# ===============================================================================
# CBFlow ECO MAKEFILE
# Auto-generated for ECO flow
# Generated: 2026-05-09 21:38:11
# ===============================================================================

# ===============================================================================
# ECO VARIABLES
# ===============================================================================

# Environment variables - read from .run.cbflow.env
FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
FC_VERSION ?= v1.0.0

# Directories
STAMP_DIR = .stamps
WORK_DIR = work
LOGS_DIR = logs

# ===============================================================================
# MAIN ECO TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete ECO flow
.PHONY: all
all: inputs1 eco1 export_db1
	@echo "done ECO flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow ECO Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make eco1           Run eco1 stage"
	@echo "  make export_db1     Run export_db1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete ECO flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# ECO STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
ECO1_STAMP = $(STAMP_DIR)/eco1.stamp
EXPORT_DB1_STAMP = $(STAMP_DIR)/export_db1.stamp

include .make/inputs1.mk
include .make/eco1.mk
include .make/export_db1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean ECO results
.PHONY: clean
clean:
	@echo "Cleaning ECO files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

