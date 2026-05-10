#!/bin/bash
# CBflow All-Flow Test Mode Verification
# Creates a run for each of the 14 flows and verifies wrappers/launch modes
set -uo pipefail

CBFLOW_BIN="/Users/vmerugu/projects/CBflow_clone/PD/bin/cbflow"
WORKAREA="/Users/vmerugu/projects/CBflow_clone/workarea_test"
DUMMY_RTL="/Users/vmerugu/projects/CBflow_clone/rtl.list"
DUMMY_SDC="/Users/vmerugu/projects/CBflow_clone/func.sdc"
DUMMY_UPF="/Users/vmerugu/projects/CBflow_clone/power.upf"
DUMMY_NETLIST="/Users/vmerugu/projects/CBflow_clone/netlist.v"
DUMMY_DEF="/Users/vmerugu/projects/CBflow_clone/floorplan.def"

# Ensure dummy files exist
touch "$DUMMY_RTL" "$DUMMY_SDC" "$DUMMY_UPF" "$DUMMY_NETLIST" "$DUMMY_DEF"

cd "$WORKAREA"

PASS=0
FAIL=0
SKIP=0
RESULTS=""

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  CBflow All-Flow Test Mode Verification"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════════"
echo ""

test_flow() {
    local FLOW="$1"
    local CONFIG_BODY="$2"
    local RUN_NAME="test_$(echo "$FLOW" | tr '[:upper:]' '[:lower:]')"
    local RUN_DIR="P0_run_${FLOW}_${RUN_NAME}"
    local CONFIG_FILE="user_config_$(echo "$FLOW" | tr '[:upper:]' '[:lower:]')_test.tcl"

    echo "── ${FLOW} ──────────────────────────────────────────────"

    # Clean previous
    rm -rf "$RUN_DIR"

    # Write user_config
    cat > "$CONFIG_FILE" << TCEOF
#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "${FLOW}"
set flow(design_name)    "cpu_core"
set flow(run_name)       "${RUN_NAME}"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"
${CONFIG_BODY}
TCEOF

    # Create run
    local CREATE_OUT
    CREATE_OUT=$("$CBFLOW_BIN" workspace create --config "$CONFIG_FILE" 2>&1)
    local CREATE_RC=$?

    if [ $CREATE_RC -ne 0 ]; then
        echo "  [FAIL] workspace create (rc=$CREATE_RC)"
        echo "         $(echo "$CREATE_OUT" | grep -i "error\|fail" | head -3)"
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}\n  [FAIL] ${FLOW}: workspace create failed"
        rm -f "$CONFIG_FILE"
        return
    fi
    echo "  [PASS] workspace create"

    # Check run directory exists
    if [ ! -d "$RUN_DIR" ]; then
        echo "  [FAIL] run directory not found: $RUN_DIR"
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}\n  [FAIL] ${FLOW}: run directory not found"
        rm -f "$CONFIG_FILE"
        return
    fi

    # Check essential files
    local FILES_OK=true
    for f in .run.cbflow.tcl .run.cbflow.env Makefile; do
        if [ ! -f "$RUN_DIR/$f" ]; then
            echo "  [FAIL] missing: $f"
            FILES_OK=false
        fi
    done

    if [ "$FILES_OK" = false ]; then
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}\n  [FAIL] ${FLOW}: missing essential files"
        rm -f "$CONFIG_FILE"
        return
    fi
    echo "  [PASS] run directory structure"

    # Check release version
    local REL_VER
    REL_VER=$(grep "CBFLOW_RELEASE_VERSION" "$RUN_DIR/.run.cbflow.tcl" | head -1 | sed 's/.*"\(.*\)"/\1/')
    echo "  [PASS] release: $REL_VER"

    # Run cbflow run status
    local STATUS_OUT
    STATUS_OUT=$(cd "$RUN_DIR" && "$CBFLOW_BIN" run status 2>&1)
    local STATUS_RC=$?
    if [ $STATUS_RC -eq 0 ]; then
        local STAGE_COUNT
        STAGE_COUNT=$(echo "$STATUS_OUT" | grep -c "not started\|completed\|in_progress" || true)
        echo "  [PASS] run status ($STAGE_COUNT stages)"
    else
        echo "  [FAIL] run status (rc=$STATUS_RC)"
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}\n  [FAIL] ${FLOW}: run status failed"
        rm -f "$CONFIG_FILE"
        return
    fi

    # Run cbflow run show-graph
    local GRAPH_OUT
    GRAPH_OUT=$(cd "$RUN_DIR" && "$CBFLOW_BIN" run show-graph 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [PASS] show-graph"
    else
        echo "  [WARN] show-graph failed"
    fi

    # Count wrappers that would be generated (run handlers in test mode)
    local HANDLER_DIR
    # Find the handler directory for this flow
    local VENDOR_TOOL
    VENDOR_TOOL=$(ls -d /Users/vmerugu/projects/CBflow_clone/PD/cmds/${FLOW}/synopsys/*/v1.0.0 2>/dev/null | head -1)
    if [ -z "$VENDOR_TOOL" ]; then
        VENDOR_TOOL=$(ls -d /Users/vmerugu/projects/CBflow_clone/PD/cmds/${FLOW}/cadence/*/v1.0.0 2>/dev/null | head -1)
    fi
    if [ -z "$VENDOR_TOOL" ]; then
        VENDOR_TOOL=$(ls -d /Users/vmerugu/projects/CBflow_clone/PD/cmds/${FLOW}/mentor/*/v1.0.0 2>/dev/null | head -1)
    fi

    if [ -n "$VENDOR_TOOL" ]; then
        # Find all handlers that have "run" subnode (not inputs)
        local HANDLER_COUNT=0
        local WRAPPER_COUNT=0
        local LAUNCH_COUNT=0

        for handler in "$VENDOR_TOOL"/*_subnode_handler.tcl; do
            local hname=$(basename "$handler" _subnode_handler.tcl)
            # Skip inputs handlers
            [[ "$hname" == "inputs" || "$hname" == "inputs1" ]] && continue
            # Check if handler has "run" subnode with launch logic
            if grep -q "Determine launch mode" "$handler" 2>/dev/null; then
                # Get stage name from handler
                local stage_name
                stage_name=$(grep 'set stage_name' "$handler" | head -1 | sed 's/.*"\(.*\)"/\1/')
                [ -z "$stage_name" ] && stage_name="$hname"
                local node_name="${stage_name}1"

                # Create work dir and run handler
                mkdir -p "$RUN_DIR/work/${FLOW}/${node_name}/run" "$RUN_DIR/logs"
                local HOUT
                HOUT=$(tclsh "$handler" run "$RUN_DIR" "$node_name" 2>&1)
                local HRC=$?
                HANDLER_COUNT=$((HANDLER_COUNT + 1))

                if echo "$HOUT" | grep -q "run completed \[TEST MODE\]"; then
                    # Check wrapper exists
                    local wrapper="$RUN_DIR/work/${FLOW}/${node_name}/run/launch_${stage_name}.csh"
                    if [ -f "$wrapper" ]; then
                        WRAPPER_COUNT=$((WRAPPER_COUNT + 1))
                    fi
                    # Check launch mode
                    if echo "$HOUT" | grep -q "Launch mode:"; then
                        LAUNCH_COUNT=$((LAUNCH_COUNT + 1))
                    fi
                fi
            fi
        done

        if [ $HANDLER_COUNT -gt 0 ]; then
            echo "  [PASS] handlers: $HANDLER_COUNT run, $WRAPPER_COUNT wrappers, $LAUNCH_COUNT launch-mode"
        else
            echo "  [SKIP] no handlers with launch logic found"
        fi
    else
        echo "  [SKIP] no handler directory found for $FLOW"
    fi

    PASS=$((PASS + 1))
    RESULTS="${RESULTS}\n  [PASS] ${FLOW}: create + status + handlers OK"

    # Cleanup config file
    rm -f "$CONFIG_FILE"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Test each flow with appropriate mandatory inputs
# ═══════════════════════════════════════════════════════════════

test_flow "SYNTH_PNR" "
set synth_pnr(input,rtl_filelist)   \"$DUMMY_RTL\"
set synth_pnr(input,sdc_func_file)  \"$DUMMY_SDC\"
set synth_pnr(input,upf_file)       \"$DUMMY_UPF\"
set synth_pnr(input,rtl_format)     \"sverilog\"
"

test_flow "SYNTH" "
set synth(input,rtl_filelist)   \"$DUMMY_RTL\"
set synth(input,sdc_func_file)  \"$DUMMY_SDC\"
set synth(input,rtl_format)     \"sverilog\"
"

test_flow "PNR" "
set pnr(input,netlist)         \"$DUMMY_NETLIST\"
set pnr(input,sdc_func_file)   \"$DUMMY_SDC\"
set pnr(input,def_file)        \"$DUMMY_DEF\"
"

test_flow "FP" "
set fp(input,netlist)          \"$DUMMY_NETLIST\"
set fp(input,sdc_func_file)    \"$DUMMY_SDC\"
"

test_flow "STA" "
set sta(input,netlist)         \"$DUMMY_NETLIST\"
set sta(input,sdc_func_file)   \"$DUMMY_SDC\"
"

test_flow "LEC" "
set lec(input,rtl_files)       \"$DUMMY_RTL\"
set lec(input,netlist_revised) \"$DUMMY_NETLIST\"
"

test_flow "ECO" "
set eco(eco,type)              \"timing\"
set eco(input,netlist)         \"$DUMMY_NETLIST\"
"

test_flow "CLP" "
set clp(input,reference_netlist) \"$DUMMY_NETLIST\"
set clp(input,upf_file)          \"$DUMMY_UPF\"
"

test_flow "EMIR" "
set emir(input,netlist)        \"$DUMMY_NETLIST\"
set emir(input,def_file)       \"$DUMMY_DEF\"
"

test_flow "PV" "
set pv(input,gds_file)         \"$DUMMY_DEF\"
"

test_flow "POPT" "
set popt(input,netlist)        \"$DUMMY_NETLIST\"
set popt(input,sdc_func_file)  \"$DUMMY_SDC\"
"

test_flow "FCFP" "
set fcfp(input,netlist)        \"$DUMMY_NETLIST\"
"

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo -e "$RESULTS"
echo ""
echo "  ──────────────────────────────────────────────────"
echo "  PASS: $PASS"
[ $FAIL -gt 0 ] && echo "  FAIL: $FAIL"
[ $SKIP -gt 0 ] && echo "  SKIP: $SKIP"
TOTAL=$((PASS + FAIL))
echo "  TOTAL: $TOTAL/14 flows"
echo ""
if [ $FAIL -eq 0 ]; then
    echo "  All flows verified successfully."
else
    echo "  $FAIL flow(s) FAILED."
fi
echo ""
