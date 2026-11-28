# CBflow roles and access — plan (future scope)

Status: plan only, not implemented.

Goal: who may run which skills and commands, and change which configs and
releases, scoped by project and by role. Today the only gates are scattered:
- config-manager: project owners for project configs;
- release locks: locker or chip lead;
- RACE runs: run owner for mutations;
- frozen flow releases: read-only files.

## 1. Roles
| Role | Scope | Typical people |
|---|---|---|
| **cad_admin** (CSD / CAD) | framework-wide | flow developers, CAD support |
| **flow_owner** (per discipline: PD / DFT / DV / RTL) | framework, one discipline | discipline methodology lead |
| **chip_lead** | one project | project lead |
| **discipline_lead** (per project × discipline) | one project, one discipline | PD lead, DV lead … |
| **block_owner** (per project × block) | one project, its blocks | block implementers |
| **engineer** | one project (assigned) | team members |
| **viewer** | one project, read-only | management, reviewers |

A person can hold several roles. Every role except cad_admin and flow_owner is
bound to a project.

## 2. Permissions (actions × role)
| Action | viewer | engineer | block_owner | discipline_lead | chip_lead | flow_owner | cad_admin |
|---|---|---|---|---|---|---|---|
| read runs / dashboards / reports | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| create / run / retrace runs (own project) | | ✓ | ✓ | ✓ | ✓ | | ✓ |
| release a block exit | | | own blocks | ✓ | ✓ | | ✓ |
| publish to SmartGrid, waive checks | | | | ✓ (policy) | ✓ | | |
| lock / unlock exits | | | own blocks | ✓ | ✓ | | ✓ |
| edit run / user configs | | own runs | ✓ | ✓ | ✓ | | ✓ |
| edit project discipline overlay | | | | own discipline | ✓ | | ✓ |
| edit project global config (hierarchy, phases, exits) | | | | | ✓ | | ✓ |
| library tags: create / freeze (project tag) | | | | PD lead | ✓ | | ✓ |
| library base tags (cells) | | | | | | PD | ✓ |
| framework configs / command files (new version) | | | | | | own discipline | ✓ |
| cut a flow release / freeze | | | | | | | ✓ |
| pin a project to a flow release | | | | | ✓ | | ✓ |
| kick off a new project | | | | | | | ✓ (+ chip lead named) |

## 3. Skills mapped to permissions
| Skill | Needs |
|---|---|
| rtl2gds, spec2rtl, timing-eco, drc-fix, floorplan | engineer+ on the project; releases need block_owner+ |
| checklist (triage / waivers) | engineer (read); discipline_lead+ (waivers within policy) |
| library-manager | discipline_lead (PD)+ for project tags; flow_owner (PD) / cad_admin for base tags |
| mmmc-manager (write) | discipline_lead (PD)+ |
| config-manager | per scope, as in §2 |
| cmd-manager | flow_owner (discipline) / cad_admin |
| flow-manager | read: everyone. cut / freeze: cad_admin. pin: chip_lead / cad_admin |
| project-kickoff | cad_admin |

**Rule:** a skill on project P runs only when the user holds a role on P (or is
cad_admin). Every write action checks the specific permission. A read-only role
may still run read-only commands (status, audit, show).

## 4. Data model
`global/config/access/roles.json`. It is versioned, edited only by cad_admin
(through config-manager, `--framework`), and every change is logged.
```json
{
  "cad_admin":  ["vmerugu"],
  "flow_owner": {"PD": ["vmerugu"], "DFT": [], "DV": [], "RTL": []},
  "projects": {
    "opensky": {
      "chip_lead": ["vmerugu"],
      "discipline_lead": {"PD": ["vmerugu"], "DV": [], "DFT": [], "RTL": []},
      "block_owner": {"gcd": ["vmerugu"], "mac_array": []},
      "engineer": ["vmerugu"],
      "viewer": []
    }
  }
}
```
**Migration:** seed it from `master_projects.json` (`chip_lead`, `flow_owners`).
That registry keeps project metadata; roles move to `roles.json`. Identities are
logins (`$USER`) or, later, SSO / LDAP groups (`group:pd-team`).

## 5. Enforcement points
1. **One library:** `global/utils/core/access.py` with `can(user, action, project=None,
   discipline=None, block=None) -> (bool, why)`, plus a Tcl `cbflow_can` for
   handlers. Every gate calls it.
2. **CLI:** `cbflow` dispatch checks the action of each subcommand. For example
   `workspace create` checks engineer on the project, `run release` checks
   block_owner+, `flow release create` checks cad_admin. The dashboards check the
   same (HTTP 403, like run ownership today).
3. **Skills:** each skill script calls `access.can` before writes. SKILL.md step 1
   adds "check the user's role on the project; refuse with the needed role".
   Claude Code hooks (PreToolUse on Bash / Edit) block edits under
   `<DISC>/config`, `cmds`, `global/config` for users without the role. The harness
   enforces that, not the model.
4. **Files:** frozen releases are already read-only. Framework trees could add
   group ownership (`cbflow-cad`) + 2775; project areas `cbflow-<project>`.
5. **Audit:** every allowed or refused write appends to
   `<state>/access_audit.jsonl` (who, action, target, decision, reason).

## 6. Phases
| Phase | Scope |
|---|---|
| 1 | `roles.json` + `access.py` + the read / write matrix; wire config-manager, cmd-manager, flow-manager, release lock, library-manager |
| 2 | CLI dispatch gates (workspace create / run / release / publish / waiver); dashboard 403s |
| 3 | Claude Code hooks for file edits by role; per-skill role checks in every SKILL.md |
| 4 | LDAP / SSO groups; group file permissions; access audit page in SmartGrid |

## 7. Open questions for the owner
1. Are CSD and CAD the same role (cad_admin), or should CSD be a support role:
   read everything, run diagnostics, no writes?
2. Can a block_owner release their block's BTO / MTO, or is that discipline_lead+?
3. Do waivers need chip_lead approval in addition to the discipline lead?
4. Cross-project reuse: may engineers of project A read project B's releases (for IP
   reuse) by default?
