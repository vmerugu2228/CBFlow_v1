# Machine Learning in EDA

## Overview

Machine learning (ML) is transforming electronic design automation by enabling prediction, optimization, and decision-making at speeds and scales that were previously impossible. In physical design, ML models can predict timing, congestion, IR drop, and routability hours before traditional analysis would complete, enabling faster design space exploration and earlier detection of problems. This guide covers the current state of ML applications in EDA, practical use cases, and the considerations PD engineers should understand.

## Why ML in EDA?

### The Scalability Challenge

Modern SoCs contain billions of transistors with millions of nets and thousands of timing paths. Traditional EDA algorithms (global optimization, incremental STA, detailed routing) are computationally expensive. A single signoff STA run can take hours; a full PnR iteration can take a day.

ML offers the potential to approximate these expensive computations in seconds or minutes, enabling:

- Rapid design space exploration (evaluate hundreds of configurations instead of a handful)
- Early prediction of downstream problems (predict post-route timing from placement data)
- Intelligent automation (ML-guided tool parameter tuning)

### The Data Advantage

EDA generates massive amounts of structured data: timing reports, placement databases, routing results, power maps, congestion maps. This data is ideal for supervised ML:

- Features are well-defined (net length, cell count, pin density, etc.)
- Labels are readily available (actual timing, actual congestion, actual DRC count)
- Historical designs provide rich training data

## Timing Prediction

### Pre-Route Timing Prediction

One of the most impactful ML applications. Predict post-route timing from placement data, before routing is complete.

**Problem**: After placement, timing is estimated using wire load models or Steiner tree approximations. These estimates can be off by 20-50% from actual post-route timing. If the actual timing is much worse, the placement must be redone.

**ML approach**:
- **Features**: Net topology (pin count, bounding box, HPWL), cell characteristics (drive strength, Vt), path depth, local cell density, congestion estimates
- **Label**: Actual post-route net delay (from extracted parasitics)
- **Model**: Gradient-boosted trees (XGBoost, LightGBM) or graph neural networks (GNNs) that operate on the netlist graph
- **Accuracy**: State-of-the-art models achieve < 5% mean absolute error for net delay prediction

### Path-Level Timing Prediction

Predict WNS and TNS at signoff from early implementation stages.

**ML approach**:
- **Features**: Post-placement timing, congestion metrics, utilization, cell count by type, path characteristics (logic depth, fan-out)
- **Label**: Signoff WNS/TNS (from PrimeTime/Tempus)
- **Model**: Regression models trained on historical designs
- **Usage**: Flag designs that are likely to fail signoff timing, enabling earlier intervention

### Practical Considerations

- Models must be trained per technology node and per design style (CPU vs. GPU vs. modem)
- Retraining is needed when process libraries change or tool versions are updated
- ML predictions are estimates, not guarantees. They should guide decisions, not replace signoff analysis

## Congestion Prediction

### Early Congestion Estimation

Predict routing congestion from placement (or even from netlist/floorplan) before global routing.

**Problem**: Routing congestion is only accurately known after global routing, which takes hours. If congestion is severe, the placement or floorplan must be changed, wasting the routing run.

**ML approach**:
- **Features**: Local cell density, pin density, net connectivity (adjacency graph), macro proximity, utilization
- **Label**: Actual global routing overflow or congestion percentage per grid cell
- **Model**: Convolutional neural networks (CNNs) operating on spatial feature maps, or GNNs operating on the netlist graph
- **Output**: Congestion heatmap prediction

### Applications

- **Floorplan evaluation**: Compare congestion predictions for multiple floorplan candidates without running routing
- **Placement guidance**: Bias placement to avoid predicted congestion hotspots
- **Resource estimation**: Predict whether the current utilization and pin density will be routable

### Commercial Tool Integration

- **Cadence Cerebrus**: Uses ML for placement and routing optimization, including congestion prediction
- **Synopsys DSO.ai**: Distributed search optimization using ML to explore PnR tool parameter space
- **Custom models**: Many design teams train proprietary congestion models on their design portfolio

## Placement Optimization

### ML-Guided Placement

Traditional placement algorithms use analytical methods (force-directed, quadratic) followed by detailed placement (greedy swaps, simulated annealing). ML can augment these:

**Reinforcement Learning for Macro Placement**: Google's work (published in Nature, 2021) demonstrated RL-based macro placement:
- **Agent**: RL policy network that places macros one at a time on a grid
- **Reward**: Combination of wirelength, congestion, and timing metrics
- **Training**: Pre-train on a dataset of designs, then fine-tune for each new design
- **Result**: Competitive with or better than human experts for macro placement, completing in hours instead of weeks

**Standard Cell Placement Enhancement**:
- ML models predict the best placement parameter settings (target density, congestion weight, timing weight)
- Bayesian optimization explores the parameter space efficiently
- Transfer learning reuses knowledge from previous designs

### Practical Considerations

