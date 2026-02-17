# Long-Runner Harness

> 长时间运行 Agent 的自动化框架 / Automation Framework for Long-Running Agents

基于 Anthropic 官方 autonomous-coding 模式，实现 Dual-Agent 架构 + Browser-First Testing + Defense-in-Depth Security。

Based on Anthropic's official autonomous-coding pattern, implementing Dual-Agent Architecture + Browser-First Testing + Defense-in-Depth Security.

## 特性 / Features

- **Dual-Agent 模式** - Initializer Agent + Coding Agent 协作
- **Dual-Agent Mode** - Initializer Agent + Coding Agent collaboration
- **Browser-First Testing** - 通过 Playwright MCP 进行真实浏览器 UI 验证
- **Browser-First Testing** - Real browser UI verification via Playwright MCP
- **Defense-in-Depth Security** - 多层安全防护
- **Defense-in-Depth Security** - Multi-layer security protection
- **自动调度** - 智能选择下一个功能并执行
- **Auto-Dispatch** - Intelligently select and execute the next feature
- **Session 隔离** - 每个功能在独立 session 中执行，避免上下文过长
- **Session Isolation** - Each feature runs in an isolated session to avoid context length issues

## 安装 / Installation

将文件复制到 Claude Code 的相应目录：

Copy files to the corresponding directories in Claude Code:

```bash
# 复制 skill 文件 / Copy skill files
cp SKILL.md dispatch.sh ~/.claude/skills/long-runner-harness/

# 复制 command 文件 / Copy command files
cp commands/long-runner.md ~/.claude/commands/

# 复制调度脚本 / Copy dispatch script
cp scripts/long-runner-dispatch.sh ~/.claude/scripts/
```

## 使用 / Usage

```bash
# 初始化新项目 / Initialize new project
/long-runner init "项目描述"

/long-runner init "project description"

# 继续执行（单步）/ Continue execution (single step)
/long-runner continue

# 全自动模式 / Full auto mode
/long-runner auto

# 批量模式（每次5个功能）/ Batch mode (5 features per run)
/long-runner auto --batch 5

# 查看进度 / View progress
/long-runner status

# 从中断恢复 / Resume from interruption
/long-runner resume
```

## 目录结构 / Directory Structure

```
.
├── README.md                        # 本文档 / This file
├── SKILL.md                         # Skill 定义文件 / Skill definition
├── dispatch.sh                      # Skill 调度脚本 / Skill dispatch script
├── commands/
│   └── long-runner.md               # Command 定义文件 / Command definition
└── scripts/
    └── long-runner-dispatch.sh      # 自动调度器脚本 / Auto-dispatcher script
```

## 项目结构（运行时） / Project Structure (Runtime)

```
project/
├── feature_list.json      # 功能列表 / Feature list
├── init.sh                # 启动脚本 / Startup script
├── claude-progress.txt    # 进度日志 / Progress log
├── app_spec.txt           # 项目规格说明 / Project specification
├── .claude_settings.json  # 自动化权限配置 / Automation permission config
├── evidence/              # 浏览器测试截图 / Browser test screenshots
└── docs/plans/            # 实现计划 / Implementation plans
```

## 参考 / References

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude Quickstarts: Autonomous Coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)

## License

MIT
