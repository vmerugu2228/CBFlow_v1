"""CBflow-ProjectDashboard — project-level tracking daemon.

Serves a per-project rollup of published runs across (block, phase, milestone)
cells. Data is snapshotted (frozen) into a per-project tracker.db at publish
time. No polling, no filesystem watch — publish rides on each release:

    cbflow run release --tag <TAG> [--override]          # publishes if the daemon is running; --publish starts it
    cbflow run release --tag <TAG> --no-publish          # opt out (local only)

The web UI shows a grid: blocks × phases, each cell holding one chip per exit
milestone, colored by the checklist verdict at the moment of publish. Click a
chip → detail page with all metrics and the checklist result.

Complement to the per-run dashboard (`cbflow run dashboard`), which serves
live DAG/status views scoped to a single run directory.
"""

__version__ = '1.0.0'
