# Long-Runner Harness

> 长时间运行 Agent 的自动化框架

基于 Anthropic 官方 autonomous-coding 模式，实现 Dual-Agent 架构 + Browser-First Testing + Defense-in-Depth Security。

## 特性

- **Dual-Agent 模式** - Initializer Agent + Coding Agent 协作
- **Browser-First Testing** - 通过 Playwright MCP 进行真实浏览器 UI 验证
- **Defense-in-Depth Security** - 多层安全防护
- **自动调度** - 智能选择下一个功能并执行

## 安装

将文件复制到 Claude Code 的 skills 目录：

```bash
cp -r . ~/.claude/skills/long-runner-harness/
```

## 使用

```bash
# 初始化
/long-runner init

# 继续执行
/long-runner continue
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `SKILL.md` | 完整的 skill 定义和文档 |
| `dispatch.sh` | 调度器脚本 |

## 参考

- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude Quickstarts: Autonomous Coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)

## License

MIT
