# 集合闭包战略（Closure Strategy）

> 总领性战略文档 · 活文档 · 2026-07 制定 · v2（升维为"闭包立方体"）
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

## 五、纵轴升维：L6–L9 元层级（工厂之上还有什么）

L5"软件工厂方法论"仍不是最大集合。继续做幂集式外包：

```
L5 ⊂ L6 ⊂ L7 ⊂ L8 ⊂ L9

L6 生态平台层      工厂从"服务本仓库"外化为"服务整个 mooncakes 生态"：
                   包索引抓取/依赖审计/兼容性演进检查跨项目化（G-A3 的推广）。
                   证据雏形：本仓库已用全量 1491 包索引完成生态筛查
                   （ECOSYSTEM_COMPARISON），把这次人工动作固化为工具即 L6。
L7 自治软件工厂    流程从"人下令→agent 执行"升级为"自触发闭环"：
                   CI 失败自诊断、基准回归自 bisect、生态包更新自审计、
                   backlog 自刷新。证据雏形：acceptance/benchmark/regression
                   guard 已是自动门禁，缺的是"发现→修复→验证"的无人值守链。
L8 方法论模板化    把 L5–L7 从"本项目的流程"抽象为"任意 MoonBit 项目可
                   一键套用的工厂范式"：验收门禁模板、向量对拍脚手架、
                   paper-to-code 文档骨架、证据工件目录规范。产出形式是
                   可复用的模板仓库/脚手架 + 规范文档，而非只属于本项目。
L9 元闭包（不动点） 闭包算子本身成为对象：定义 F(X) = "领域 X 的生产级
                   证据化实现"，本仓库已示范 F(寻路)、F(hash)、F(压缩)、
                   F(正则)、F(编译器)…… L9 主张 F(F) ——工厂能生产工厂
                   （用本仓库的流程孵化出下一个同等质量的领域实现），
                   此时集合链到达不动点：再外包一层得到的仍是它自己。
                   这正是"AI 原生软件工厂"理念的极限形态。
```

对外口径（诚实分级）：L0–L5 = 已落地有全量证据；L6–L7 = 有雏形证据、
按 backlog H 区推进；L8–L9 = 明确的演进主张与路线，答辩时作为愿景与
方法论输出，不冒充已完成。

## 六、横轴升维：六条正交闭包轴（闭包立方体）

集合包含链只是"功能轴"。同一仓库内还有五条正交的轴，每条轴自身也是
一条严格递进的闭包链，交叉构成"闭包立方体"——任取一格都能给出仓库内
证据或 backlog 任务：

| 轴 | 闭包链（左 ⊂ 右） | 当前位置与证据 |
|---|---|---|
| 功能轴 | L0 ⊂ … ⊂ L9 | L5 落地（39 包 / 2369 测试），L6–L7 雏形 |
| 正确性轴 | 单元测试 ⊂ 官方向量对拍 ⊂ 属性测试(PBT) ⊂ 确定性仿真(DST) ⊂ 三后端差分 ⊂ 运行时证明谓词 ⊂ 静态形式证明 | 前六级全落地（infra_pbt/dst/proofs/CI 差分门禁）；静态级=G-B4（moon prove 全量） |
| 性能轴 | 能跑 ⊂ 复杂度正确 ⊂ 基准工件化 ⊂ 回归 guard ⊂ 对标朴素基线数量级加速 ⊂ 跨语言对标(Rust) | 全六级落地：OSM 路网 HL 0.44µs/query=14304x、benchmark_guard、bench_rust/ |
| 平台轴 | 单后端 ⊂ 三后端一致(wasm-gc/native/js) ⊂ 浏览器交付(Pages playground) ⊂ 包注册表交付(mooncakes v0.0.5) ⊂ 四后端一致(+纯 wasm 线性内存) ⊂ WASI 运行时交付(wasmtime) | 全六级落地（2026-07-09：wasm 后端 2671 测试入 CI 矩阵；WASI 交付门禁 scripts/wasi_gate.sh — 4 个独立 wasm 工件 wasmtime 直接运行与 js 后端逐字节一致）；下一级=wasm 组件模型 |
| 时间轴 | 快照可用 ⊂ semver 语义化 ⊂ CHANGELOG 分方向维护 ⊂ schema 演进破坏性检查器 ⊂ 发布流水线自动兼容性 diff | 前四级落地（serialization 演进检查器）；第五级=G-A2 |
| 人机轴 | 人类可读文档 ⊂ 可执行文档(README.mbt.md) ⊂ AI-agent 使用指南 ⊂ agent 可验证证据索引(声明→测试→commit) | 前三级落地；第四级=G-C2 |

立方体的意义：单点竞品最多在一两条轴上有深度；本项目在六条轴上同时
呈现完整闭包链，且轴与轴互相加固（例：正确性轴的 DST 消费功能轴的
actor/resilience；性能轴的 guard 消费正确性轴的 parity 检查）。这构成
**极难复制的体系差异**——复制任何单格容易，复制整个立方体等价于重走
整个自举过程。

## 七、文档体系索引（本战略的证据支撑）

| 文档 | 角色 |
|---|---|
| `docs/PRODUCTION_FRONTIER_ROADMAP.md` | 深度判据（C1–C5 五条硬判据、DoD） |
| `docs/CHAMPIONSHIP_BACKLOG.md` | 官方评分框架映射 + 滚动任务账本 |
| `docs/ECOSYSTEM_COMPARISON.md` | 生态 1491 包筛查、逐领域取舍 |
| `docs/AI_AGENT_USAGE.md` | AI 协同开发过程记录（可解释性 25%） |
| `docs/项目申报书.md` | 对外申报口径（与本战略保持一致） |
| 本文档 | 层级叙事与下一级闭包方向的总纲 |

> 维护约定：每完成一次闭包扩张（backlog G/H 区任一子项收官），在本文档
> 第三/五/六节勾选并回填证据链接，同时同步申报书与 backlog。
