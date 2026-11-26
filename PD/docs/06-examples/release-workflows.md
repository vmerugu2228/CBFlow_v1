# Release Workflows

Two kinds of release exist in CBflow:

- **Design exit releases** — a run releases design data to an exit milestone (FP_EXIT … MTO, DV / DFT / RTL
  exits) under `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>`. See the
  [Exit Release Guide](../02-user-guide/exit-release-guide.md).
- **Framework releases** — versioned snapshots of the CBflow configs / command files themselves
  (`cbflow flow release …`). See [Release Management](../02-user-guide/release-management.md).

---

## 1. Design exit releases

### Publish a self-released open-source run

```bash
cd workarea/gcd/P1_run_PNR_gcd_b1
cbflow run release --from-run . --publish            # release_data1 already wrote the release; publish it
cbflow run release --from-run . --publish --override # replace an existing SmartGrid entry
```

### Release an intermediate stage (place -> PLACE_EXIT)

```bash
# a) bypass the later stages
cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1
cbflow run stage --name release_data1

# b) or rewire export onto place1
cbflow run set-dep --node export_data1 --deps place1
cbflow run stage --name release_data1

# c) or add a pair under place1 and publish it
cbflow run add-node --node export_data2  --type export_data  --dep place1
cbflow run add-node --node release_data2 --type release_data --dep export_data2
cbflow run stage --name release_data2
cbflow run release --from-run . --node release_data2 --publish
```

`workarea/test_place_release.sh` (`SRC=place1|cts_opt1`) exercises all three.

### MTO carries the same data as BTO

```bash
cbflow run release --from-run . --clone-from BTO --tag MTO --publish
```

Or, in the same run: set `project(release,tag) "MTO"` in `setup/override_config.release_data1.tcl` (run GUI
release form -> Save), then `cbflow run retrace --from release_data1 && cbflow run stage --name release_data1`.

### Signoff of an exit (STA / PV / LEC)

```bash
cd workarea
FLOWS="STA PV LEC" PHASE=P2 RUN=p2_b1 LIB_TAG=OSS2 ./run_signoff.sh gcd PRO_EXIT
PV_MODE=hier PHASE=P2 ./run_signoff.sh ctrl_subsys PRO_EXIT     # hierarchical PV -> PV/PRO_EXIT_HIER
PUBLISH=0 PHASE=P2 ./run_signoff.sh gcd BTO                      # release without publishing
```

Signoff flows read only the release of the exit they verify (`sta(input,release_tag) "PRO_EXIT"`), and release to
`<block>/<FLOW>/<exit>`.

### Commercial flows: package from the workspace

```bash
cbflow run release --tag PLACE_EXIT --dry-run       # gate check only (required flows of the exit)
cbflow run release --tag PLACE_EXIT --publish
cbflow run release-check --tag BTO --project bumblebee --phase LC3            # every block released?
cbflow run release-check --tag BTO --project bumblebee --phase LC3 --block cpu_core
```

### Exit order

Exits release in the order of the phase's plan — `project(phase_exits)` for PD, `project(phase_exits,DV)` (and so
on) for other disciplines, each ordered on its own. `workarea/test_exit_order.sh` demonstrates the refusal:

```
ERROR: exit order — gcd P2 cannot release PRO_EXIT before PLACE_EXIT, CTS_EXIT (release in order: FP_EXIT -> PLACE_EXIT -> CTS_EXIT -> PRO_EXIT; ...)
```

### Consume a block release in a library tag (hierarchy)

```bash
# DL3 gcd's BTO release becomes a block in library tag OSS2 for its DL2 parent (ctrl_subsys)
cbflow flow library-manager add --tech skywater_130nm --project opensky --tag OSS2 \
    --category block --path <release,path>/P2/gcd/PNR/BTO
cbflow flow library-manager check --tech skywater_130nm --lib_tag OSS2
```

---

## 2. Framework releases

Framework releases snapshot the versioned component directories (`v1.0.0/`, `v1.0.1/`, …).

### Quick release

```bash
cbflow flow version status                                 # component health
cbflow flow release create --type patch --desc "Internal testing release"
cbflow flow release list
cbflow flow release info --version v2.0.1
```

### Release from a config file (pin component versions)

```bash
cbflow flow release generate-config --output qa-release.json
vi qa-release.json                       # pick the version of each component
cbflow flow release create --config qa-release.json --desc "QA Sprint 23"
cbflow flow release validate --version v2.1.0       # check the created release
```

### Compare and switch

```bash
cbflow flow release diff --v1 v2.0.0 --v2 v2.0.1 --format markdown
cbflow flow release set-current --version v2.0.1
cbflow flow release components
```

### Ship to a customer

```bash
cbflow bundle --output /tmp            # CBflow_v2.0.0_<date>.tar.gz (run data, releases and the RACE area excluded)
# customer side, after unpacking:
bin/cbflow run release-lock            # production permissions
```

---

**See also:**
- [Basic Workflows](basic-workflows.md)
- [Advanced Scenarios](advanced-scenarios.md)
