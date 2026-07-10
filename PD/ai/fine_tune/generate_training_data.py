#!/usr/bin/env python3
"""
Generate fine-tuning training data from CBflow docs, code, and EDA guides.
Converts all knowledge into instruction-response pairs (JSONL format).

Usage:
    python generate_training_data.py

Output: data/cbflow_training.jsonl (2000-5000 examples)
"""

import json
import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_CORE = os.path.dirname(os.path.dirname(SCRIPT_DIR))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'data')
os.makedirs(OUTPUT_DIR, exist_ok=True)

examples = []


def add(instruction, output, category="general"):
    examples.append({
        "instruction": instruction,
        "output": output,
        "category": category,
    })


# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 1: CBflow Commands (exact command syntax)
# ═══════════════════════════════════════════════════════════════════════════════

def generate_cbflow_commands():
    """Generate Q&A pairs for every cbflow command."""

    # Workspace commands
    add("How do I create a new CBflow run?",
        'cbflow workspace create --config user_config.tcl', "command")
    add("Create a SYNTH_PNR run named test1",
        'cbflow workspace create --config uc_SYNTH_PNR.tcl', "command")
    add("How to list all runs in workspace?",
        'cbflow workspace list-runs', "command")
    add("Show workspace status",
        'cbflow workspace status', "command")
    add("Generate a user config template for PNR flow",
        'cbflow workspace template --flow PNR', "command")
    add("Delete all runs in workspace",
        'cbflow workspace clean --confirm', "command")

    # Run commands
    add("Run the complete flow",
        'cbflow run all', "command")
    add("Run a single stage named place1",
        'cbflow run stage --name place1', "command")
    add("Check the status of current run",
        'cbflow run status', "command")
    add("Show detailed status with subnodes",
        'cbflow run status --details', "command")
    add("Retrace from CTS stage onwards",
        'cbflow run retrace --from cts1', "command")
    add("Bypass the signoff stage",
        'cbflow run bypass --stages signoff1', "command")
    add("Force re-run the place stage",
        'cbflow run force --stages place1', "command")
    add("Add a custom node named place2 of type place after place1",
        'cbflow run add-node --node place2 --type place --dep place1', "command")
    add("Create a branch named timing_fix from cts1",
        'cbflow run create-branch --branch timing_fix --from cts1', "command")
    add("List all branches",
        'cbflow run list-branches', "command")
    add("Show the dependency graph",
        'cbflow run show-graph', "command")
    add("Show dependency graph with subnodes",
        'cbflow run show-graph --detail', "command")
    add("Release with tag PLACE_EXIT",
        'cbflow run release --tag PLACE_EXIT', "command")
    add("Check release readiness for BTO",
        'cbflow run release-check --tag BTO --project bumblebee --phase P2', "command")
    add("Lock permissions for production",
        'cbflow run release-lock', "command")
    add("Unlock permissions for development",
        'cbflow run release-lock --unlock', "command")
    add("Launch the web dashboard",
        'cbflow run gui', "command")

    # Flow commands
    add("List all available flow types",
        'cbflow flow types', "command")
    add("Show information about PNR flow",
        'cbflow flow info --flow PNR', "command")
    add("List stages in SYNTH_PNR flow",
        'cbflow flow stages --flow SYNTH_PNR', "command")
    add("Check CBflow installation",
        'cbflow flow check', "command")

    # SmartGenie commands
    add("Start the SmartGenie AI server",
        'cbflow smartgenie serve', "command")
    add("Ingest all knowledge into the database",
        'cbflow smartgenie ingest --all', "command")
    add("Search the knowledge base for hold violations",
        'cbflow smartgenie search "hold violation fix"', "command")
    add("Show usage statistics",
        'cbflow smartgenie usage', "command")
    add("Create a customer bundle",
        'cbflow bundle', "command")


# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 2: CBflow Flow Knowledge
# ═══════════════════════════════════════════════════════════════════════════════

