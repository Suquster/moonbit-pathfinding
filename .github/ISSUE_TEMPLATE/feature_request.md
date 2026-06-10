---
name: "\u2728 Feature Request / 功能请求"
about: "Suggest a new algorithm, API, or improvement / 建议新算法、新 API 或改进"
title: "[FEATURE] <short description / 简短描述>"
labels: ["enhancement", "triage"]
assignees: []
---

<!--
Thanks for proposing an improvement! Filling in the template helps us
evaluate scope, priority, and mapping to the OSC-2026 roadmap.

感谢您提出改进建议！完整填写模板有助于我们评估范围、优先级，
以及与 OSC-2026 路线图的对应关系。
-->

## 🟢 Use case / 使用场景

<!-- What problem are you trying to solve? What does your workflow look
like today without this feature? Who benefits from it?
您想解决的问题是什么？在没有该功能之前，您目前的工作流是怎样的？
谁将从中受益？ -->



## 🟢 Proposed solution / 建议方案

<!-- Describe the API, algorithm, or behaviour you would like to see.
Pseudocode or a tentative MoonBit signature is very welcome.
描述您期望的 API、算法或行为。欢迎附上伪代码或初步的 MoonBit 签名。 -->

```moonbit
// Tentative signature / 初步签名:
pub fn my_new_algo[N : Hash + Eq](
  start : N,
  successors : (N) -> Array[N],
  // ...
) -> Option[Array[N]] {
  ...
}
```

## 🟢 Alternatives considered / 已考虑的替代方案

<!-- What other approaches did you look at? Why are they insufficient?
您考虑过哪些替代方案？为何它们无法满足需求？ -->

1.
2.

## 🟢 Which requirement does this map to? / 对应哪条需求？

<!-- moonbit-pathfinding is developed against a spec with 25 numbered
requirements (see `.kiro/specs/moonbit-pathfinding/requirements.md`).
Please help us locate the closest match, or mark "new requirement" if
this introduces a brand-new capability.

本项目依据 25 条编号需求进行开发 (见
`.kiro/specs/moonbit-pathfinding/requirements.md`)。
请指出最接近的需求编号；如为全新能力，请勾选 "new requirement"。 -->

- [ ] R1 MVP 算法 (BFS/DFS/Dijkstra/A*/BF/FW/Kruskal/CC)
- [ ] R2 进阶算法 (IDA*/Bi-BFS/Yen/SCC/Topo/KM/Edmonds-Karp)
- [ ] R3 统一 Successor API
- [ ] R4 泛型节点类型
- [ ] R5 工程基线 (CI/格式化)
- [ ] R6 测试覆盖率
- [ ] R7 文档 & Doc_Comment
- [ ] R8 形式化证明 (moon prove)
- [ ] R9 性能基准
- [ ] R10 示例程序
- [ ] R11 包元数据 / mooncakes.io 发布
- [ ] R12 错误处理与类型
- [ ] R13 PBT 属性测试
- [ ] R14 基准运行器
- [ ] R15 社区运营
- [ ] R16 Playground
- [ ] R17 多后端 (wasm-gc / js / native)
- [ ] New requirement / 新需求 (please describe below / 请在下方描述)

Closest requirement ID / 最接近的需求编号:

## 🟢 Tier classification / 档位归属

<!-- Our spec classifies deliverables into three tiers. Which tier does
this feature best fit?

本项目将交付物划分为三档，此功能最适合哪一档？ -->

- [ ] **Tier-1 保底档** — foundational correctness or MVP coverage gap
- [ ] **Tier-2 优秀档** — advanced algorithm, PBT, benchmark, or community
- [ ] **Tier-3 冠军档** — formal verification, multi-backend, playground
- [ ] Not sure / 不确定

## 🔵 Backend impact / 后端影响

<!-- Does the feature behave differently across MoonBit backends?
该功能在不同 MoonBit 后端上是否行为不同？ -->

- [ ] wasm-gc
- [ ] js
- [ ] native
- [ ] Backend-independent / 与后端无关

## 🔵 Comparable prior art / 参考实现

<!-- Links to equivalent functionality in Rust pathfinding crate,
NetworkX, JGraphT, or academic papers. We value citations heavily.

对标 Rust `pathfinding` crate / Python NetworkX / Java JGraphT 或学术
论文等已有实现的链接。我们高度重视引用来源。 -->

- Rust `pathfinding::` :
- NetworkX `networkx.` :
- Paper / 论文 (BibTeX or DOI):
- Other / 其他:

## 🔵 API compatibility / API 兼容性

<!-- Will this change existing public APIs? Is a breaking release needed?
本改动是否会影响现有公开 API？是否需要破坏性版本升级？ -->

- [ ] Pure addition, no breaking changes / 纯新增，无破坏性改动
- [ ] Extends an existing signature / 扩展现有签名
- [ ] Requires a breaking change (major version bump) / 需要破坏性改动 (大版本升级)

## 🔵 Willing to implement? / 是否愿意贡献实现？

- [ ] I'd like to send a PR myself / 我愿意自己提交 PR
- [ ] I can help with reviews / 我可以协助评审
- [ ] I'm only filing the request / 我只是提出建议

## 🔵 Additional context / 其他上下文

<!-- Mockups, test cases, benchmark expectations, open questions.
可附上示意图、测试用例、基准预期或尚未明确的问题。 -->



## ✅ Checklist / 提交前自查

- [ ] I have searched existing issues and discussions.
      我已搜索现有 issue 与讨论。
- [ ] I have identified the closest requirement ID (or marked "new").
      我已标注最接近的需求编号 (或勾选 "新需求")。
- [ ] I have indicated the relevant tier.
      我已选择对应的档位。
