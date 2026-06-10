# 答辩 Q&A 稿 · 5 个挑战性问题

> 对应 tasks.md 46.1 / Requirement R25.4
>
> 每个回答先给边界，再给证据，最后给升级路径。核心原则：宁可少说一点，也必须能被仓库复现。

---

## Q1：你说 proof predicates，但 `moon prove` 不是还没稳定吗？

**30 秒应答**：

> 是的，当前我不会把它包装成“静态形式化证明已完成”。本项目已完成的是可执行合约基础设施：
>
> 1. `src/proofs/predicates.mbt` 定义路径合法、可达性、路径代价、非负权等共享谓词。
> 2. `src/proofs/bfs_proof.mbt` 与 `src/proofs/dijkstra_proof.mbt` 把 BFS / Dijkstra 的前后置条件编码成返回 `Bool` 的 MoonBit 函数。
> 3. BFS minimality 已经从无条件 true 升级为有界 BFS shortest-path witness，并由 `src/proofs/bfs_proof_test.mbt` 覆盖最短路、非最短路、非法路径。
>
> 所以当前硬证据是 runtime-checked proof predicates；`moon prove` 是工具链稳定后的升级路径，不是当前验收事实。

---

## Q2：你的 ALT 实现可能退化，那相对 Dijkstra 还有什么价值？

**30 秒应答**：

> 当前 ALT 的首要目标是正确性而不是抢跑性能数字。对有向图，如果启发式 admissible 但不 consistent，A* 早停可能返回次优解，所以实现必须谨慎。
>
> 目前的价值有三点：一是 landmark 预处理和三角不等式启发式已经落地；二是测试可以和 Dijkstra 做结果对照；三是 native benchmark guard 已经能把基础回归记录成 artifact。
>
> 下一阶段我会补更强的 ALT 专项证据：记录真实输入图、查询对、扩展节点数和 Dijkstra 对照，再决定是实现 reopen closed nodes，还是只在 consistent heuristic 下启用早停。

---

## Q3：CH 预处理还没有精细收缩顺序，加速比能保证吗？

**30 秒应答**：

> 不能直接保证论文级巨大加速，这类数字必须来自具体路网、具体机器和具体实现策略。当前 CH 的定位是正确性版本：预处理、shortcut、双向查询和路径展开链路先打通。
>
> 我会用两类证据回答：源码在 `src/advanced/ch.mbt`，测试在 advanced 包；答辩时只承诺“实现与正确性验证正在完善”，不承诺未记录的加速比。
>
> 真正的性能叙事要等 edge-difference 收缩顺序、lazy update、witness search 调参和真实路网 benchmark artifact 一起完成；当前 native benchmark guard 只作为回归证据，不包装成论文级加速比。

---

## Q4：相对 Rust pathfinding，这个项目不可替代的价值是什么？

**30 秒应答**：

> 我不会用绝对化口号贬低 Rust pathfinding。Rust pathfinding 是成熟库，本项目的价值在 MoonBit 生态和工程证据链：
>
> 1. MoonBit 原生 API，填补生态图算法库空白。
> 2. successor function 风格适合 AI Agent 生成调用代码，也适合真实项目把数组、Map 或外部数据源接入。
> 3. `README.mbt.md` 可被 `moon test` 执行，文档不是静态宣传页。
> 4. runtime proof predicates 让路径合法性、代价一致性、BFS minimality 变成可运行检查。
> 5. CH / JPS / ALT 已有 MoonBit 实现，native benchmark guard 已可复现；后续用真实路网 benchmark artifact 补齐性能叙事。
>
> 也就是说，我的差异化不是“语言换皮”，而是把 MoonBit 的多后端、可执行文档和未来证明链路组合成一个可交付库。

---

## Q5：怎么证明测试不是“灌水凑数”？

**30 秒应答**：

> 我用测试类型而不是数字回答。第一，README doctest 能防用户入口过时；第二，proof tests 专门覆盖合约谓词；第三，属性测试和 fuzz 是跨算法对照，不是单点 happy path；第四，`scripts/acceptance.ps1` 把 check、fmt、test、doc、doc audit、coverage gate 串起来。
>
> 举个具体例子：BFS minimality 现在会拒绝更长但合法的路径，这个测试直接对应“最短路”语义，而不是为了提高覆盖率随便加断言。
>
> 后续会继续补负例和边界：不可达、单节点、重复边、负权、断连图、空图等都要按算法适配。

---

## 通用应答原则

| 问题类型 | 第一句 | 第二句 | 第三句 |
|----------|--------|--------|--------|
| 功能完整度 | 先给当前版本边界 | 列文件和命令证据 | 给下一步验收条件 |
| 性能质疑 | 不报未测数字 | 区分 native 回归证据和真实路网缺口 | 承诺 artifact 格式和对照方法 |
| 证明质疑 | 区分 runtime predicates 和 static prove | 展示 `src/proofs` | 说明升级路径 |
| 创新性质疑 | 避免贬低成熟库 | 强调 MoonBit 原生和证据链 | 回到官方评分项 |
| 测试质疑 | 强调测试类型 | 举一个抓语义的测试 | 说明还会补哪些边界 |

---

## 演练归档

- 演练 1：`docs/rehearsal/practice_run_1.m4a`（待录制）
- 演练 2：邀请同学或实验室同事模拟评委提问

每次演练后更新本文件，把新出现的问题和更稳的回答加进去。
