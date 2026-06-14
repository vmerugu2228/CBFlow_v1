"""Static config-validation checks. Ported from PD/bin/cbflow-test-suite.

8 categories of read-only validation across all 12 flows. No subprocess, no
workspace creation — just structural checks against config and command files.
"""

import os
import re
from pathlib import Path


# ── Category 1: Workspace and Run Creation ──────────────────────────────────

def cat1_workspace_creation(results, pd_dir, flows):
    suite = 'static'
    category = 'cat1_workspace_creation'

    for flow in flows:
        config_file = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'node_configs', f'{flow}_config.tcl')
        if os.path.exists(config_file):
            results.passed(suite, category, f'{flow}: node config exists')
        else:
            results.failed(suite, category, f'{flow}: node config missing', config_file)
            continue

        with open(config_file) as f:
            content = f.read()

        m = re.search(r'stages\s+\{([^}]+)\}', content)
        if m:
            stages = m.group(1).split()
            results.passed(suite, category, f'{flow}: stages defined', f'{len(stages)}: {" ".join(stages)}')
        else:
            results.failed(suite, category, f'{flow}: no stages defined')
            continue

        for stage in stages:
            if f'dependencies,{stage}' in content:
                results.passed(suite, category, f'{flow}/{stage}: dependency defined')
            else:
                results.failed(suite, category, f'{flow}/{stage}: missing dependency entry')

            for attr in ['stage_types', 'node_types']:
                if f'{attr},{stage}' in content:
                    results.passed(suite, category, f'{flow}/{stage}: {attr} defined')
                else:
                    results.failed(suite, category, f'{flow}/{stage}: missing {attr}')

            if f'runtime,timeout,{stage}' in content:
                results.passed(suite, category, f'{flow}/{stage}: timeout defined')
            else:
                results.failed(suite, category, f'{flow}/{stage}: missing runtime timeout')

    flow_config = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'flow_config.tcl')
    if os.path.exists(flow_config):
        with open(flow_config) as f:
            fc = f.read()
        m = re.search(r'flow\(types\)\s+\{([^}]+)\}', fc)
        if m:
            defined = m.group(1).split()
            for flow in flows:
                if flow in defined:
                    results.passed(suite, category, f'flow_config: {flow} in flow(types)')
                else:
                    results.failed(suite, category, f'flow_config: {flow} missing from flow(types)')
        results.passed(suite, category, 'flow_config.tcl exists and parseable')
    else:
        results.failed(suite, category, 'flow_config.tcl missing')


# ── Category 2: Makefile and Handler Validation ─────────────────────────────

_TOOL_CMD_SUFFIXES = [
    'fc', 'pt', 'icv', 'formality', 'vc_lp', 'redhawk',
    'genus', 'innovus', 'tempus', 'calibre', 'conformal_lp',
    'voltus', 'power_compiler',
]


def cat2_makefiles_handlers(results, pd_dir, flows):
    suite = 'static'
    category = 'cat2_makefiles_handlers'

    for flow in flows:
        config_file = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'node_configs', f'{flow}_config.tcl')
        if not os.path.exists(config_file):
            results.skipped(suite, category, f'{flow}: no config')
            continue
        with open(config_file) as f:
            content = f.read()
        m = re.search(r'stages\s+\{([^}]+)\}', content)
        if not m:
            continue
        stages = m.group(1).split()

        # Tool resolution: try the main flow config first (some flows include
        # tool,vendor/tool,name directly), then fall back to per-tool configs
        # (STA, LEC, EMIR, PV, CLP, POPT, ECO split tool data into separate
        # `<FLOW>_<tool>_config.tcl` files).
        tool_vendor, tool_name = _resolve_flow_tool(pd_dir, flow, content)
        if not tool_vendor or not tool_name:
            # Last resort: pick any concrete cmds/<FLOW>/<vendor>/<tool>/v1.0.0 dir.
            picks = list(_tool_dirs_for(pd_dir, flow))
            if not picks:
                results.failed(suite, category, f'{flow}: no cmds dir resolvable',
                               f'no tool defaults and no cmds/{flow}/*/*/v1.0.0/ found')
                continue
            tool_vendor, tool_name, _ = picks[0]

        cmds_dir = os.path.join(pd_dir, 'cmds', flow, tool_vendor, tool_name, 'v1.0.0')
        if not os.path.isdir(cmds_dir):
            results.failed(suite, category, f'{flow}: cmds dir missing', cmds_dir)
            continue

        # Parse node_types to know which stages are bundled inputs.
        # node_types,<stage>1 == "inputs" means the stage is handled by
        # inputs_<tool>.tcl rather than its own cmd file.
        node_types = {}
        for nm in re.finditer(r'node_types,(\w+)\s+"(\w+)"', content):
            node_types[nm.group(1)] = nm.group(2)

        inputs_cmd_file = os.path.join(cmds_dir, f'inputs_{tool_name}.tcl')
        inputs_handler = os.path.join(cmds_dir, 'inputs_subnode_handler.tcl')
        inputs_covered = os.path.exists(inputs_cmd_file) or os.path.exists(inputs_handler)

        for stage in stages:
            stage_base = stage.rstrip('0123456789')

            # Bundled-inputs stages: rtl1, sdc1, upf1, netlist1, def1, library1, etc.
            # — handled by inputs_<tool>.tcl, not a per-stage cmd file.
            if node_types.get(stage) == 'inputs':
                if inputs_covered:
                    results.passed(suite, category,
                                   f'{flow}/{stage}: covered by inputs_{tool_name}.tcl')
                else:
                    results.failed(suite, category,
                                   f'{flow}/{stage}: input pseudo-stage but no inputs_{tool_name}.tcl')
                continue

            cmd_found = False
            for suf in [tool_name] + _TOOL_CMD_SUFFIXES:
                pat = f'{stage_base}_{suf}.tcl'
                cmd_path = os.path.join(cmds_dir, pat)
                if os.path.exists(cmd_path):
                    cmd_found = True
                    with open(cmd_path) as f:
                        cc = f.read()
                    # The bootstrap convention sources setup.tcl (which
                    # provides REPORTS_DIR, tech_config, user_config). Accept
                    # either the literal token in the cmd file OR an explicit
                    # source of setup.tcl / config.tcl.
                    sources_setup = 'setup.tcl' in cc or '$run_dir/.run.cbflow.tcl' in cc
                    for key in ['REPORTS_DIR', 'tech_config', 'user_config']:
                        if key in cc or sources_setup:
                            results.passed(suite, category, f'{flow}/{stage}: {key} provided')
                        else:
                            results.failed(suite, category, f'{flow}/{stage}: {key} missing in {pat}')
                    # Cmd files end with `exit` literally OR via `flow_exec_all` /
                    # `exit_with_status` macros that handle exit internally.
                    stripped = cc.strip()
                    if (stripped.endswith('exit')
                            or 'flow_exec_all' in cc
                            or 'exit_with_status' in cc):
                        results.passed(suite, category, f'{flow}/{stage}: exit at end')
                    else:
                        results.failed(suite, category, f'{flow}/{stage}: missing exit in {pat}')
                    break

            if not cmd_found:
                handler_pats = [
                    f'{stage_base}_subnode_handler.tcl',
                    f'{stage_base}1_subnode_handler.tcl',
                ]
                if any(os.path.exists(os.path.join(cmds_dir, hp)) for hp in handler_pats):
                    results.passed(suite, category, f'{flow}/{stage}: handler exists')
                else:
                    results.failed(suite, category, f'{flow}/{stage}: no command file or handler found')

    mg = os.path.join(pd_dir, 'utils', 'commands', 'makefile_generator.py')
    if os.path.exists(mg):
        results.passed(suite, category, 'makefile_generator.py exists')
    else:
        results.failed(suite, category, 'makefile_generator.py missing')


