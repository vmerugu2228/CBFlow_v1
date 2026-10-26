# On-Chip Variation: OCV Derating Methodologies

## Why OCV Matters

Process, voltage, and temperature variations do not only exist between different chips (die-to-die) or different wafer lots (lot-to-lot). Variations also exist within a single die. Two identical cells placed millimeters apart on the same chip can have different delays due to local process fluctuations, voltage IR drop gradients, and thermal gradients. On-Chip Variation (OCV) analysis models these intra-die variations to ensure timing correctness.

Without OCV, STA assumes that all cells on the same chip have exactly the same delay at a given PVT corner. This is unrealistically optimistic. OCV adds realism by derating (scaling) delays differently on launch and capture paths, creating a pessimistic analysis that accounts for local variation.

## The Principle of OCV Derating

For setup analysis, OCV assumes the worst case:
- **Launch path (data):** Derated slower (delays increased)
- **Capture path (clock):** Derated faster (delays decreased)

This maximizes the data arrival time while minimizing the data required time, stressing setup.

For hold analysis, OCV assumes the opposite:
- **Launch path (data):** Derated faster (delays decreased)
- **Capture path (clock):** Derated slower (delays increased)

This minimizes the data arrival time while maximizing the required time, stressing hold.

## Flat OCV (Traditional Derating)

The simplest OCV model applies a single, flat derating factor to all cells.

```tcl
# Apply flat OCV derating
set_timing_derate -early 0.93  ;# 7% faster for early (hold launch / setup capture)
set_timing_derate -late  1.07  ;# 7% slower for late (setup launch / hold capture)
```

This means:
- For setup: data path delays are multiplied by 1.07, clock path delays by 0.93
- For hold: data path delays are multiplied by 0.93, clock path delays by 1.07

### Limitations of Flat OCV

Flat OCV is overly pessimistic because it applies the same derating to every cell regardless of:
- **Path depth:** Variation averages out over long paths (statistical averaging)
- **Cell type:** Large cells have less variation than small cells
- **Physical proximity:** Cells near each other have correlated variations

This excessive pessimism leads to over-design: unnecessary buffer insertion, excessive LVT usage, and wasted power and area.

## AOCV: Advanced OCV (Stage-Based)

AOCV (also called SBOCV -- Stage-Based OCV) recognizes that random variations partially cancel across multiple stages in a path. The derating factor decreases as the number of stages (logic depth) increases.

### How AOCV Works

AOCV uses lookup tables indexed by:
- **Number of stages** in the path (logic depth)
- **Distance** between cells (physical span of the path)

```
Stages | Derate (late) | Derate (early)
  1    |    1.12       |    0.88
  2    |    1.09       |    0.91
  5    |    1.06       |    0.94
  10   |    1.04       |    0.96
  20   |    1.03       |    0.97
```

A single-stage path gets a large derating (high variation), while a 20-stage path gets a small derating (variation averages out).

### AOCV Table Format

AOCV tables are provided by the foundry or library vendor in a specific file format:

```
# AOCV table file format
object_type : cell
object_name : BUFX4_SVT
depth_based_derate_table (late_derate) {
  index_1 ("1, 2, 3, 5, 10, 20");
  values ("1.12, 1.09, 1.07, 1.05, 1.03, 1.02");
}
depth_based_derate_table (early_derate) {
  index_1 ("1, 2, 3, 5, 10, 20");
  values ("0.88, 0.91, 0.93, 0.95, 0.97, 0.98");
}
```

### Applying AOCV

```tcl
# Innovus
setAnalysisMode -aocv true
read_aocv /path/to/aocv_table.aocv

# PrimeTime
read_aocv /path/to/aocv_table.aocv
set_timing_derate -aocv
```

### AOCV Benefits

AOCV is less pessimistic than flat OCV for deep paths, recovering significant timing margin. Typical improvements:
- 5-15% TNS reduction compared to flat OCV
- Fewer hold buffers needed
- More realistic slack distribution

## POCV: Parametric OCV

POCV (also called SOCV -- Statistical OCV) goes further than AOCV by modeling variation statistically. Instead of applying a fixed derate per stage count, POCV computes a delay distribution (mean + sigma) for each cell and combines them statistically along the path.

### How POCV Works

Each cell delay is modeled as a Gaussian distribution:
```
Cell delay = Nominal_delay +/- (sigma * variation_coefficient)
```

Path delay is computed as:
```
Path delay (mean) = sum of nominal delays
Path delay (sigma) = sqrt(sum of (sigma_i)^2)  [for random variation]
                   + sum of systematic_variation_i   [for systematic variation]
```

