# Long-Runner Harness

> 长时间运行 Agent 的自动化框架

[English Version](./README.md)

基于 Anthropic 官方 autonomous-coding 模式，实现 Dual-Agent 架构 + Browser-First Testing + Defense-in-Depth Security。

## 特性

- **Dual-Agent 模式** - Initializer Agent + Coding Agent 协作
- **Browser-First Testing** - 通过 Playwright MCP 进行真实浏览器 UI 验证
- **Defense-in-Depth Security** - 多层安全防护
- **自动调度** - 智能选择下一个功能并执行
- **Session 隔离** - 每个功能在独立 session 中执行，避免上下文过长

## 安装

将文件复制到 Claude Code 的相应目录：

```bash
# 复制 skill 文件
cp SKILL.md dispatch.sh ~/.claude/skills/long-runner-harness/

# 复制 command 文件
cp commands/long-runner.md ~/.claude/commands/

# 复制调度脚本
cp scripts/long-runner-dispatch.sh ~/.claude/scripts/
```

## 使用

```bash
# 初始化新项目
/long-runner init "项目描述"

# 继续执行（单步）
/long-runner continue

# 全自动模式
/long-runner auto

# 批量模式（每次5个功能）
/long-runner auto --batch 5

# 查看进度
/long-runner status

# 从中断恢复
/long-runner resume
```

## 目录结构

```
.
├── README.md                        # English version
├── README-zh.md                     # 本文档
├── SKILL.md                         # Skill 定义文件
├── dispatch.sh                      # Skill 调度脚本
├── commands/
│   └── long-runner.md               # Command 定义文件
└── scripts/
    └── long-runner-dispatch.sh      # 自动调度器脚本
```

## 项目结构（运行时）

```
project/
├── feature_list.json      # 功能列表
├── init.sh                # 启动脚本
├── claude-progress.txt    # 进度日志
├── app_spec.txt           # 项目规格说明
├── .claude_settings.json  # 自动化权限配置
├── evidence/              # 浏览器测试截图
└── docs/plans/            # 实现计划
```

## 参考

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude Quickstarts: Autonomous Coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)

## License

MIT