# ── Category 3: Override Setup and Config Mechanism ─────────────────────────

def cat3_override_mechanism(results, pd_dir, flows):
    suite = 'static'
    category = 'cat3_override_mechanism'

    for flow in flows:
        config_file = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'node_configs', f'{flow}_config.tcl')
        if not os.path.exists(config_file):
            continue
        with open(config_file) as f:
            content = f.read()
        vendor = re.search(r'tool,vendor\s+"(\w+)"', content)
        tool = re.search(r'tool,name\s+"(\w+)"', content)
        v = vendor.group(1) if vendor else 'synopsys'
        t = tool.group(1) if tool else 'fc'

        cmds_dir = os.path.join(pd_dir, 'cmds', flow, v, t, 'v1.0.0')
        if not os.path.isdir(cmds_dir):
            continue

        for cmd_file in Path(cmds_dir).glob('*_*.tcl'):
            if 'handler' in cmd_file.name or 'subnode' in cmd_file.name:
                continue
            with open(cmd_file) as f:
                cc = f.read()
            if 'setup.tcl' in cc or 'setup_file' in cc:
                results.passed(suite, category, f'{flow}/{cmd_file.name}: setup.tcl hook mechanism')
            else:
                results.skipped(suite, category, f'{flow}/{cmd_file.name}: no setup.tcl hook')
            if 'override_setup' in cc:
                results.passed(suite, category, f'{flow}/{cmd_file.name}: override_setup mechanism')
            else:
                results.skipped(suite, category, f'{flow}/{cmd_file.name}: no override_setup')
            if 'config_file' in cc or 'config.tcl' in cc:
                results.passed(suite, category, f'{flow}/{cmd_file.name}: config.tcl sourced')
            else:
                results.skipped(suite, category, f'{flow}/{cmd_file.name}: no config.tcl sourcing')

    if os.path.exists(os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'flow_config.tcl')):
        results.passed(suite, category, 'Override hierarchy: flow_config.tcl (global)')

    for proj in ['phoenix', 'ravendrive']:
        if os.path.isdir(os.path.join(pd_dir, 'config', 'project', proj)):
            results.passed(suite, category, f'Override hierarchy: project config ({proj})')
        else:
            results.skipped(suite, category, f'Override hierarchy: project config ({proj}) not found')

    for tech in ['gf_22nm', 'tsmc_7nm', 'tsmc_5nm']:
        if os.path.isdir(os.path.join(pd_dir, 'config', 'tech', tech)):
            results.passed(suite, category, f'Override hierarchy: tech config ({tech})')
        else:
            results.failed(suite, category, f'Override hierarchy: tech config ({tech}) missing')


# ── Category 4: LSF Management ──────────────────────────────────────────────

