# Long-Runner Harness

> 长时间运行 Agent 的自动化框架

[English Version](./README.md)

基于 Anthropic 官方 autonomous-coding 模式，实现 Dual-Agent 架构 + Browser-First Testing + Defense-in-Depth Security + Meta-Harness Trace Store。

## 特性

- **双 Agent 辩论 (v5.1)** - init 阶段并行启动提案者 + 评审者 Agent，对技术方案和功能列表进行辩论审查
- **Brainstorm 集成** - 提案者 Agent 先调用 superpowers:brainstorm skill 进行头脑风暴（不可用时自动回退）
- **Trace Store** - 完整 session trace 存储在 `.long-runner/` 目录，支持跨 session 学习
- **环境 Bootstrap** - 自动探测项目环境，消除每轮 2-3 次探索浪费
- **因果假设** - 调试时显式写因果链，支持跨 session 学习
- **Pareto 追踪** - 多维 metric 追踪（功能、视觉质量、控制台错误），不只单一 pass/fail
- **Browser-First Testing** - 通过 Playwright MCP 进行真实浏览器 UI 验证
- **Defense-in-Depth Security** - 多层安全防护（沙箱 + 文件系统 + 命令白名单）
- **自动调度** - 智能选择下一个功能并执行，自动解析依赖关系
- **Session 隔离** - 每个功能在独立 session 中执行，避免上下文过长

## 更新日志

### v5.1
- **双 Agent 辩论**：init 阶段并行运行提案者（含 brainstorm skill）+ 评审者，综合结果生成最终 feature_list
- **Superpowers 集成**：Agent A 调用 `superpowers:brainstorm` skill；不可用时回退到直接生成
- 通过对抗式审查避免低质量功能列表，在编码开始前就保证需求质量

### v5.0
- **Trace Store**：`.long-runner/` 目录，包含 traces、hypotheses、pareto metrics、summaries
- **环境 Bootstrap**：自动生成 `env-snapshot.json`，每个 session 少 2-3 次探索
- **因果假设**：结构化假设追踪，调试时写因果链（Meta-Harness 论文附录 A.2）
- **Pareto Metrics**：多目标优化，取代单一 pass/fail
- **新增命令**：`diagnose`、`pareto`、`resume` 子命令
- 基于 [Meta-Harness 论文](https://arxiv.org/abs/2603.28052) 洞察

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
# 初始化新项目（含双 Agent 辩论）
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

# 诊断：trace 分析 + 未解决的假设
/long-runner diagnose

# Pareto 前沿可视化
/long-runner pareto
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
├── docs/plans/            # 实现计划
└── .long-runner/          # v5 Trace Store
    ├── meta.json              # 版本 + 元信息
    ├── bootstrap/
    │   └── env-snapshot.json  # 自动生成的环境快照
    ├── traces/
    │   ├── index.json         # trace 索引
    │   └── {session_id}.trace.json
    ├── hypotheses/
    │   ├── {session_id}.hypothesis.json
    │   └── open.md            # 当前未解决的假设
    ├── pareto/
    │   ├── metrics.json       # 多维 metric
    │   └── frontier.json      # Pareto 前沿
    └── summaries/
        └── {session_id}.summary.md
```

## 参考

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude Quickstarts: Autonomous Coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)
- [Meta-Harness: End-to-End Optimization of LLM Harnesses](https://arxiv.org/abs/2603.28052)

## License

MIT
