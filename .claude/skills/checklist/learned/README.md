# Checklist learned store

What the checklist skill learned per tech node and per block, so the next
triage starts from prior knowledge. Written only by `../scripts/learn.py add`;
read by `learn.py read`, `checklist_triage.py` (entries for a failing check)
and `missing_checks.py` (rejected suggestions).

## Layout
```
learned/<tech>/_tech.md     facts true for every block on the tech node (library, PDK, tool behaviour)
learned/<tech>/<block>.md   facts of one block
```
`<tech>` = the run's `env.TECH_NAME` (e.g. `skywater_130nm`), `<block>` = `env.CBFLOW_BLOCK_NAME`
(`learn.py context <run>` prints both). Files are created on the first `add`.

## Entry format (one line, `|`-separated, appended under `## Entries`)
```
- <YYYY-MM-DD> | <phase> | <milestone> | <check> | <kind> | <run dir name> | <one fact>
```
- `check`: check name as in the status JSON, a mandatory-file path, or `-`.
- `kind`: `failure` (value / scenario seen), `cause` (confirmed root cause), `fix` / `fix-failed`
  (action applied and its result), `waiver` (id, expiry, approver), `missing-accepted` /
  `missing-rejected` (suggested check name + the user's reason), `threshold` (agreed target), `note`.
- Only facts observed in a run or decided by the user; no guesses, no `|` or newlines in fields.

Example (format only):
```
- 2026-01-15 | P2 | PRO_EXIT | setup_wns | fix | P2_run_PNR_blk_r3 | timing ECO (12 resizes) -> WNS +0.004 ns, retrace from pro1
```