def cat4_lsf_management(results, pd_dir, flows):
    suite = 'static'
    category = 'cat4_lsf_management'

    # tool_launch_config.tcl namespaces things under lsf(...). bsub queue/project
    # and queue tier definitions live in lsf_config.tcl (per the file's own
    # comment header). Module-load mappings moved to project configs.
    tlc = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'tool_launch_config.tcl')
    lsfc = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'lsf_config.tcl')

    if os.path.exists(tlc):
        with open(tlc) as f:
            tlc_content = f.read()
        for tool in ['fc', 'pt', 'fm', 'icv', 'genus', 'innovus', 'tempus']:
            if f'tool_shell,{tool}' in tlc_content:
                results.passed(suite, category, f'tool_launch_config: tool_shell for {tool}')
            else:
                results.failed(suite, category, f'tool_launch_config: missing tool_shell for {tool}')
        # Flow → stage mappings live as lsf(flow_mapping,<flow_lower>,<stage>).
        for flow in flows:
            if f'flow_mapping,{flow.lower()},' in tlc_content:
                results.passed(suite, category, f'tool_launch_config: {flow} flow_mapping')
            else:
                results.skipped(suite, category, f'tool_launch_config: {flow} flow_mapping not found')
    else:
        results.failed(suite, category, 'tool_launch_config.tcl missing')

    if os.path.exists(lsfc):
        with open(lsfc) as f:
            lsf_content = f.read()
        for key in ['bsub,queue', 'bsub,project']:
            if key in lsf_content:
                results.passed(suite, category, f'lsf_config: {key} defined')
            else:
                results.failed(suite, category, f'lsf_config: {key} missing')
        for queue in ['XS', 'S', 'M', 'L', 'XL', 'ultra']:
            if f'queue_types,{queue}' in lsf_content or f'queue,{queue}' in lsf_content:
                results.passed(suite, category, f'lsf_config: queue tier {queue}')
            else:
                results.failed(suite, category, f'lsf_config: queue tier {queue} missing')
    else:
        results.failed(suite, category, 'lsf_config.tcl missing')

    flow_config = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'flow_config.tcl')
    if os.path.exists(flow_config):
        with open(flow_config) as f:
            fc = f.read()
        for key in ['use_lsf', 'use_xterm']:
            if f'flow({key})' in fc:
                results.passed(suite, category, f'flow_config: flow({key}) defined')
            else:
                results.failed(suite, category, f'flow_config: flow({key}) missing')

    for module in ['lsf_cmd.py', 'lsf_manager_cmd.py']:
        if os.path.exists(os.path.join(pd_dir, 'utils', 'commands', module)):
            results.passed(suite, category, f'{module} exists')
        else:
            results.failed(suite, category, f'{module} missing')


# ── Category 5: MMMC Config and Scenario Creation ───────────────────────────

def cat5_mmmc_config(results, pd_dir, flows):
    suite = 'static'
    category = 'cat5_mmmc_config'

    # MMMC moved from framework-level to per-project. Check each project for
    # its own mmmc_config.tcl (ravendrive, denali, phoenix). Same for the
    # auto-generated scenarios file.
    proj_root = os.path.join(pd_dir, 'config', 'project')
    if os.path.isdir(proj_root):
        for proj in sorted(os.listdir(proj_root)):
            proj_mmmc = os.path.join(proj_root, proj, 'v1.0.0', 'mmmc_config.tcl')
            if os.path.exists(proj_mmmc):
                results.passed(suite, category, f'{proj}: mmmc_config.tcl present')
                with open(proj_mmmc) as f:
                    content = f.read()
                # Look for the canonical MMMC building blocks (any of these).
                markers = ['mmmc_config', 'mmmc(voltage', 'mmmc(pvt', 'mmmc(scenario',
                           'analysis_views', 'library_sets']
                if any(m in content for m in markers):
                    results.passed(suite, category, f'{proj}: mmmc_config has scenario data')
                else:
                    results.failed(suite, category, f'{proj}: mmmc_config.tcl has no scenario markers')
            else:
                results.skipped(suite, category, f'{proj}: no mmmc_config.tcl (project may not need MMMC)')

    if os.path.exists(os.path.join(pd_dir, 'utils', 'commands', 'mmmc_manager_cmd.py')):
        results.passed(suite, category, 'mmmc_manager_cmd.py exists')
    else:
        results.failed(suite, category, 'mmmc_manager_cmd.py missing')

    init_design = os.path.join(pd_dir, 'cmds', 'SYNTH_PNR', 'synopsys', 'fc', 'v1.0.0', 'init_design_fc.tcl')
    if os.path.exists(init_design):
        with open(init_design) as f:
            content = f.read()
        for cmd in ['create_mode', 'create_corner', 'create_scenario']:
            if cmd in content:
                results.passed(suite, category, f'init_design_fc: {cmd} present')
            else:
                results.failed(suite, category, f'init_design_fc: {cmd} missing — MCMM incomplete')
        if 'set_scenario_status' in content:
            results.passed(suite, category, 'init_design_fc: set_scenario_status for activation')
        else:
            results.failed(suite, category, 'init_design_fc: set_scenario_status missing')

    # Library data moved out of tech_config.tcl into per-phase lib_config_<P>.tcl.
    # Accept either: library_sets keyword in tech_config.tcl OR existence of any
    # lib_config*.tcl that references libraries.
    for tech in ['gf_22nm', 'tsmc_7nm', 'tsmc_5nm']:
        tech_dir = os.path.join(pd_dir, 'config', 'tech', tech, 'v1.0.0')
        if not os.path.isdir(tech_dir):
            continue
        has_libs = False
        for fname in os.listdir(tech_dir):
            if not fname.endswith('.tcl'):
                continue
            with open(os.path.join(tech_dir, fname)) as f:
                tc = f.read()
            # Any of these is sufficient evidence that the tech has library data.
            if any(s in tc for s in ('library_sets', 'tech(ndm', 'set tech(',
                                     'lib_root', 'ndm,stdcell')):
                has_libs = True
                break
        if has_libs:
            results.passed(suite, category, f'{tech}: library data present')
        else:
            results.failed(suite, category, f'{tech}: no library data found in tech/{tech}/v1.0.0/*.tcl')


# ── Category 6: Mandatory I/O and Per-Node Validation ───────────────────────

