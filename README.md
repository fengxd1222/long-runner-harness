# Long-Runner Harness

> Automation Framework for Long-Running Agents

Based on Anthropic's official autonomous-coding pattern, implementing Dual-Agent Architecture + Browser-First Testing + Defense-in-Depth Security + Meta-Harness Trace Store.

## Features

- **Dual-Agent Debate (v5.1)** - Init phase launches Proposer + Critic agents in parallel for tech stack and feature list quality review
- **Brainstorm Integration** - Proposer agent invokes superpowers:brainstorm skill before generating proposals (with graceful fallback)
- **Trace Store** - Full session traces stored in `.long-runner/` directory for cross-session learning
- **Environment Bootstrap** - Auto-detect project environment, eliminate redundant exploration turns
- **Causal Hypotheses** - Explicit causal chains during debugging for cross-session learning
- **Pareto Tracking** - Multi-dimensional metrics tracking (functional, visual quality, console errors)
- **Browser-First Testing** - Real browser UI verification via Playwright MCP
- **Defense-in-Depth Security** - Multi-layer security protection (sandbox + filesystem + command whitelist)
- **Auto-Dispatch** - Intelligently select and execute the next feature with dependency resolution
- **Session Isolation** - Each feature runs in an isolated session to avoid context length issues

## Changelog

### v5.1
- **Dual-Agent Debate**: init phase runs Proposer (with brainstorm skill) + Critic in parallel, then synthesizes results into final feature_list
- **Superpowers Integration**: Agent A invokes `superpowers:brainstorm` skill; falls back to direct generation if unavailable
- Prevents low-quality feature lists by adversarial review before coding starts

### v5.0
- **Trace Store**: `.long-runner/` directory with traces, hypotheses, pareto metrics, summaries
- **Environment Bootstrap**: auto-generated `env-snapshot.json` eliminates 2-3 exploration turns per session
- **Causal Hypotheses**: structured hypothesis tracking for debugging (Appendix A.2 of Meta-Harness paper)
- **Pareto Metrics**: multi-objective optimization instead of single pass/fail
- **New Commands**: `diagnose`, `pareto`, `resume` subcommands
- Based on [Meta-Harness paper](https://arxiv.org/abs/2603.28052) insights

## Installation

Copy files to the corresponding directories in Claude Code:

```bash
# Copy skill files
cp SKILL.md dispatch.sh ~/.claude/skills/long-runner-harness/

# Copy command files
cp commands/long-runner.md ~/.claude/commands/

# Copy dispatch script
cp scripts/long-runner-dispatch.sh ~/.claude/scripts/
```

## Usage

```bash
# Initialize new project (with dual-agent debate)
/long-runner init "project description"

# Continue execution (single step)
/long-runner continue

# Full auto mode
/long-runner auto

# Batch mode (5 features per run)
/long-runner auto --batch 5

# View progress
/long-runner status

# Resume from interruption
/long-runner resume

# Diagnose: trace analysis + unresolved hypotheses
/long-runner diagnose

# Pareto frontier visualization
/long-runner pareto
```

## Directory Structure

```
.
├── README.md                         # This file
├── README-zh.md                      # Chinese version
├── SKILL.md                          # Skill definition
├── dispatch.sh                       # Skill dispatch script
├── commands/
│   └── long-runner.md                # Command definition
└── scripts/
    └── long-runner-dispatch.sh       # Auto-dispatcher script
```

## Project Structure (Runtime)

```
project/
├── feature_list.json      # Feature list
├── init.sh                # Startup script
├── claude-progress.txt    # Progress log
├── app_spec.txt           # Project specification
├── .claude_settings.json  # Automation permission config
├── evidence/              # Browser test screenshots
├── docs/plans/            # Implementation plans
└── .long-runner/          # v5 Trace Store
    ├── meta.json              # Version + metadata
    ├── bootstrap/
    │   └── env-snapshot.json  # Auto-generated environment snapshot
    ├── traces/
    │   ├── index.json         # Trace index
    │   └── {session_id}.trace.json
    ├── hypotheses/
    │   ├── {session_id}.hypothesis.json
    │   └── open.md            # Current unresolved hypotheses
    ├── pareto/
    │   ├── metrics.json       # Multi-dimensional metrics
    │   └── frontier.json      # Pareto frontier
    └── summaries/
        └── {session_id}.summary.md
```

## References

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude Quickstarts: Autonomous Coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)
- [Meta-Harness: End-to-End Optimization of LLM Harnesses](https://arxiv.org/abs/2603.28052)

## License

MIT
