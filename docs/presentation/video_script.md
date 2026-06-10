# 答辩视频脚本 · 7 分钟

> 对应 tasks.md 44.1 / Requirement R12.1, R12.2, R25.1
>
> 目标：在 7 分钟内让评委记住“MoonBit 原生、证据可复现、未来可升级静态证明”的项目定位。
> 所有镜头必须能在本仓库本地复现；未交付能力只作为路线图讲，不作为当前事实展示。

---

## 时间轴

| 时间 | 段落 | 内容 | 画面 |
|------|------|------|------|
| 0:00-0:10 | Hook | “这是一个 MoonBit 原生路径规划与图算法库，重点是可执行文档和可验证工程证据。” | 标题页 |
| 0:10-0:45 | 问题陈述 | MoonBit 生态需要可复用路径规划库，也需要能被评委和用户复现的质量证据。 | 对比页 |
| 0:45-1:30 | 架构总览 | `src/core`、`src/directed`、`src/undirected`、`src/advanced`、`src/proofs` 五层结构。 | 架构页 |
| 1:30-2:20 | 算法演示 | 运行 `moon run examples/network_routing`，展示 Dijkstra 网络路由输出。 | 终端录屏 |
| 2:20-3:10 | README 即测试 | 运行 `moon test README.mbt.md`，说明 README 示例不是截图而是黑盒测试。 | 终端 + README |
| 3:10-4:10 | Proof predicates | 展示 `src/proofs/bfs_proof.mbt` 与 `src/proofs/bfs_proof_test.mbt`，解释 runtime minimality witness。 | 代码高亮 |
| 4:10-5:00 | 质量保障 | 运行 `scripts\acceptance.ps1 -SkipCoverage`，展示 check/fmt/test/doc/audit 链路。 | 终端录屏 |
| 5:00-5:45 | 高级算法 | 展示 CH/JPS/ALT 源码、测试与 native benchmark guard，明确真实路网加速比仍需 OSM artifact。 | PPT + 文件路径 |
| 5:45-6:30 | 对标与差异化 | 对标 Rust pathfinding：MoonBit 原生、多后端、README doctest、runtime predicates、release evidence。 | 表格页 |
| 6:30-7:00 | 路线图与结尾 | 下一步是边界回归、双语文档/答辩打磨、OSM benchmark 与 playground 取舍。 | 路线图页 |

---

## 关键台词

### Hook (0:00-0:10)

> “大家好，我是 taoyouce。今天展示 moonbit-pathfinding：一个 MoonBit 原生路径规划与图算法库。它的核心卖点不是一句口号，而是可执行文档、运行时 proof predicates 和可复现验收命令。”

### 问题陈述 (0:10-0:45)

> “MoonBit 正在变成可以做严肃工程的语言，但生态里还缺一类基础设施：图算法和路径规划。评委真正关心的也不只是‘我实现了多少算法’，而是这些算法能不能被调用、被测试、被解释、被继续维护。所以这个项目从第一天就按库来做，而不是按 demo 来做。”

### 架构总览 (0:45-1:30)

> “代码分五层。`core` 放 Weight、PQueue、DSU 这些可复用抽象；`unweighted`、`directed`、`undirected` 放基础算法；`advanced` 放 CH、JPS、ALT；`proofs` 放可执行谓词和 BFS/Dijkstra 的合约检查。这样的边界让用户可以只引入需要的包，也让测试能精准定位问题。”

### 算法演示 (1:30-2:20)

> “先看一个实际工作流。这里运行网络路由例子，核心调用就是 Dijkstra：用户提供起点、后继函数和目标判断，库返回路径和总代价。这个 successor function API 很适合 MoonBit，也很适合 AI Agent 生成调用代码，因为它不要求用户先适配复杂 Graph 类型。”

推荐命令：

```powershell
moon run examples/network_routing
```

### README 即测试 (2:20-3:10)

> “README 不是只给人看的。`README.mbt.md` 里的 MoonBit 代码块会被 `moon test README.mbt.md` 当作黑盒测试执行。也就是说，文档过时会直接让验收失败。这一点对开源库非常关键。”

推荐命令：

```powershell
moon test README.mbt.md
```

### Proof predicates (3:10-4:10)

> “现在看最硬的一块：proof predicates。以 BFS 为例，我们检查路径起点、终点、边合法性，并且用有界 BFS witness 检查 minimality。当前这些是运行时可执行 Bool 函数，已经被测试驱动；未来 `moon prove` 语法稳定后，可以把同一套谓词提升到静态证明注解。”

推荐镜头：

```powershell
moon test src/proofs
```

### 质量保障 (4:10-5:00)

> “本地验收脚本把评审关心的证据串成一条命令：`moon check`、格式检查、完整测试、README doctest、`moon doc`、公共 API 注释审计。完整版本还会跑 coverage gate；录屏里可先用 `-SkipCoverage` 展示快速门禁，正式提交前跑完整门禁。”

推荐命令：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance.ps1 -SkipCoverage
```

### 高级算法 (5:00-5:45)

> “高级算法不是拿来贴标签的。CH、JPS、ALT 已经进入 `src/advanced`，并有测试覆盖；native benchmark guard 已经固化为本地回归证据。真正的路网加速比会等 OSM 真实路网 artifact 落库后再讲，避免把 smoke benchmark 说成性能结论。”

### 对标与差异化 (5:45-6:30)

> “和 Rust pathfinding 对标，我避免使用无法一次证明的绝对化说法。当前能证明的差异化是：MoonBit 原生、多后端目标、README 可执行、runtime proof predicates、中英文文档、CH/JPS/ALT 的 MoonBit 实现、benchmark regression artifacts 和 release readiness evidence。未验证的真实路网加速比、浏览器 playground、外部语言绑定都不当作当前事实。”

### 路线图与结尾 (6:30-7:00)

> “下一步冲刺会集中在四件事：补齐负例和边界回归，打磨中英双语文档与答辩材料，给 CH/JPS/ALT 建立论文到代码的可追溯证据，并把真实路网 benchmark 做成可复现 artifact。moonbit-pathfinding 的目标是成为评委能验证、开发者能调用、未来能升级证明链路的 MoonBit 图算法库。谢谢各位。”

---

## 录制清单

| 镜头 | 时长 | 来源 | 验收依据 |
|------|------|------|----------|
| `moon run examples/network_routing` | 30s | 本地终端 | examples 可运行 |
| `moon test README.mbt.md` | 25s | 本地终端 | README doctest |
| `moon test src/proofs` | 25s | 本地终端 | proof predicates 测试 |
| `scripts\acceptance.ps1 -SkipCoverage` | 45s | 本地终端 | 快速验收门禁 |
| `docs\presentation\slides.md` | 20s | PPT / Marp | 同口径答辩材料 |

---

## 技术要求

- 分辨率：1920×1080 或 2560×1440
- 帧率：30fps
- 格式：MP4 H.264
- 字幕：中文主讲 + 英文字幕；或英文主讲 + 中文字幕
- 时长：严格 ≤ 7:00
- 录屏前先运行一次 `scripts\acceptance.ps1 -SkipCoverage`，确保镜头中的命令能复现。