def cat6_mandatory_io(results, pd_dir, flows):
    suite = 'static'
    category = 'cat6_mandatory_io'

    for flow in flows:
        config_file = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'node_configs', f'{flow}_config.tcl')
        if not os.path.exists(config_file):
            continue
        with open(config_file) as f:
            content = f.read()
        if 'mandatory_input_groups' in content or 'critical_files' in content:
            results.passed(suite, category, f'{flow}: mandatory input validation defined')
        else:
            results.skipped(suite, category, f'{flow}: no mandatory_input_groups/critical_files')
        if 'mandatory_outputs' in content:
            results.passed(suite, category, f'{flow}: mandatory_outputs defined')
        else:
            results.skipped(suite, category, f'{flow}: no mandatory_outputs')
        if 'release_types' in content:
            results.passed(suite, category, f'{flow}: release_types defined')
        else:
            results.failed(suite, category, f'{flow}: release_types missing')

    release_config = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'release_config.tcl')
    if os.path.exists(release_config):
        with open(release_config) as f:
            rc = f.read()
        for flow in flows:
            if f'{flow},' in rc:
                results.passed(suite, category, f'release_config: {flow} has release exit files')
            else:
                results.failed(suite, category, f'release_config: {flow} missing')
        for key in ['flow_input_handshake', 'phase_criteria', 'milestone_flow_map']:
            if key in rc:
                results.passed(suite, category, f'release_config: {key} defined')
            else:
                results.failed(suite, category, f'release_config: {key} missing')
    else:
        results.failed(suite, category, 'release_config.tcl missing')

    release_utils = os.path.join(pd_dir, 'utils', 'utilities', 'v1.0.0', 'release_utils.tcl')
    if os.path.exists(release_utils):
        with open(release_utils) as f:
            ru = f.read()
        for proc in ['init', 'validate_mandatory_files', 'resolve']:
            if f'proc {proc}' in ru:
                results.passed(suite, category, f'release_utils: proc {proc} defined')
            else:
                results.failed(suite, category, f'release_utils: proc {proc} missing')
        env_refs = 0
        for line in ru.split('\n'):
            stripped = line.strip()
            if stripped.startswith('#'):
                continue
            if re.search(r'CBFLOW_RELEASE_TAG|CBFLOW_RELEASE_PHASE|CBFLOW_RELEASE_PATH', stripped):
                env_refs += 1
        if env_refs == 0:
            results.passed(suite, category, 'release_utils: zero env var lookups for release data')
        else:
            results.failed(suite, category, f'release_utils: {env_refs} env var lookups found')
    else:
        results.failed(suite, category, 'release_utils.tcl missing')

    inputs_count = 0
    resolve_count = 0
    for inputs_file in Path(os.path.join(pd_dir, 'cmds')).rglob('inputs_*.tcl'):
        if 'handler' in inputs_file.name or 'subnode' in inputs_file.name:
            continue
        inputs_count += 1
        with open(inputs_file) as f:
            if 'resolve_inputs' in f.read():
                resolve_count += 1
    if inputs_count > 0:
        results.passed(suite, category, 'Input resolution coverage',
                       f'{resolve_count}/{inputs_count} inputs files have resolve_inputs')
        if resolve_count < inputs_count:
            results.failed(suite, category, 'Input resolution: some inputs files missing resolve_inputs',
                           f'{inputs_count - resolve_count} missing')


# ── Category 7: Log Parsing and Error Halt ──────────────────────────────────

def cat7_log_parsing(results, pd_dir, flows):
    suite = 'static'
    category = 'cat7_log_parsing'

    log_viewer = os.path.join(pd_dir, 'utils', 'commands', 'log_viewer.py')
    if os.path.exists(log_viewer):
        with open(log_viewer) as f:
            lv = f.read()
        for pattern in ['Error:', 'WARNING:', '**ERROR', 'FATAL']:
            if pattern in lv:
                results.passed(suite, category, f'log_viewer: pattern "{pattern}" recognized')
            else:
                results.skipped(suite, category, f'log_viewer: pattern "{pattern}" not found')
        results.passed(suite, category, 'log_viewer.py exists')
    else:
        results.failed(suite, category, 'log_viewer.py missing')

    if os.path.exists(os.path.join(pd_dir, 'utils', 'commands', 'validation_cmd.py')):
        results.passed(suite, category, 'validation_cmd.py exists')
    else:
        results.failed(suite, category, 'validation_cmd.py missing')

    exec_all_count = 0
    total = 0
    for cmd_file in Path(os.path.join(pd_dir, 'cmds')).rglob('*.tcl'):
        if 'handler' in cmd_file.name or 'subnode' in cmd_file.name or 'scripts' in str(cmd_file):
            continue
        total += 1
        with open(cmd_file) as f:
            if 'flow_exec_all' in f.read():
                exec_all_count += 1
    results.passed(suite, category, 'flow_exec_all coverage', f'{exec_all_count}/{total} files')

    utils_tcl = os.path.join(pd_dir, 'utils', 'utilities', 'v1.0.0', 'utils.tcl')
    if os.path.exists(utils_tcl):
        with open(utils_tcl) as f:
            ut = f.read()
        for proc in ['handle_error', 'handle_warning', 'handle_info', 'flow_proc', 'flow_exec_all']:
            if f'proc {proc}' in ut:
                results.passed(suite, category, f'utils.tcl: {proc} defined')
            else:
                results.failed(suite, category, f'utils.tcl: {proc} missing')
    else:
        results.failed(suite, category, 'utils.tcl missing')

    exit_dir = os.path.join(pd_dir, 'config', 'exit', 'v1.0.0')
    if os.path.isdir(exit_dir):
        milestones = [f.replace('_config.tcl', '') for f in os.listdir(exit_dir)
                      if f.endswith('_config.tcl') and f not in (
                          'waiver_config.tcl', 'threshold_overrides.tcl', 'remediation_config.tcl')]
        results.passed(suite, category, 'Exit milestones', f'{len(milestones)} defined')
    else:
        results.failed(suite, category, 'Exit config directory missing')

    checklist = os.path.join(pd_dir, 'utils', 'commands', 'checklist_cmd.py')
    if os.path.exists(checklist):
        with open(checklist) as f:
            cc = f.read()
        for cmd in ['cmd_add_check', 'cmd_remove_check', 'cmd_list_checks', 'cmd_status', 'cmd_signoff']:
            if cmd in cc:
                results.passed(suite, category, f'checklist_cmd: {cmd} defined')
            else:
                results.failed(suite, category, f'checklist_cmd: {cmd} missing')
    else:
        results.failed(suite, category, 'checklist_cmd.py missing')