The square-root-sum-of-squares (RSS) for random variation naturally captures statistical averaging without needing stage-count tables.

### POCV Input: Variation Data

POCV requires cell-level variation data, typically provided in **LVF (Liberty Variation Format)** files:

```
# LVF data in Liberty
cell (BUFX4_SVT) {
  ocv_sigma_cell_rise ("sigma_table") {
    index_1 ("input_slew_values");
    index_2 ("output_cap_values");
    values ("sigma_values");
  }
  ocv_sigma_cell_fall ("sigma_table") {
    ...
  }
}
```

### Applying POCV

```tcl
# PrimeTime
set_app_var pocvm_enable true
read_lib -lvf /path/to/library.lvf

# Innovus
setAnalysisMode -pocv true
setAnalysisMode -socv true
```

### POCV vs. AOCV

| Aspect | AOCV | POCV |
|---|---|---|
| Variation model | Lookup table (depth + distance) | Statistical (mean + sigma per cell) |
| Accuracy | Moderate | High |
| Data requirement | AOCV tables | LVF data in Liberty |
| Statistical averaging | Implicit in table values | Explicit RSS calculation |
| Runtime | Low overhead | Moderate overhead |
| Adoption | Widely supported | Growing adoption at 7nm+ |

POCV is more accurate because it accounts for the actual variation characteristics of each cell type and operating condition, rather than using generic depth-based tables.

## SOCV: Statistical OCV

SOCV is Synopsys's implementation of parametric OCV within PrimeTime. It is functionally equivalent to POCV but uses Synopsys-specific terminology and flow.

```tcl
# PrimeTime SOCV
set_app_var timing_pocvm_enable_analysis true
set_app_var timing_pocvm_corner_sigma 3.0
```

SOCV separates variation into:
- **Random variation:** Uncorrelated between cells, subject to RSS averaging
- **Systematic variation:** Correlated across cells (e.g., lithographic proximity effects), added linearly

## LVF: Liberty Variation Format

LVF is the industry-standard format for encoding cell-level variation data for POCV/SOCV analysis. LVF data is embedded within Liberty (.lib) files.

### LVF Contents

- **Cell delay sigma:** Standard deviation of cell delay at each input-slew/output-load point
- **Constraint sigma:** Standard deviation of setup/hold timing constraints
- **Transition sigma:** Standard deviation of output transition time

### LVF Types

- **LVF Type 1:** Single sigma value (symmetric variation)
- **LVF Type 2:** Separate early and late sigma values (asymmetric variation)

## CPPR: Common Path Pessimism Removal

OCV analysis applies different derating to launch and capture clock paths. However, the portion of the clock path that is shared between launch and capture (the common path) cannot simultaneously be both fast and slow. CPPR removes this artificial pessimism.

```
Clock tree:
  root -> [common path] -> branch_point -> [launch branch] -> launch_ff
                                        -> [capture branch] -> capture_ff

Without CPPR: common path is derated slow for launch, fast for capture
With CPPR: common path derating cancels out, only branch paths are derated
```

CPPR credit = (late_derate - early_derate) * common_path_delay

This credit is added back to the slack, reducing pessimism. CPPR is essential for meaningful OCV analysis and should always be enabled.

```tcl
# Enable CPPR
set_analysis_mode -cppr both  ;# or -cppr setup / -cppr hold
```

## Practical Recommendations

1. **Use AOCV at minimum for 16nm and below.** Flat OCV is too pessimistic at advanced nodes and leads to over-design.

2. **Migrate to POCV/SOCV when LVF data is available.** The additional accuracy recovers significant margin, especially for deep pipeline paths.

3. **Always enable CPPR.** OCV without CPPR produces artificially pessimistic results, particularly for paths with long common clock segments.

4. **Verify derating values with the foundry.** Do not guess at derate values. Use the foundry-recommended AOCV tables or LVF characterization data.

5. **Check both setup and hold with OCV.** OCV affects both. Hold violations under OCV are real and must be fixed.

6. **Understand the sigma level.** POCV results depend on the sigma multiplier (e.g., 3-sigma). Higher sigma = more pessimism = higher yield guarantee.

7. **Compare flat OCV vs. AOCV vs. POCV results.** Run all three on a representative block to quantify the margin recovery from advanced OCV methods. Use this data to justify the methodology choice to the project.

OCV modeling has evolved from crude flat derating to sophisticated statistical analysis. Using the most advanced OCV methodology available for your technology node directly translates to better PPA (Power, Performance, Area) by eliminating unnecessary pessimism while maintaining silicon reliability.
