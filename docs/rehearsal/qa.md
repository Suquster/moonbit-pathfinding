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

> 生产级 ALT（`src/directed/alt.mbt`）已在真实 OSM 路网上拿到实测证据：北京驾车网 ALT 双向 A* 相对双向 Dijkstra **6.54×**（k=16 farthest 选点），证据归档 `benches/results/osm-alt-hl-native-2026-07-08.md`（历史对照：`alt-indexed-osm-20260705.md`）。
>
> 正确性不靠口头保证：INF 统一截断保证下界可采纳且一致（不存在早停次优问题），并有差分 PBT 与 OSM 全量对拍守卫。
>
> 同时诚实报告边界：合成随机图（expander）上三角不等式下界退化为零，故跨语言对比基准侧维持零启发式——该证伪实验也归档在同一文件，说明每个数字都区分输入分布。

---

## Q3：CH 的加速比能保证吗？

**30 秒应答**：

> 能，而且是真实路网实测而非引用论文数字：生产级 CH（`src/directed/ch.mbt`，edge-difference 懒更新收缩序 + witness 搜索 + stall-on-demand）在 OSM 北京驾车网 **132 µs/查询，相对双向 Dijkstra 46.7×**（相对单向 Dijkstra 103.6×），厦门 17.8×；预处理北京 25.0 s。2026-07-08 重跑与 07-05 首次归档同口径复现。
>
> 在 CH 之上还有完整上层建筑：Hub Labeling 距离查询 **0.47 µs（13279×）**、PHAST 一到全 6.27×、many-to-many 距离表 16–27×、RPHAST 目标子集再 7.2–9.4×。
>
> 每个数字都附全量对拍一致性校验 + 差分 PBT，最新实测归档 `benches/results/osm-real-networks-ch-native-2026-07-08.md`、`osm-alt-hl-native-2026-07-08.md`（调参轨迹与回本分析见 `ch-osm-20260705.md`），论文到代码追溯在 `docs/verification/paper-to-code-advanced.md`。
---

## Q4：相对 Rust pathfinding，这个项目不可替代的价值是什么？

**30 秒应答**：

> 我不会用绝对化口号贬低 Rust pathfinding。Rust pathfinding 是成熟库，本项目的价值在 MoonBit 生态和工程证据链：
>
> 1. MoonBit 原生 API，填补生态图算法库空白。
> 2. successor function 风格适合 AI Agent 生成调用代码，也适合真实项目把数组、Map 或外部数据源接入。
> 3. `README.mbt.md` 可被 `moon test` 执行，文档不是静态宣传页。
> 4. runtime proof predicates 让路径合法性、代价一致性、BFS minimality 变成可运行检查。
> 5. 8 种前沿路网算法（CH / ALT / HL / PHAST / RPHAST / m2m / CCH / JPS）Rust pathfinding 均未提供，且附真实 OSM 路网实测证据（2026-07-08 重跑，北京 CH 46.7×、HL 13279×、CCH 换权 13.1×）。
> 6. 跨语言等价工作负载对比基础设施（`bench_rust/` + 逐位一致随机源 + 黄金交叉校验）把“和 Rust 比”变成可复现命令而非口号。
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
| 性能质疑 | 只报已归档实测数字（OSM 北京/厦门） | 指向 benches/results 工件与复现命令 | 说明对拍/PBT 正确性守卫 |
| 证明质疑 | 区分 runtime predicates 和 static prove | 展示 `src/proofs` | 说明升级路径 |
| 创新性质疑 | 避免贬低成熟库 | 强调 MoonBit 原生和证据链 | 回到官方评分项 |
| 测试质疑 | 强调测试类型 | 举一个抓语义的测试 | 说明还会补哪些边界 |

---

## 演练归档

- 演练 1：`docs/rehearsal/practice_run_1.m4a`（待录制）
- 演练 2：邀请同学或实验室同事模拟评委提问

每次演练后更新本文件，把新出现的问题和更稳的回答加进去。