# ── Category 8: Cross-Cutting Checks ────────────────────────────────────────

def cat8_cross_cutting(results, pd_dir, flows):
    suite = 'static'
    category = 'cat8_cross_cutting'

    bug_count = 0
    for tcl_file in Path(os.path.join(pd_dir, 'cmds')).rglob('*.tcl'):
        if 'handler' in tcl_file.name or 'subnode' in tcl_file.name:
            continue
        with open(tcl_file) as f:
            content = f.read()
        matches = re.findall(r'\$::run_dir(?!/)', content)
        real_bugs = [m for m in matches if '::env' not in content[max(0, content.find(m) - 30):content.find(m)]]
        bug_count += len(real_bugs)
    if bug_count == 0:
        results.passed(suite, category, 'No $::run_dir bugs across all command files')
    else:
        results.failed(suite, category, f'{bug_count} $::run_dir references found')

    for pattern in ['FCT', 'PHYV']:
        count = 0
        for f in Path(os.path.join(pd_dir, 'config', 'flow', 'v1.0.0')).rglob('*.tcl'):
            with open(f) as fh:
                if re.search(rf'\b{pattern}\b', fh.read()):
                    count += 1
        if count == 0:
            results.passed(suite, category, f'No {pattern} references in active flow configs')
        else:
            results.failed(suite, category, f'{count} files still reference {pattern}')

    for module in ['email_cmd.py', 'autoppt_cmd.py']:
        if os.path.exists(os.path.join(pd_dir, 'utils', 'commands', module)):
            results.passed(suite, category, f'{module} exists')
        else:
            results.failed(suite, category, f'{module} missing')

    for comp in ['cbflow.bash', '_cbflow']:
        if os.path.exists(os.path.join(pd_dir, 'completions', comp)):
            results.passed(suite, category, f'Completion: {comp} exists')
        else:
            results.failed(suite, category, f'Completion: {comp} missing')

    for proj in ['phoenix', 'ravendrive']:
        proj_root = os.path.join(pd_dir, 'config', 'project', proj)
        if not os.path.isdir(proj_root):
            continue
        for cfg_file in Path(proj_root).rglob('*_config.tcl'):
            with open(cfg_file) as f:
                if 'release,path' in f.read():
                    results.passed(suite, category, f'{proj}: project(release,path) defined')
                    break


# ── Category 9: Dead-Code & Cross-Reference Audit ───────────────────────────
#
# Looks for the bug classes we keep finding when flows get copy-pasted from
# PNR into other flows: subnode handlers pointing at non-existent or wrong-
# stage cmd files, STAGE_NAME inside a cmd file not matching its filename,
# undefined $flow_dir (should be $::env(FLOW_DIR)), broken if-source-puts-
# exit fall-through, orphan cmd files whose stage isn't in the flow, and
# stale header comments mentioning the wrong flow.

_HANDLER_CMD_RE = re.compile(r'set\s+cmd_file\s+"([^"]+)"')
_HANDLER_STAGE_RE = re.compile(r'set\s+stage_name\s+"([^"]+)"', re.IGNORECASE)
_CMD_STAGE_NAME_RE = re.compile(r'set\s+STAGE_NAME\s+"([^"]+)"', re.IGNORECASE)
_FLOW_DIR_RE = re.compile(r'\$flow_dir(?!\w)')
_DEAD_IFELSE_RE = re.compile(
    r'if\s*\{[^}]*\bfile\s+exists[^}]*\}\s*\{[^}]*?source[^}]*?'
    r'(?:puts\s+"ERROR|handle_error)[^}]*?exit\s+1',
    re.DOTALL,
)
_HEADER_FLOW_RE = re.compile(r'^#\s*(?:CBflow\s+)?([A-Z][A-Z_]+)\b', re.MULTILINE)
# NEW: foreach step list { ... [catch {$step} ...] ... } — calls flow_proc names as Tcl commands.
# Real bug we hit in FP/cadence/innovus where flow_procs registered via flow_proc never get
# dispatched correctly because $step isn't a real Tcl proc.
_BUGGY_FOREACH_STEP_RE = re.compile(
    r'foreach\s+step\b[^{]*\{[^}]*?\}\s*\{[^{}]*?\bcatch\s*\{\s*\$step\b',
    re.DOTALL,
)
# Looser variant: any catch {$step} inside the file is suspicious.
_CATCH_STEP_RE = re.compile(r'\bcatch\s*\{\s*\$step\b')
# flow_proc body contains `exit 1` followed by more code that reads a same-array variable.
# test_mode intercepts exit, then the unreachable code runs and crashes on the missing var.
_EXIT_DEAD_READ_RE = re.compile(
    r'handle_error[^\n]*\n\s*exit\s+\d+\s*\n(?:\s*\}\s*\n)?\s*[^\}\#].*?\$([a-z_]+)\(',
    re.DOTALL,
)
# Files that define flow_procs but never call flow_exec_all (or flow_exec_all-equivalent
# dispatch). Bug surface: procs registered but never run.
_FLOW_PROC_DEF_RE = re.compile(r'\bflow_proc\s+\w+\s+\{', re.MULTILINE)
# Valid dispatch patterns:
#   - `flow_exec_all` (runs all registered procs in order)
#   - `flow_exec <name>` (explicit single-proc dispatch)
# Either is acceptable; absence of both is the bug.
# `flow_exec_all` is unambiguous wherever it appears.
# `flow_exec NAME` can appear inside `if {...} { flow_exec NAME }` constructs
# at the file's top level — so match anywhere (after stripping proc bodies).
_FLOW_DISPATCH_RE = re.compile(
    r'\b(?:flow_exec_all|flow_exec\s+\w+)\b'
)


