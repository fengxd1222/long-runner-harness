# Long-Runner Harness

> Automation Framework for Long-Running Agents

Based on Anthropic's official autonomous-coding pattern, implementing Dual-Agent Architecture + Browser-First Testing + Defense-in-Depth Security.

## Features

- **Dual-Agent Mode** - Initializer Agent + Coding Agent collaboration
- **Browser-First Testing** - Real browser UI verification via Playwright MCP
- **Defense-in-Depth Security** - Multi-layer security protection
- **Auto-Dispatch** - Intelligently select and execute the next feature
- **Session Isolation** - Each feature runs in an isolated session to avoid context length issues

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
# Initialize new project
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
└── docs/plans/            # Implementation plans
```

## References

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude Quickstarts: Autonomous Coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)

## License

MIT
