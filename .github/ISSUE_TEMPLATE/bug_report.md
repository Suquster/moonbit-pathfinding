---
name: "\U0001F41B Bug Report / Bug 报告"
about: "Report a bug in moonbit-pathfinding to help us improve / 报告一个 bug 以帮助我们改进"
title: "[BUG] <short description / 简短描述>"
labels: ["bug", "triage"]
assignees: []
---

<!--
Thanks for taking the time to file a bug! Please fill in as much of the
template below as you can. Items with 🟢 are required; 🔵 are optional.

感谢您花时间提交 bug 报告！请尽可能完整地填写下方模板。
🟢 为必填项，🔵 为可选项。
-->

## 🟢 Describe the bug / 问题描述

<!-- A clear and concise description of what the bug is.
清晰、简洁地描述该 bug。 -->



## 🟢 Reproduction steps / 复现步骤

<!-- Steps to reproduce the behaviour.
复现该行为的步骤。 -->

1.
2.
3.

## 🟢 Expected behavior / 预期行为

<!-- What did you expect to happen?
您预期会发生什么？ -->



## 🟢 Actual behavior / 实际行为

<!-- What actually happened? Include the full error message or stack trace
if any. 实际发生了什么？如有错误信息或堆栈，请粘贴完整内容。 -->

```
<paste error output here / 在此粘贴错误输出>
```

## 🟢 Environment / 运行环境

<!-- Please complete the following information.
请补全以下信息。 -->

- **MoonBit toolchain version / MoonBit 工具链版本**
  (run `moon version --all` / 执行 `moon version --all`):
  ```
  <paste output here>
  ```
- **OS / 操作系统**: <!-- e.g. Windows 11 23H2 / macOS 14.5 / Ubuntu 22.04 -->
- **Architecture / 架构**: <!-- e.g. x86_64 / aarch64 / loongarch64 -->
- **Backend / 后端**: <!-- ☐ wasm-gc  ☐ js  ☐ native  ☐ all / 全部 -->
- **moonbit-pathfinding version / 版本**: <!-- e.g. 0.2.0 / git commit hash -->
- **Install source / 安装来源**: <!-- ☐ mooncakes.io  ☐ git clone  ☐ local path -->

## 🟢 Minimal code to reproduce / 最小复现代码

<!-- Please provide a minimal, self-contained MoonBit snippet that triggers
the bug. Prefer the smallest graph / input that still reproduces it.
请提供能够独立复现问题的最小 MoonBit 代码片段，尽量使用能触发 bug 的最小图/输入。 -->

```moonbit
// moon.mod.json deps: "Suquster/moonbit-pathfinding": "x.y.z"
fn main {
  // ...
}
```

## 🔵 Which algorithm is affected? / 涉及哪个算法？

<!-- Tick all that apply / 勾选全部相关项 -->

- [ ] BFS / DFS
- [ ] Dijkstra
- [ ] A\* / IDA\*
- [ ] Bellman-Ford
- [ ] Floyd-Warshall
- [ ] Bidirectional BFS
- [ ] Yen k-shortest
- [ ] Kruskal MST
- [ ] Tarjan SCC / Topological Sort
- [ ] Connected Components
- [ ] Kuhn-Munkres / Edmonds-Karp
- [ ] Graph data structure / 图数据结构
- [ ] Documentation / 文档
- [ ] Other / 其他:

## 🔵 Regression / 回归信息

<!-- Did this work in a previous version? If yes, which one?
之前的版本能正常工作吗？如果可以，请注明具体版本。 -->

- Last known good version / 最后一个正常版本:
- First broken version / 首次出现问题的版本:

## 🔵 Additional context / 其他上下文

<!-- Add any other context, screenshots, profiling data, or links to related
issues / discussions. 可附加其他上下文、截图、性能数据，或相关 issue/讨论链接。 -->



## ✅ Checklist / 提交前自查

- [ ] I have searched existing issues and this is not a duplicate.
      我已搜索现有 issue 且本问题不是重复报告。
- [ ] I have tested against the latest `main` branch or the latest
      published version. 我已在最新 `main` 分支或最新发布版本上验证过。
- [ ] My reproduction code is minimal and self-contained.
      我提供的复现代码是最小且自包含的。
- [ ] I have included the `moon version --all` output.
      我已附上 `moon version --all` 的输出。