def _has_top_level_dispatch(text):
    """Strip all flow_proc bodies, then check for any flow_exec_all or
    `flow_exec <name>` at top level. This avoids matching `flow_exec X`
    that appears INSIDE another flow_proc body (which is just calling a
    sibling, not dispatching at file scope)."""
    # Greedy brace-matched strip of flow_proc bodies
    out = []
    i = 0
    while i < len(text):
        m = re.search(r'\bflow_proc\s+\w+\s+\{', text[i:])
        if not m:
            out.append(text[i:])
            break
        # append everything before the proc body
        out.append(text[i:i + m.start()])
        # skip the proc body via brace-matching
        j = i + m.end()
        depth = 1
        while j < len(text) and depth > 0:
            if text[j] == '{': depth += 1
            elif text[j] == '}': depth -= 1
            j += 1
        i = j
    stripped = ''.join(out)
    return bool(_FLOW_DISPATCH_RE.search(stripped))


def _parse_flow_stages(pd_dir, flow):
    """Return the canonical stage list for a flow (digits stripped, e.g.
    'export_db1' → 'export_db'). Empty list if config missing."""
    cfg = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0',
                       'node_configs', f'{flow}_config.tcl')
    if not os.path.exists(cfg):
        return []
    with open(cfg) as f:
        content = f.read()
    m = re.search(r'stages\s+\{([^}]+)\}', content)
    if not m:
        return []
    return [s.rstrip('0123456789') for s in m.group(1).split()]


def _resolve_handler_cmd_path(pd_dir, raw_cmd, flow, vendor, tool):
    """Resolve $::env(FLOW_DIR), $_tool_ver, and per-tool VERSION env vars
    to the on-disk path the handler is going to source.

    Defaults to v1.0.0 where the version isn't specified explicitly (the
    convention used everywhere in this tree).
    """
    p = raw_cmd
    p = p.replace('$::env(FLOW_DIR)', pd_dir)
    p = p.replace('${::env(FLOW_DIR)}', pd_dir)
    p = p.replace('$_tool_ver', 'v1.0.0')
    p = p.replace('${_tool_ver}', 'v1.0.0')
    p = re.sub(r'\$::env\([A-Z_]+_VERSION\)', 'v1.0.0', p)
    p = re.sub(r'\$\{::env\([A-Z_]+_VERSION\)\}', 'v1.0.0', p)
    return p


def _tool_dirs_for(pd_dir, flow):
    """Yield (vendor, tool, dir) for every concrete cmds/<FLOW>/<vendor>/<tool>/v1.0.0/ that exists."""
    flow_root = os.path.join(pd_dir, 'cmds', flow)
    if not os.path.isdir(flow_root):
        return
    for vendor in sorted(os.listdir(flow_root)):
        vroot = os.path.join(flow_root, vendor)
        if not os.path.isdir(vroot):
            continue
        for tool in sorted(os.listdir(vroot)):
            d = os.path.join(vroot, tool, 'v1.0.0')
            if os.path.isdir(d):
                yield vendor, tool, d


def _resolve_flow_tool(pd_dir, flow, content):
    """Find a (vendor, tool) pair for a flow whose cmds dir actually exists.

    Some flows put tool,vendor/tool,name in the main <FLOW>_config.tcl;
    others (STA, LEC, EMIR, PV, CLP, POPT, ECO) split tool data into
    `<FLOW>_<tool>_config.tcl`. POPT has multiple tools declared but only
    one cmds dir; pick the one that exists on disk.
    """
    def _cmds_exists(v, t):
        return os.path.isdir(os.path.join(pd_dir, 'cmds', flow, v, t, 'v1.0.0'))

    vm = re.search(r'tool,vendor\s+"(\w+)"', content)
    tm = re.search(r'tool,name\s+"(\w+)"', content)
    if vm and tm and _cmds_exists(vm.group(1), tm.group(1)):
        return vm.group(1), tm.group(1)

    node_dir = os.path.join(pd_dir, 'config', 'flow', 'v1.0.0', 'node_configs')
    if os.path.isdir(node_dir):
        pat = re.compile(rf'^{re.escape(flow)}_(\w+)_config\.tcl$')
        for fname in sorted(os.listdir(node_dir)):
            if not pat.match(fname):
                continue
            with open(os.path.join(node_dir, fname)) as f:
                tc = f.read()
            v2 = re.search(r'tool,vendor\s+"(\w+)"', tc)
            t2 = re.search(r'tool,name\s+"(\w+)"', tc)
            if v2 and t2 and _cmds_exists(v2.group(1), t2.group(1)):
                return v2.group(1), t2.group(1)
    return '', ''


# Synthetic stages: present as cmd files everywhere but not in any flow's
# `stages {...}` list. Known convention; not orphans.
_SYNTHETIC_STAGES = frozenset({
    'inputs',           # bundled input resolver
    'validate',         # post-stage validator
    'release_data',     # release packager (some flows put it in stages, some don't)
    'export_data',      # FP/SYNTH export
})

