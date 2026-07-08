# 集合闭包战略（Closure Strategy）

> 总领性战略文档 · 活文档 · 2026-07 制定
>
> 核心思想：**本项目不是官方推荐清单里的一个"点"，而是一条不断向外闭包的
> "集合链"**。寻路是种子集合 L0；每当为把当前集合做到生产级而必须引入的
> 支撑能力自身长成完整子系统时，就完成一次闭包扩张，得到一个真包含前者的
> 更大集合。当前仓库已实际闭包到 L5——与大赛核心理念"AI 原生软件工厂"
> 同构。这是差异化壁垒：**评审看到的不是单点作品，而是层层自举、证据链
> 完整的软件工厂切片**。

## 一、闭包层级总览（每层真包含前一层，均已落地）

```
L0 ⊂ L1 ⊂ L2 ⊂ L3 ⊂ L4 ⊂ L5

L0 寻路核心        BFS/Dijkstra/A*/Bellman-Ford/Yen/JPS/ALT/CH/CCH/Hub Labeling
                   + 真实 OSM 路网基准（厦门 2.4 万 / 北京 16.4 万节点）
L1 通用图算法      流(Dinic/MCMF)/匹配(Hopcroft-Karp/KM)/MST/SCC/桥割点/欧拉/
                   全对最短路 —— src/directed|undirected|unweighted|advanced|graph
L2 验证基础设施    proofs(可执行证明谓词)/infra_pbt/dst(确定性模拟测试)/
                   infra_fuzz/infra_bench —— "如何证明 L0/L1 是对的"自身成为子系统
L3 通用基础软件    infra_hash|compress|time|diff|cli|resilience|config|codec|
                   text|ds|metrics|timer|alloc + logging + serialization + actor
                   —— "支撑 L2 工程闭环"的基础库层，19+ 包、全 RFC/FIPS 向量对拍
L4 语言工程工具链  mini_compiler|regex_engine|lsp_server|lsp_binding|
                   parser_combinator|codegen_infra|build_tool|docgen|playground
                   —— "处理源代码与文档本身"的工具层
L5 AI 原生软件工厂 acceptance 4 门禁|黄金向量对拍法|paper-to-code 追溯|
   （方法论输出）   三后端差分 CI|证据工件(benches/results, docs/verification)|
                   AI_AGENT_USAGE.md —— 可复用、可演进、可持续的工程流程本身
```

关键数字：39 个源码包、~15 万行 MoonBit、2369 测试全绿、acceptance 4 门禁、
三后端（wasm-gc/native/js）差分一致性 CI。

## 二、为什么"闭包叙事"是夺冠策略

1. **官方推荐清单是公共信息**，人人可选（电子表格/数据库内核/文档引擎…）；
   单点作品之间只能拼单点深度。闭包链叙事把评审的比较维度从"这个点做得
   多好"切换到"这条自举链有多完整"——后者无法被单点作品复制。
2. **与大赛核心理念同构**：章程原文要求把开发过程变为"可复用、可演进、
   可持续的软件工程流程"。L5 层的 acceptance 门禁 + 向量对拍法 + 证据工件
   正是这个流程的实体化，且已经在 L0–L4 上反复复用验证（每一轮补深都走
   同一条流水线）。
3. **四个评审维度全覆盖**：完成度（可构建/可复现，acceptance 一键验收）、
   工程质量（2369 测试、零告警、三后端门禁）、可解释性（paper-to-code、
   ECOSYSTEM_COMPARISON、AI_AGENT_USAGE）、用户体验（mooncakes 发布、
   playground、可执行 README）。
4. **每层互为消费方（自举证明）**：L3 的 hash 给 L2 的 bench 做指纹，
   L3 的 diff 给 L4 的 docgen 做回归对比，L4 的 regex 给 L3 的 text 做
   检索，L2 的 PBT 反过来测 L0–L4 所有层。集合之间不是并列堆料，而是
   有向依赖闭环——这直接回答"是否重复造轮子"：每个轮子都有链内真实
   消费方。

## 三、下一级闭包候选（L5 → L6 的三条扩张方向）

按"专精一个做完再做别的"原则排序，每条都是把现有集合再包一层：

### 方向 A（宽度闭包）：从"单模块工厂"到"多模块工作区"
现状是一个 module 内 39 个包；更大的集合是**跨 module 的工程编排**。
- A1 build_tool 深化为真实多包工作区模型（依赖图求解、增量构建计划、
  与 moon.mod 语义对拍）
- A2 release_aggregate 扩为生态级发布流水线（semver 兼容性 diff ——
  用自家 serialization 的 schema 演进检查器吃自己的狗粮）
- A3 mooncakes_protocol 类能力：包索引抓取/依赖审计（供 ECOSYSTEM_COMPARISON
  自动刷新，把"生态筛查"本身自动化成工具）

### 方向 B（深度闭包）：从"实现对标"到"性能/形式化前沿"
- B1 hash/compress 流式增量 API（对标 Go hash.Hash / zlib z_stream 状态机）
- B2 zstd 帧格式解码（RFC 8878 子集，接上已有 LZ4/DEFLATE 家族）
- B3 regex 惰性 DFA + bounded backtracking（对标 Rust regex hybrid 引擎）
- B4 proofs 从运行时谓词升级到更强静态证据（moon prove 全量接入）

### 方向 C（广度闭包）：从"库集合"到"可运行系统"
把 L0–L4 组装成端到端应用切片，证明集合的组合价值：
- C1 路网服务样例：OSM 解析(L3 codec)→CH 预处理(L0)→CLI/补全(L3 cli)→
  metrics/logging(L3)→resilience 包裹(L3)→playground 可视化(L4)
- C2 "软件工厂自述"：用自家 docgen+diff+hash 为整个仓库生成可校验的
  证据索引（每个声明→测试→commit 的三元组），答辩时现场可复现

## 四、文档体系索引（本战略的证据支撑）

| 文档 | 角色 |
|---|---|
| `docs/PRODUCTION_FRONTIER_ROADMAP.md` | 深度判据（C1–C5 五条硬判据、DoD） |
| `docs/CHAMPIONSHIP_BACKLOG.md` | 官方评分框架映射 + 滚动任务账本 |
| `docs/ECOSYSTEM_COMPARISON.md` | 生态 1491 包筛查、逐领域取舍 |
| `docs/AI_AGENT_USAGE.md` | AI 协同开发过程记录（可解释性 25%） |
| `docs/项目申报书.md` | 对外申报口径（与本战略保持一致） |
| 本文档 | 层级叙事与下一级闭包方向的总纲 |

> 维护约定：每完成一次闭包扩张（新方向 A/B/C 中任一子项收官），在本文档
> 第三节勾选并回填证据链接，同时同步申报书与 backlog。