def generate_flow_knowledge():
    """Generate Q&A about CBflow flows from actual config files."""

    # Read flow types
    flow_config = os.path.join(CBFLOW_CORE, 'config', 'flow', 'v1.0.0', 'flow_config.tcl')
    if os.path.exists(flow_config):
        with open(flow_config) as f:
            content = f.read()
        m = re.search(r'flow\(types\)\s+\{([^}]+)\}', content)
        if m:
            flows = m.group(1).split()
            add("What flows are available in CBflow?",
                f"CBflow supports {len(flows)} flows: {', '.join(flows)}", "flow")
            add("List all CBflow flow types",
                '\n'.join(f"- {f}" for f in flows), "flow")

    # Read each flow's stages from node configs
    node_dir = os.path.join(CBFLOW_CORE, 'config', 'flow', 'v1.0.0', 'node_configs')
    if os.path.isdir(node_dir):
        for cfg_file in Path(node_dir).glob('*_config.tcl'):
            flow_name = cfg_file.stem.replace('_config', '')
            with open(cfg_file) as f:
                content = f.read()
            m = re.search(r'stages\s+\{([^}]+)\}', content)
            if m:
                stages = m.group(1).split()
                add(f"What are the stages in {flow_name} flow?",
                    f"{flow_name} has {len(stages)} stages: {', '.join(stages)}", "flow")
                add(f"How many stages does {flow_name} have?",
                    f"{flow_name} has {len(stages)} stages.", "flow")

            # Tool info
            m = re.search(r'tool,vendor\s+"([^"]+)"', content)
            vendor = m.group(1) if m else ""
            m = re.search(r'tool,name\s+"([^"]+)"', content)
            tool = m.group(1) if m else ""
            if vendor and tool:
                add(f"What tool does {flow_name} use?",
                    f"{flow_name} uses {vendor} {tool}.", "flow")

    # Read project configs
    proj_dir = os.path.join(CBFLOW_CORE, 'config', 'project')
    if os.path.isdir(proj_dir):
        for proj in os.listdir(proj_dir):
            proj_cfg = os.path.join(proj_dir, proj, 'v1.0.0', f'{proj}_config.tcl')
            if os.path.exists(proj_cfg):
                with open(proj_cfg) as f:
                    content = f.read()
                m = re.search(r'project\(block_list\)\s+"([^"]*)"', content)
                if m:
                    blocks = m.group(1).split()
                    add(f"What blocks are available in project {proj}?",
                        f"Project '{proj}' has {len(blocks)} blocks: {', '.join(blocks)}", "flow")


# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 3: EDA Knowledge (from generated docs)
# ═══════════════════════════════════════════════════════════════════════════════

def generate_eda_knowledge():
    """Generate Q&A pairs from EDA guide documents."""
    guides_dir = os.path.join(os.path.dirname(SCRIPT_DIR), 'eda_guides')
    if not os.path.isdir(guides_dir):
        return

    for md_file in Path(guides_dir).glob('*.md'):
        with open(md_file, errors='ignore') as f:
            content = f.read()

        title = md_file.stem.replace('_', ' ').title()

        # Extract sections (## headers)
        sections = re.split(r'\n##\s+', content)
        for section in sections[1:]:  # Skip before first header
            lines = section.strip().split('\n')
            if not lines:
                continue
            header = lines[0].strip()
            body = '\n'.join(lines[1:]).strip()
            if len(body) > 100:
                # Create Q&A from section
                add(f"Explain {header.lower()} in {title.lower()}",
                    body[:1500], "eda")

        # Create a summary Q&A for the whole doc
        if len(content) > 200:
            summary = content[:2000]
            add(f"What is {title.lower()}?",
                summary[:1000], "eda")


# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 4: Conversations (multi-turn)
# ═══════════════════════════════════════════════════════════════════════════════