# Known STAGE_NAME aliases — a cmd file whose filename includes a descriptive
# suffix (e.g. `timing_scenario_pt.tcl`) intentionally sets STAGE_NAME to the
# parent stage. Filename → expected STAGE_NAME.
_STAGE_NAME_ALIASES = {
    'timing_scenario': 'timing',   # MMMC per-scenario template under timing1
    'timing_setup':    'timing',   # setup-mode timing analysis template
    'timing_hold':     'timing',   # hold-mode timing analysis template
}


def _stage_from_filename(stem, tool):
    """Return the stage prefix of a cmd-file name.

    The naïve approach (rfind('_')) breaks for multi-token tool names like
    'conformal_lp', 'vc_lp', 'power_compiler'. We strip the exact `_<tool>`
    suffix when present, falling back to rfind('_').
    """
    suf = '_' + tool
    if stem.endswith(suf):
        return stem[:-len(suf)]
    i = stem.rfind('_')
    return stem[:i] if i > 0 else stem


def cat9_dead_code_audit(results, pd_dir, flows):
    suite = 'static'
    category = 'cat9_dead_code_audit'

    for flow in flows:
        flow_stages = set(_parse_flow_stages(pd_dir, flow))
        if not flow_stages:
            results.skipped(suite, category, f'{flow}: no flow stages parsed')
            continue

        for vendor, tool, tdir in _tool_dirs_for(pd_dir, flow):
            scope = f'{flow}/{vendor}/{tool}'

            # ── Check 1 & 2: handler ↔ cmd-file integrity + STAGE_NAME match ──

            for handler in sorted(Path(tdir).glob('*_subnode_handler.tcl')):
                rel = handler.name
                try:
                    text = handler.read_text(errors='replace')
                except OSError as e:
                    results.failed(suite, category, f'{scope}/{rel}: read failed',
                                   f'{type(e).__name__}: {e}')
                    continue

                handler_stage = ''
                hm = _HANDLER_STAGE_RE.search(text)
                if hm:
                    handler_stage = hm.group(1)

                cm = _HANDLER_CMD_RE.search(text)
                if not cm:
                    # Handler has no cmd_file at all; not flagged (some
                    # handlers are pure scaffolding).
                    continue

                raw = cm.group(1)
                resolved = _resolve_handler_cmd_path(pd_dir, raw, flow, vendor, tool)
                if not os.path.exists(resolved):
                    results.failed(suite, category,
                                   f'{scope}/{rel}: cmd_file references missing path',
                                   f'{raw} → {resolved}')
                    continue
                results.passed(suite, category, f'{scope}/{rel}: cmd_file resolves')

                # Compare STAGE_NAME in target cmd file vs handler's stage_name.
                if handler_stage:
                    try:
                        target_text = open(resolved, errors='replace').read()
                    except OSError:
                        continue
                    tm = _CMD_STAGE_NAME_RE.search(target_text)
                    if tm and tm.group(1) != handler_stage:
                        results.failed(
                            suite, category,
                            f'{scope}/{rel}: STAGE_NAME mismatch',
                            f'handler stage_name="{handler_stage}", '
                            f'{os.path.basename(resolved)} STAGE_NAME="{tm.group(1)}"')

            # ── Check 3 & 4 & 5 & 6: per cmd file (not handlers) ──

            for cmdf in sorted(Path(tdir).glob('*.tcl')):
                if cmdf.name.endswith('_subnode_handler.tcl'):
                    continue
                rel = cmdf.name
                try:
                    text = cmdf.read_text(errors='replace')
                except OSError:
                    continue

                # Filename → expected stage. Strip the exact `_<tool>` suffix
                # so multi-token tools (conformal_lp, power_compiler) parse right.
                expected_stage = _stage_from_filename(cmdf.stem, tool)

                # Check 2 (cmd file STAGE_NAME ↔ filename)
                # Honour known aliases — some files name themselves after a
                # sub-view (e.g. timing_scenario) but legitimately set
                # STAGE_NAME to the parent stage.
                allowed = {expected_stage}
                if expected_stage in _STAGE_NAME_ALIASES:
                    allowed.add(_STAGE_NAME_ALIASES[expected_stage])
                sm = _CMD_STAGE_NAME_RE.search(text)
                if sm:
                    actual = sm.group(1)
                    if actual not in allowed:
                        results.failed(
                            suite, category,
                            f'{scope}/{rel}: STAGE_NAME does not match filename',
                            f'STAGE_NAME="{actual}" expected one of {sorted(allowed)}')
                    else:
                        results.passed(suite, category, f'{scope}/{rel}: STAGE_NAME ok')

                # Check 3 ($flow_dir undefined)
                hits = []
                for i, line in enumerate(text.splitlines(), 1):
                    if _FLOW_DIR_RE.search(line):
                        hits.append(i)
                if hits:
                    results.failed(
                        suite, category,
                        f'{scope}/{rel}: $flow_dir (undefined) used',
                        f'lines {hits} — should be $::env(FLOW_DIR)')

                # Check 4 (dead if-source-puts-exit fall-through)
                if _DEAD_IFELSE_RE.search(text):
                    results.failed(
                        suite, category,
                        f'{scope}/{rel}: dead if-source-puts-exit pattern',
                        'success path falls through into error+exit — needs else branch')

                # Check 7 (NEW): foreach step list { ... catch {$step} ... } —
                # invokes flow_proc names as Tcl commands. Real bug in the FP
                # innovus tree until we fixed it.
                if _CATCH_STEP_RE.search(text) and _FLOW_PROC_DEF_RE.search(text):
                    results.failed(
                        suite, category,
                        f'{scope}/{rel}: foreach step + catch {{$step}} pattern',
                        'flow_procs registered via `flow_proc` are not Tcl commands; '
                        'use `flow_exec_all` instead of `foreach step {...} {catch {$step}}`')

                # Check 8 (NEW): handle_error/exit followed by unreachable code that
                # reads same-namespace variable. In test_mode exit is intercepted
                # and the dead code runs, exposing missing variables.
                # Heuristic: just find `handle_error ...\n exit \d` followed by
                # a line that still uses $arr( inside the same proc.
                for proc_match in re.finditer(r'flow_proc\s+(\w+)\s+\{', text):
                    proc_name = proc_match.group(1)
                    proc_start = proc_match.end()
                    # find matching close brace for this proc
                    depth = 1
                    i = proc_start
                    while i < len(text) and depth > 0:
                        if text[i] == '{': depth += 1
                        elif text[i] == '}': depth -= 1
                        i += 1
                    proc_body = text[proc_start:i]
                    # Look for exit \d followed by $arr( read
                    if re.search(r'\bexit\s+\d+\s*\n[^{}#]*?\$[a-z_]+\(', proc_body, re.DOTALL):
                        # Only flag if it's an actual array-read AFTER exit, not
                        # inside a nested block.
                        m = re.search(r'\bexit\s+\d+\b', proc_body)
                        if m:
                            tail = proc_body[m.end():]
                            if re.search(r'\$[a-z_]+\([^)]+\)', tail):
                                results.failed(
                                    suite, category,
                                    f'{scope}/{rel}: dead code after exit in flow_proc {proc_name}',
                                    'test_mode intercepts `exit`; code after it runs and may '
                                    'crash on missing variables. Use `return` instead of `exit N`.')
                                break

                # Check 10 (NEW): brace imbalance — broken Tcl syntax. Often
                # `flow_exec_all` is present in the text but trapped inside an
                # unclosed proc body. Detected separately so the message is clear.
                opens = text.count('{')
                closes = text.count('}')
                braces_balanced = (opens == closes)
                if not braces_balanced:
                    results.failed(
                        suite, category,
                        f'{scope}/{rel}: unbalanced braces',
                        f'{opens} opens vs {closes} closes (diff {opens-closes}) — '
                        f'fix the missing/extra braces; `flow_exec_all` may be trapped '
                        f'inside an unclosed proc body')

                # Check 9 (NEW): file defines flow_procs but never invokes
                # dispatch. Procs registered but never run. Skip if braces are
                # imbalanced (check 10 already flagged the real bug).
                has_flow_procs = bool(_FLOW_PROC_DEF_RE.search(text))
                if (has_flow_procs and braces_balanced
                        and not _has_top_level_dispatch(text)
                        and not _CATCH_STEP_RE.search(text)):
                    results.failed(
                        suite, category,
                        f'{scope}/{rel}: defines flow_procs but no top-level dispatch',
                        'add `flow_exec_all` (or top-level `flow_exec <name>`) to run them')

                # Check 5 (orphan cmd file: stage not in flow's stage list)
                # Informational only — many flows have legitimate sub-view
                # files (e.g. STA timing_scenario/timing_hold, MMMC setup,
                # DMSA workers) that aren't listed as top-level stages but
                # are correctly sourced at runtime. Emit as SKIP so the
                # finding shows up if --verbose but doesn't fail the suite.
                if (expected_stage
                        and expected_stage not in flow_stages
                        and expected_stage not in _SYNTHETIC_STAGES):
                    results.skipped(
                        suite, category,
                        f'{scope}/{rel}: stage not in flow list',
                        f'expected_stage="{expected_stage}" not in {flow}.stages '
                        f'(may be a sub-view or pre-stage file)')

                # Check 6 (header comment claims a different flow)
                hm2 = _HEADER_FLOW_RE.search(text[:600])
                if hm2:
                    claimed = hm2.group(1)
                    # Skip generic words that aren't flow names.
                    if claimed not in ('CBFlow', 'CBFLOW', 'CB', 'TCL', 'INFO', 'ERROR',
                                       'WARNING') and claimed != flow:
                        # Only flag if the claimed token is a known flow type.
                        if claimed in {'SYNTH', 'FP', 'PNR', 'STA', 'LEC', 'EMIR',
                                       'PV', 'ECO', 'CLP', 'POPT', 'FCFP', 'SYNTH_PNR'}:
                            results.failed(
                                suite, category,
                                f'{scope}/{rel}: header comment claims wrong flow',
                                f'comment says "{claimed}" but file lives under {flow}/')


# ── Registry ────────────────────────────────────────────────────────────────

CATEGORIES = {
    1: ('Workspace & Run Creation', cat1_workspace_creation),
    2: ('Makefile & Handler Validation', cat2_makefiles_handlers),
    3: ('Override Setup & Config', cat3_override_mechanism),
    4: ('LSF Management', cat4_lsf_management),
    5: ('MMMC Config & Scenarios', cat5_mmmc_config),
    6: ('Mandatory I/O & Validation', cat6_mandatory_io),
    7: ('Log Parsing & Error Halt', cat7_log_parsing),
    8: ('Cross-Cutting Checks', cat8_cross_cutting),
    9: ('Dead-Code & Cross-Reference Audit', cat9_dead_code_audit),
}


def run(results, pd_dir, flows, categories=None):
    """Run static categories. categories=None runs all."""
    selected = sorted(categories or CATEGORIES.keys())
    for cat_num in selected:
        if cat_num not in CATEGORIES:
            continue
        _, func = CATEGORIES[cat_num]
        func(results, pd_dir, flows)
