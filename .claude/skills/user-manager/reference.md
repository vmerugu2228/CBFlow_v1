# user-manager reference

## Roles
| Role | Scope | Held as |
|---|---|---|
| cad_admin (CAD / CSD) | everything | `cad_admin: [logins]` |
| flow_owner.<DISC> | framework code / config of one discipline | `flow_owner: {PD: [...]}` |
| chip_lead | one project | `projects.<p>.chip_lead` |
| discipline_lead.<DISC> | one project × discipline | `projects.<p>.discipline_lead.<DISC>` |
| block_owner.<block> | one project × block | `projects.<p>.block_owner.<block>` |
| engineer | one project | `projects.<p>.engineer` |
| viewer | one project, read | `projects.<p>.viewer` |
| grant_read | read-only for a non-member | `projects.<p>.grant_read` |

## Actions → roles (core/access.py `allowed_roles`; cad_admin always allowed)
| Action | Allowed |
|---|---|
| read | members, viewer, grant_read |
| run.create / run.mutate | chip_lead, discipline_lead, engineer, block_owner (own block) |
| release.exit / release.lock / release.candidate — BTO / MTO (incl. `_ECO<n>`) | chip_lead, discipline_lead (of the flow's discipline) |
| … — earlier exits | the above + block_owner (own block) |
| release.publish / release.override / checklist.signoff / waiver.request | chip_lead, discipline_lead |
| waiver.approve, release.cleanup, config.project.global, flow.release.pin, project.manage | chip_lead |
| config.project:<DISC> | chip_lead, discipline_lead.<DISC> |
| libtag.project | chip_lead, discipline_lead.PD |
| libtag.base | flow_owner.PD |
| config.framework:<DISC> | flow_owner.<DISC> |
| flow.release.cut, project.create, project.lead_change, framework.lock, access.admin | cad_admin only |

Another user's run (engine): its owner, or chip_lead / discipline_lead / cad_admin of
the run's project (audited as `run.mutate.other`).

## Where it is enforced (phase 1)
| Entry | Gate |
|---|---|
| `cbflow run <verb>` (`run_cmd.py` `_access_gate`) | read verbs → read; mutating → run.mutate; release → release.exit:<tag> (+ publish / override); release-lock → framework.lock |
| `cbflow workspace create` | run.create on the user config's project |
| `cbflow flow release candidate / lock / unlock / cleanup / locks` (`candidate_cmd.py`) | release.candidate / release.lock:<exit> / release.cleanup / read |
| `cbflow flow release create / set-current` | flow.release.cut |
| `cbflow flow project create / manage / delete` | project.create / project.lead_change / project.manage |
| `library-manager generate / add / project-tag create / freeze` | libtag.base / libtag.project |
| `mmmc-manager` writes | config.project.global |
| `checklist sign-off / waiver add / waiver revoke / add-check / remove-check` | checklist.signoff / waiver.request / waiver.approve / config.framework; the approver recorded = the authenticated user |
| release node (`release_utils.tcl` init) | `cbflow_can_or_error release.exit:<tag>` (utils.tcl) |
| RACE engine `_check_ownership` | owner, or a lead of the project |

**Not yet** (phase 2 / 3):
- dashboard caller identity (tokens);
- the two-step waiver approval;
- gates inside the config / cmd / flow-manager skill scripts and the MCP server;
- a Claude Code PreToolUse hook for file edits.

Plan: `global/docs/roles-access-plan.md`.

## Identity and audit
- **Identity:** `access.whoami()` = the login of the process uid (`pwd`). `$USER` /
  `$LOGNAME` are ignored.
- **Audit:** `<CBFLOW_ROOT>/.access_audit/<YYYY-MM>.jsonl`, one line per decision:
  allow / deny / would-deny, user, action, project, target, why.
  - Test-mode decisions go to `test-<YYYY-MM>.jsonl`, which reports ignore.
- **Enforcement** (`roles.json` `enforce`):
  - `default` applies to projects without their own setting; `projects.<p>`
    overrides it per project;
  - `framework` covers actions with no project;
  - off means `would-deny` is logged and the action proceeds.

## Seed (done 2026-11-28)
`cbflow flow access seed --apply` built `roles.json` from `master_projects.json`:
- **cad_admin:** vmerugu.
- **Each project's chip lead login.**
- **Discipline leads from `flow_owners`:** backend → PD + DFT, frontend → RTL,
  verification → DV.
- **india:** its display names ("Raj Sh", "Gangadhar CH", "Not specified") were
  dropped. Grant its logins explicitly.
