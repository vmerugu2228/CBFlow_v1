# ===============================================================================
# CBFlow FP MAKEFILE
# Auto-generated for FP flow
# Generated: 2026-05-09 21:37:43
# ===============================================================================

# ===============================================================================
# FP VARIABLES
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
# MAIN FP TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete FP flow
.PHONY: all
all: inputs1 init_design1 import_design1 floorplan1 powerplan1 place_pins1 export_data1 release_data1
	@echo "done FP flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow FP Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make init_design1   Run init_design1 stage"
	@echo "  make import_design1   Run import_design1 stage"
	@echo "  make floorplan1     Run floorplan1 stage"
	@echo "  make powerplan1     Run powerplan1 stage"
	@echo "  make place_pins1    Run place_pins1 stage"
	@echo "  make export_data1   Run export_data1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete FP flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# FP STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
INIT_DESIGN1_STAMP = $(STAMP_DIR)/init_design1.stamp
IMPORT_DESIGN1_STAMP = $(STAMP_DIR)/import_design1.stamp
FLOORPLAN1_STAMP = $(STAMP_DIR)/floorplan1.stamp
POWERPLAN1_STAMP = $(STAMP_DIR)/powerplan1.stamp
PLACE_PINS1_STAMP = $(STAMP_DIR)/place_pins1.stamp
EXPORT_DATA1_STAMP = $(STAMP_DIR)/export_data1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/init_design1.mk
include .make/import_design1.mk
include .make/floorplan1.mk
include .make/powerplan1.mk
include .make/place_pins1.mk
include .make/export_data1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean FP results
.PHONY: clean
clean:
	@echo "Cleaning FP files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

