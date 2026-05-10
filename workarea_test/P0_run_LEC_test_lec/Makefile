# ===============================================================================
# CBFlow LEC MAKEFILE
# Auto-generated for LEC flow
# Generated: 2026-05-09 21:38:02
# ===============================================================================

# ===============================================================================
# LEC VARIABLES
# ===============================================================================

# Environment variables - read from .run.cbflow.env
FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION=' .run.cbflow.env | cut -d'=' -f2 | tr -d '"')
FORMALITY_VERSION ?= v1.0.0

# Directories
STAMP_DIR = .stamps
WORK_DIR = work
LOGS_DIR = logs

# ===============================================================================
# MAIN LEC TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete LEC flow
.PHONY: all
all: inputs1 setup1 compare1 analyze1
	@echo "done LEC flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow LEC Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make setup1         Run setup1 stage"
	@echo "  make compare1       Run compare1 stage"
	@echo "  make analyze1       Run analyze1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete LEC flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# LEC STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
SETUP1_STAMP = $(STAMP_DIR)/setup1.stamp
COMPARE1_STAMP = $(STAMP_DIR)/compare1.stamp
ANALYZE1_STAMP = $(STAMP_DIR)/analyze1.stamp

include .make/inputs1.mk
include .make/setup1.mk
include .make/compare1.mk
include .make/analyze1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean LEC results
.PHONY: clean
clean:
	@echo "Cleaning LEC files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

