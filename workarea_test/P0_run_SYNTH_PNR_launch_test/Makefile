# ===============================================================================
# CBFlow SYNTH_PNR MAKEFILE
# Auto-generated for SYNTH_PNR flow
# Generated: 2026-05-06 09:43:34
# ===============================================================================

# ===============================================================================
# SYNTH_PNR VARIABLES
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
# MAIN SYNTH_PNR TARGETS
# ===============================================================================

.DEFAULT_GOAL := help

# Complete SYNTH_PNR flow
.PHONY: all
all: inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1
	@echo "done SYNTH_PNR flow completed successfully"

# Show help information
.PHONY: help
help:
	@echo "CBFlow SYNTH_PNR Makefile"
	@echo ""
	@echo "Flow stages:"
	@echo "  make inputs1        Run inputs1 stage"
	@echo "  make init_design1   Run init_design1 stage"
	@echo "  make synthesis1     Run synthesis1 stage"
	@echo "  make place1         Run place1 stage"
	@echo "  make cts1           Run cts1 stage"
	@echo "  make cts_opt1       Run cts_opt1 stage"
	@echo "  make route1         Run route1 stage"
	@echo "  make pro1           Run pro1 stage"
	@echo "  make signoff1       Run signoff1 stage"
	@echo "  make export_data1   Run export_data1 stage"
	@echo "  make release_data1   Run release_data1 stage"
	@echo ""
	@echo "Commands:"
	@echo "  make all           Run complete SYNTH_PNR flow"
	@echo "  make clean         Clean all generated files"

# ===============================================================================
# SYNTH_PNR STAGE TARGETS
# ===============================================================================

INPUTS1_STAMP = $(STAMP_DIR)/inputs1.stamp
INIT_DESIGN1_STAMP = $(STAMP_DIR)/init_design1.stamp
SYNTHESIS1_STAMP = $(STAMP_DIR)/synthesis1.stamp
PLACE1_STAMP = $(STAMP_DIR)/place1.stamp
CTS1_STAMP = $(STAMP_DIR)/cts1.stamp
CTS_OPT1_STAMP = $(STAMP_DIR)/cts_opt1.stamp
ROUTE1_STAMP = $(STAMP_DIR)/route1.stamp
PRO1_STAMP = $(STAMP_DIR)/pro1.stamp
SIGNOFF1_STAMP = $(STAMP_DIR)/signoff1.stamp
EXPORT_DATA1_STAMP = $(STAMP_DIR)/export_data1.stamp
RELEASE_DATA1_STAMP = $(STAMP_DIR)/release_data1.stamp

include .make/inputs1.mk
include .make/init_design1.mk
include .make/synthesis1.mk
include .make/place1.mk
include .make/cts1.mk
include .make/cts_opt1.mk
include .make/route1.mk
include .make/pro1.mk
include .make/signoff1.mk
include .make/export_data1.mk
include .make/release_data1.mk

# ===============================================================================
# CLEAN
# ===============================================================================

# Clean SYNTH_PNR results
.PHONY: clean
clean:
	@echo "Cleaning SYNTH_PNR files..."
	@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make
	@rm -f Makefile
	@echo "[DONE] Clean completed"

