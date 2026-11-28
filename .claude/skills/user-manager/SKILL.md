---
name: user-manager
description: Manage CBflow people and roles — who holds which role on which project (cad_admin, flow_owner, chip_lead, discipline_lead, block_owner, engineer, viewer, read grants), onboarding and offboarding users, role reviews (missing leads, logins that do not exist, single points of failure), access checks ("can X release BTO on project P?"), the access audit, and the enforcement rollout per project (audit-only → enforced after a readiness check). Use when the user asks to add / remove / move a person, grant or revoke a role, see who has access, why an action was denied, review access, or turn access enforcement on.
---

# User manager (roles and access)

Backend: `cbflow flow access` (roles in `global/config/access/roles.json`, rules in
`global/utils/core/access.py`). Helper:
`U=.claude/skills/user-manager/scripts/um.py` (executable; call it from the repo
root). Read [reference.md](reference.md) for the role matrix and rules.

## 0. Who is asking
Start with `bin/cbflow flow access whoami`. What the requester may change:
- **cad_admin:** every role, enforcement, and the access configuration.
- **chip_lead:** the roles of their own project (not chip_lead itself).
- **Anyone else:** read only. Prepare a request for a chip lead or cad_admin
  instead of changing anything.

## 1. Look
```bash
bin/cbflow flow access show [--project P] [--user U]
$U report [--project P]           # users x projects x roles + problems
bin/cbflow flow access check --action <action> --project P [--disc D] [--block B] --user U
bin/cbflow flow access audit [--user U] [--project P] [--decision deny|would-deny]
```
`report` flags:
- logins that don't exist on the host;
- projects without a chip lead or a discipline lead (BTO / MTO then fall to the
  chip lead);
- a single cad_admin.

Explain a denial from the audit line: the action, the roles the user has, the roles
needed, and who holds them.

## 2. Change (dry run first; apply on the requester's yes)
```bash
$U onboard  --user U --project P --role R [--disc D | --block B] --reason "…" [--apply]
$U offboard --user U [--project P] --reason "…" [--apply]      # every role the user holds
bin/cbflow flow access grant|revoke --role R --user U [--project P] [--disc D] [--block B] --reason "…"
```
- **Users:** logins only (`pwd`), or `group:<unix group>`. Never display names.
- **Roles that need a qualifier:** `discipline_lead` needs `--disc`, `block_owner`
  needs `--block`, and `flow_owner` needs `--disc`.
- **Cross-project read:** `grant_read` on project P lets a non-member read P. A
  chip lead grants it.
- **Moving someone between projects:** offboard from the old project, onboard on
  the new one.
- **Every change** is backed up (`global/config/access/backup/`) and logged
  (`global/config/access/CHANGELOG.jsonl`) with who and why.
- **The last cad_admin** can't be removed.

## 3. Enforcement rollout (cad_admin)
A project starts audit-only: denials are logged as `would-deny` and the action
proceeds.
1. `$U readiness --project P [--days 30]`: who would be blocked.
2. Fix the roles (onboard), or confirm those users should be blocked.
3. Turn it on: `bin/cbflow flow access enforce on --project P --reason "…"`. For
   framework actions (flow releases, framework configs, base library tags):
   `enforce on --framework`.
4. Watch `bin/cbflow flow access audit --decision deny --project P` the first days.

Turning it back off is `enforce off`, which is logged.

## Rules
- Never edit `roles.json` by hand or sed. Always go through `cbflow flow access`,
  which applies the permission checks, backup and log.
- Never impersonate users outside the test suite. (`CBFLOW_ACCESS_TEST` is only
  honoured with `CBFLOW_ACCESS_TEST=1`, for tests.)
- A denial is information, not an obstacle. Route the request to the role holder;
  don't work around the gate.