- RL-based placement is computationally expensive to train (hundreds of GPU-hours per design)
- The quality depends heavily on the reward function definition
- Reproducibility and explainability are challenges (RL policies are black boxes)
- Hybrid approaches (ML + traditional algorithms) often outperform pure ML

## Routing Prediction

### Routability Prediction

Predict whether a placed design is routable (and how many DRC violations routing will produce) before actually routing.

**Features**: Pin density, congestion estimates, cell density, macro channel width, net connectivity
**Label**: Post-route DRC count, routing overflow
**Usage**: Filter out non-routable placements early, saving hours of routing time

### Route Quality Prediction

Predict the quality of routing (wire length, via count, SI impact) from placement:

- Predict total wire length per metal layer
- Predict via count and distribution
- Predict SI-induced timing degradation

These predictions enable earlier and more accurate power and timing estimates.

## IR Drop Prediction

### Static IR Drop Prediction

Predict static IR drop from power grid design and cell placement without running full PDN simulation.

**ML approach**:
- **Features**: Power grid topology (stripe width, via count, pad locations), cell power consumption, cell density distribution
- **Label**: IR drop value at each analysis point
- **Model**: CNN operating on a spatial grid, or physics-informed neural network (PINN)
- **Speed**: 100-1000x faster than full simulation

### Dynamic IR Drop Prediction

Predict peak dynamic IR drop from switching activity patterns:

- **Features**: Switching activity (from VCD or statistical estimation), power grid parameters, decap cell placement
- **Label**: Peak dynamic IR drop per region
- **Application**: Early identification of IR drop hotspots for decap placement optimization

### Practical Impact

IR drop simulation (RedHawk, Voltus) on a large SoC can take 12-48 hours. ML prediction in minutes enables:

- Iterative power grid optimization (try many configurations quickly)
- Runtime monitoring during PnR (flag IR drop risks during placement)
- Quick validation after ECOs (re-predict without full resimulation)

## Design Space Exploration

### Hyperparameter Optimization

PnR tools have hundreds of parameters that affect QoR. Finding the optimal combination is a high-dimensional optimization problem.

**Approaches**:
- **Bayesian optimization**: Model the QoR as a function of parameters using a Gaussian process; sample points that maximize expected improvement
- **Reinforcement learning**: Agent learns to select tool parameters based on design characteristics
- **Multi-objective optimization**: Simultaneously optimize timing, power, area, and congestion

**Commercial tools**:
- **Synopsys DSO.ai**: Automates PnR parameter tuning across distributed compute, using ML to guide exploration
- **Cadence Cerebrus**: ML-driven optimization of Innovus flow parameters
- **Siemens (Mentor) Solido**: ML-based optimization for analog/mixed-signal, applicable to characterization

### Flow Optimization

Beyond individual tool parameters, ML can optimize the flow itself:

- Which optimization steps to run and in what order
- When to stop iterating (diminishing returns detection)
- Which constraints to tighten or relax at each stage

## Practical ML Deployment Considerations

### Data Quality

ML models are only as good as their training data:

- **Consistency**: Training data must use consistent tool versions, libraries, and methodologies
- **Diversity**: Include designs of varying size, complexity, and utilization
- **Labeling accuracy**: Ensure labels (e.g., signoff timing) are from converged, signoff-quality runs
- **Volume**: Most ML models require hundreds to thousands of training samples for robust generalization

### Model Validation

- **Cross-validation**: Validate on held-out designs, not just held-out paths from the same design
- **Out-of-distribution detection**: Flag predictions where the model is operating outside its training domain
- **Correlation metrics**: Report correlation (R-squared), mean absolute error, and worst-case error
- **Human review**: ML predictions should be reviewed by experienced engineers, especially for critical decisions

### Integration with EDA Flows

- ML predictions should be advisory, not authoritative. They guide early decisions; signoff still requires full analysis
- Integrate ML predictions into dashboards alongside traditional metrics
- Automate retraining as new design data becomes available
- Version-control models alongside the EDA flow

### Current Limitations

- **Generalization**: Models trained on one design style (CPU) may not work well on another (GPU)
- **Technology transfer**: Models trained at 7nm may not transfer to 5nm without retraining
- **Explainability**: Neural network predictions are difficult to explain (why is this net predicted to have high delay?)
- **Reliability**: ML models can produce confident but incorrect predictions, especially on novel designs
- **Adoption barrier**: Requires ML expertise alongside EDA expertise, which is a rare combination

## Future Directions

- **Foundation models for EDA**: Large pre-trained models that understand circuit structure and can be fine-tuned for specific tasks
- **Generative design**: ML models that generate floorplans, power grids, or clock tree topologies rather than just predicting metrics
- **Closed-loop optimization**: ML models directly controlling PnR tools in real-time, adjusting parameters dynamically during optimization
- **Cross-stage prediction**: Predict tapeout-quality metrics from RTL, skipping intermediate implementation stages
- **Process-design co-optimization**: ML models that jointly optimize design parameters and process parameters for maximum yield

ML in EDA is a rapidly evolving field. PD engineers who understand both the potential and the limitations of these techniques will be well-positioned to leverage them effectively.
