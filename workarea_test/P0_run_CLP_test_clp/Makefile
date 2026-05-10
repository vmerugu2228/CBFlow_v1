# ===============================================================================
# CBFlow CLP MAKEFILE
# Auto-generated for CLP flow
# Generated: 2026-05-09 21:38:20
# ===============================================================================

# ===============================================================================
# CLP VARIABLES
# ===============================================================================

# Environment variables - read from .run.cbflow.env
FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
VC_LP_VERSION ?= v1.0.0

# Directories
STAMP_DIR = .stamps
WORK_DIR = work
LOGS_DIR = logs

# ===============================================================================
# MAIN CLP TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete CLP flow
.PHONY: all
all: inputs1 clp1 export_data1 release_data1
	@echo "done CLP flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow CLP Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make clp1           Run clp1 stage"
	@echo "  make export_data1   Run export_data1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete CLP flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# CLP STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
CLP1_STAMP = $(STAMP_DIR)/clp1.stamp
EXPORT_DATA1_STAMP = $(STAMP_DIR)/export_data1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/clp1.mk
include .make/export_data1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean CLP results
.PHONY: clean
clean:
	@echo "Cleaning CLP files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

