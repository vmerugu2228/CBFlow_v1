# CBflow SmartGenie — Fine-Tuning Guide

## Overview

Fine-tune a local LLM on CBflow-specific data so it natively understands:
- All 12 CBflow flows and their stages
- Exact cbflow CLI command syntax
- EDA tool commands (FC, PT, Innovus, Calibre, Tessent...)
- VLSI/PD methodology and best practices
- Project-specific configs and conventions

## Architecture

```
Training Data (JSONL)  →  Base Model (qwen2.5:7b)  →  Fine-Tuned Model
   ├── cbflow_commands.jsonl      LoRA/QLoRA adapter       cbflow-genie:7b
   ├── eda_knowledge.jsonl        (trains only 1-5%         ↓
   ├── tool_commands.jsonl         of parameters)       ollama create
   └── conversations.jsonl                                   ↓
                                                        cbflow smartgenie
```

## Step 1: Prepare Training Data (done — see data/ folder)

Training data format: JSONL with instruction/input/output or conversation format.

```json
{"instruction": "What flows are available in CBflow?", "output": "CBflow supports 12 flows:\n1. SYNTH — RTL synthesis\n2. PNR — Place and route\n..."}
{"instruction": "Create a SYNTH_PNR run named test1 for block cpu_core", "output": "{\"tool\": \"bash\", \"args\": {\"command\": \"cbflow workspace create --config uc_SYNTH_PNR_test1.tcl\"}}"}
```

## Step 2: Fine-Tune (needs GPU)

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
- See data/ folder for prepared JSONL files
- Target: 2000-5000 training examples
- Categories: commands, knowledge, conversations, tool use
