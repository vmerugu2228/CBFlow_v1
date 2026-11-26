# CBflow SmartGenie — Fine-Tuning Guide

## Overview

Fine-tune a local LLM on CBflow-specific data so it natively understands:
- All 33 CBflow flows (PD, DFT, DV, RTL) and their stages
- Exact cbflow CLI command syntax
- EDA tool commands (FC, PT, Innovus, Calibre, Tessent...)
- VLSI/PD methodology and best practices
- Project-specific configs and conventions

## Architecture

```
data/cbflow_training.jsonl  →  Base Model (qwen2.5)  →  LoRA / QLoRA adapter  →  ollama create cbflow-genie
(generate_training_data.py)                              (1-5% of parameters)     →  CBFLOW_MODEL=cbflow-genie cbflow smartgenie
```

## Step 1: Prepare Training Data

```bash
python3 generate_training_data.py      # writes data/cbflow_training.jsonl
```

`data/cbflow_training.jsonl` is the single generated file (instruction / output
pairs with a category: commands, knowledge, tool_use, …). Re-run the generator
after CLI or flow changes.

Training data format: JSONL with instruction/input/output or conversation format.

```json
{"instruction": "What flows are available in CBflow?", "output": "CBflow supports 12 flows:\n1. SYNTH — RTL synthesis\n2. PNR — Place and route\n..."}
{"instruction": "Create a SYNTH_PNR run named test1 for block cpu_core", "output": "{\"tool\": \"bash\", \"args\": {\"command\": \"cbflow workspace create --config uc_SYNTH_PNR_test1.tcl\"}}"}
```

## Step 2: Fine-Tune (needs GPU)

No training script ships in this directory: the `fine_tune.py` /
`fine_tune_mlx.py` commands below are placeholders for your own Unsloth / MLX
training script.

### Option A: Cloud GPU (~$5-10, 2-4 hours)
```bash
# Rent GPU: RunPod ($0.74/hr for A100 40GB) or Lambda ($1.10/hr)
# Upload training data
pip install unsloth
python fine_tune.py --data data/ --model qwen2.5:7b --output cbflow-genie
```

### Option B: Mac M1/M2/M3 with MLX (free, slow ~8-12 hours)
```bash
pip install mlx mlx-lm
python fine_tune_mlx.py --data data/ --model qwen2.5:7b
```

### Option C: Linux with NVIDIA GPU (A100/4090/A6000)
```bash
pip install unsloth peft transformers
python fine_tune.py --data data/ --model qwen2.5:7b
```

## Step 3: Deploy to Ollama
```bash
# Create Modelfile
cat > Modelfile << 'EOF'
FROM qwen2.5:7b
ADAPTER ./cbflow-adapter
PARAMETER temperature 0.1
SYSTEM "You are CBflow SmartGenie..."
EOF

# Create custom model
ollama create cbflow-genie -f Modelfile

# Use it
export CBFLOW_MODEL=cbflow-genie
cbflow smartgenie
```

## Training Data Stats
- `data/cbflow_training.jsonl` (≈2.4k examples at last generation)
- Target: 2000-5000 training examples
- Categories: commands, knowledge, conversations, tool use
