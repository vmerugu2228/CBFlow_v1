"""Spec-to-GDS sign-off chain status for the SmartGrid project page.

project(signoff_chain,<phase>) (global project config) lists the chain's
stages in order; a stage is "<step> <tag>" pairs that run in parallel
(workarea/run_spec2gds.sh). A step's flow is the longest registered flow type
its name starts with (SYNTH, ATPG_pre -> ATPG, M1_EXEC). Per block, a step is
done when <release,path>/<phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE exists;
a done step released before a step of an earlier stage is flagged stale (its
inputs were re-released after it).
"""

import os
from datetime import datetime

import dash_config
from core import registry


def _flow_of(step, flow_types):
    cands = [f for f in flow_types if step == f or step.startswith(f + '_')]
    return max(cands, key=len) if cands else ''


def chain_stats(project):
    """{release_path, phases: [{phase, stages: [[step…]…], steps: {step: {flow, tag}},
    blocks: {block: {step: {done, time, stale, path}}}, done, total}]}; None when
    the project declares no chain."""
    rel_path = dash_config.project_value(project, 'release,path') or ''
    hier = dash_config.hierarchy(project) or {}
    phases = registry.tcl_list(dash_config.project_value(project, 'phases') or '')
    flow_types = registry.flow_types()
    out = []
    for ph in phases:
        raw = dash_config.project_value(project, f'signoff_chain,{ph}')
        if not raw:
            continue
        stages, steps = [], {}
        for st in registry.tcl_list(raw):
            words = registry.tcl_list(st)
            pairs = list(zip(words[0::2], words[1::2]))
            stages.append([s for s, _ in pairs])
            for s, tag in pairs:
                steps[s] = {'flow': _flow_of(s, flow_types), 'tag': tag}
        blocks, done = {}, 0
        for b in hier:
            row, prev_max = {}, 0.0
            for stage in stages:
                stage_max = 0.0
                for s in stage:
                    d = os.path.join(rel_path, ph, b, steps[s]['flow'], steps[s]['tag'])
                    mark = os.path.join(d, 'RELEASE_COMPLETE')
                    t = os.path.getmtime(mark) if os.path.isfile(mark) else 0.0
                    row[s] = {'done': bool(t), 'path': d,
                              'time': datetime.fromtimestamp(t).strftime('%Y-%m-%d %H:%M') if t else '',
                              'stale': bool(t) and t < prev_max}
                    done += bool(t)
                    stage_max = max(stage_max, t)
                prev_max = max(prev_max, stage_max)
            if any(c['done'] for c in row.values()):
                blocks[b] = row
        out.append({'phase': ph, 'stages': stages, 'steps': steps, 'blocks': blocks,
                    'done': done, 'total': len(steps) * len(blocks)})
    return {'release_path': rel_path, 'phases': out} if out else None
