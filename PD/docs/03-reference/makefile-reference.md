# RACE Engine Command Reference

CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) as its dispatcher. GNU Make is no longer used.

For the complete command reference, see:
- [Python Scripts Reference](python-scripts-reference.md) — All CLI commands
- [Configuration Reference](configuration-reference.md) — All config files

## RACE Commands

```bash
cbflow run all                              # Execute full DAG
cbflow run stage --name place1              # Execute single stage
cbflow run status --details                 # Query RACE DB for status
cbflow run retrace --from cts1              # Invalidate + downstream
cbflow run bypass --stages export_data1     # Skip stages
cbflow run force --stages place1            # Force re-run
cbflow run forcevalidate --node signoff1    # Mark as done
cbflow run forcevalidate --from X --to Y    # Mark range as done
cbflow run show-graph                       # Visualize RACE DAG
cbflow run add-node --node eco1 --dep signoff  # Add custom node
```

---

**Documentation Version**: 2.0.0
