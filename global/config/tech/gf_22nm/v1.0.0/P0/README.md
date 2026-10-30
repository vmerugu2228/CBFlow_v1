# Library tag: `P0`

Technology: **gf_22nm**  
Generated: **2026-10-11 00:07:33**  
Source lib_root: `/tmp/post_merge_mock`

---

## Flow integration

Set `project(lib_config_tag)` to `P0` in user_config.tcl (or `project_pd_config.tcl`). The resolver auto-picks
`PD/config/tech/gf_22nm/v1.0.0/P0/lib_config.tcl`.

## Coverage

- **Tracks:** 9T
- **VTs:**    svt lvt
- **Corners:** ss_0p80v_125c tt_0p90v_25c

## File counts per subdirectory

| subdir | files |
|---|---:|
| `db/` | 2 |
| `io/` | 2 |
| `lef/` | 2 |
| `lib/` | 4 |
| `memory/` | 4 |
| `ndm/` | 2 |

## Layout

```
P0/
├── lib_config.tcl    # resolver-visible tech(...) keys, LOCAL paths
├── MANIFEST.tcl      # symlink → vendor audit
├── README.md         # this file
├── ndm/<track>/      # stdcell NDM per track (all VTs flat inside)
├── lib/<track>/      # Liberty .lib timing + nominal
├── db/<track>/       # compiled .db for PT/FC
├── lef/<track>/      # abstract LEF
├── memory/{{lib,db,lef,ndm}}/
├── io/{{lib,db,lef,ndm}}/
├── analog/{{lib,db,lef,ndm}}/
├── gds/, cdl/, verilog/   # reserved
└── logs/generate.log
```

## Regenerate

```
cbflow flow library-manager generate --tech gf_22nm --tag P0
```

Regeneration rebuilds every symlink from the source `lib_root` and rewrites `lib_config.tcl`. Older symlinks pointing at files that disappeared from the vendor delivery are left in place with `stub` method so flow-time breakage is loud, not silent.