def generate_conversations():
    """Generate realistic multi-turn conversation examples."""

    convos = [
        {
            "conversations": [
                {"role": "user", "content": "Create a SYNTH_PNR run named test1 for block cpu_core"},
                {"role": "assistant", "content": "Creating SYNTH_PNR run 'test1' for cpu_core...\n\nRun created successfully: P0_run_SYNTH_PNR_test1"},
                {"role": "user", "content": "Now run it"},
                {"role": "assistant", "content": "Running SYNTH_PNR flow...\n\nAll 13 stages completed: PASS"},
                {"role": "user", "content": "Check status"},
                {"role": "assistant", "content": "SYNTH_PNR Run Status:\n- 13/13 stages DONE\n- Result: PASS\n- All stages: rtl1, sdc1, upf1, init_design1, synthesis1, place1, cts1, cts_opt1, route1, pro1, signoff1, export_data1, release_data1"},
            ]
        },
        {
            "conversations": [
                {"role": "user", "content": "What blocks are available in bumblebee?"},
                {"role": "assistant", "content": "Project 'bumblebee' has 3 blocks:\n- cpu_core\n- memory_ctrl\n- io_ctrl"},
                {"role": "user", "content": "Create a run for memory_ctrl"},
                {"role": "assistant", "content": "Creating SYNTH_PNR run for memory_ctrl...\n\nRun created: P0_run_SYNTH_PNR_run1"},
            ]
        },
        {
            "conversations": [
                {"role": "user", "content": "How to fix hold violations after CTS?"},
                {"role": "assistant", "content": "Hold violation fixes after CTS:\n- Insert buffers/delay cells on short paths\n- Enable CCD (concurrent clock-data optimization)\n- Use useful skew to borrow slack from setup\n- Check hold-critical corners (FF, high voltage, cold)\n- Command: set_app_options -name clock_opt.hold_control_effort -value high"},
            ]
        },
    ]

    for convo in convos:
        examples.append({"conversations": convo["conversations"], "category": "conversation"})


# ═══════════════════════════════════════════════════════════════════════════════
# CATEGORY 5: Tool Use Examples
# ═══════════════════════════════════════════════════════════════════════════════

def generate_tool_use():
    """Generate tool-calling training examples."""

    tool_examples = [
        ("Create a SYNTH run named varun for cpu_core",
         '{"tool": "bash", "args": {"command": "cbflow workspace create --config uc_SYNTH_varun.tcl"}}'),
        ("Run the PNR flow",
         '{"tool": "bash", "args": {"command": "cd P0_run_PNR_test1 && cbflow run all"}}'),
        ("Check status of SYNTH_PNR run",
         '{"tool": "bash", "args": {"command": "cd P0_run_SYNTH_PNR_test1 && cbflow run status"}}'),
        ("Read the flow config file",
         '{"tool": "read_file", "args": {"path": "config/flow/v1.0.0/flow_config.tcl"}}'),
        ("Search for hold violation fixes",
         '{"tool": "search_kb", "args": {"query": "hold violation fix CTS"}}'),
    ]

    for instruction, output in tool_examples:
        add(instruction, output, "tool_use")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    print("Generating training data...")

    generate_cbflow_commands()
    print(f"  CBflow commands: {len(examples)} examples")

    n = len(examples)
    generate_flow_knowledge()
    print(f"  Flow knowledge: {len(examples) - n} examples")

    n = len(examples)
    generate_eda_knowledge()
    print(f"  EDA knowledge: {len(examples) - n} examples")

    n = len(examples)
    generate_conversations()
    print(f"  Conversations: {len(examples) - n} examples")

    n = len(examples)
    generate_tool_use()
    print(f"  Tool use: {len(examples) - n} examples")

    # Write JSONL
    output_file = os.path.join(OUTPUT_DIR, 'cbflow_training.jsonl')
    with open(output_file, 'w') as f:
        for ex in examples:
            f.write(json.dumps(ex) + '\n')

    print(f"\n  Total: {len(examples)} training examples")
    print(f"  Output: {output_file}")

    # Stats by category
    cats = {}
    for ex in examples:
        c = ex.get('category', 'unknown')
        cats[c] = cats.get(c, 0) + 1
    print(f"\n  By category:")
    for c, n in sorted(cats.items()):
        print(f"    {c}: {n}")


if __name__ == '__main__':
    main()
