# ===============================================================================
# CBFlow FCFP MAKEFILE
# Auto-generated for FCFP flow
# Generated: 2026-05-09 21:38:56
# ===============================================================================

# ===============================================================================
# FCFP VARIABLES
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
# MAIN FCFP TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete FCFP flow
.PHONY: all
all: inputs1 init_design1 commit_blocks1 init_compile1 create_floorplan1 shaping1 placement1 create_power1 place_pins1 top_compile1 timing_budget1 export_data1 release_data1
	@echo "done FCFP flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow FCFP Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make init_design1   Run init_design1 stage"
	@echo "  make commit_blocks1   Run commit_blocks1 stage"
	@echo "  make init_compile1   Run init_compile1 stage"
	@echo "  make create_floorplan1   Run create_floorplan1 stage"
	@echo "  make shaping1       Run shaping1 stage"
	@echo "  make placement1     Run placement1 stage"
	@echo "  make create_power1   Run create_power1 stage"
	@echo "  make place_pins1    Run place_pins1 stage"
	@echo "  make top_compile1   Run top_compile1 stage"
	@echo "  make timing_budget1   Run timing_budget1 stage"
	@echo "  make export_data1   Run export_data1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete FCFP flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# FCFP STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
INIT_DESIGN1_STAMP = $(STAMP_DIR)/init_design1.stamp
COMMIT_BLOCKS1_STAMP = $(STAMP_DIR)/commit_blocks1.stamp
INIT_COMPILE1_STAMP = $(STAMP_DIR)/init_compile1.stamp
CREATE_FLOORPLAN1_STAMP = $(STAMP_DIR)/create_floorplan1.stamp
SHAPING1_STAMP = $(STAMP_DIR)/shaping1.stamp
PLACEMENT1_STAMP = $(STAMP_DIR)/placement1.stamp
CREATE_POWER1_STAMP = $(STAMP_DIR)/create_power1.stamp
PLACE_PINS1_STAMP = $(STAMP_DIR)/place_pins1.stamp
TOP_COMPILE1_STAMP = $(STAMP_DIR)/top_compile1.stamp
TIMING_BUDGET1_STAMP = $(STAMP_DIR)/timing_budget1.stamp
EXPORT_DATA1_STAMP = $(STAMP_DIR)/export_data1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/init_design1.mk
include .make/commit_blocks1.mk
include .make/init_compile1.mk
include .make/create_floorplan1.mk
include .make/shaping1.mk
include .make/placement1.mk
include .make/create_power1.mk
include .make/place_pins1.mk
include .make/top_compile1.mk
include .make/timing_budget1.mk
include .make/export_data1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean FCFP results
.PHONY: clean
clean:
	@echo "Cleaning FCFP files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

