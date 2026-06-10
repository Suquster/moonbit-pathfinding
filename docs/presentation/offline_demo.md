# 离线演示备用脚本

> 对应 tasks.md 47.2 / Requirement R12.5
>
> 决赛现场无公网或网络不稳时，按本脚本执行纯本地演示，时长 ≤ 7 分钟。
> 本脚本只展示当前仓库可验证能力；未交付的 browser playground 不作为现场必备镜头。

---

## 准备清单（赛前 1 天）

- [ ] 笔记本预装 MoonBit（验证 `moon version`）
- [ ] 仓库已 clone 到本机，例如 `D:\demo\moonbit-pathfinding`
- [ ] 已跑过一次 `pwsh -File scripts\acceptance.ps1 -SkipCoverage`
- [ ] U 盘 1（主）：完整仓库 zip
- [ ] U 盘 2（备）：同上
- [ ] PPT PDF 离线本：`docs\presentation\slides.pdf`
- [ ] 视频 MP4：`docs\presentation\demo_v1_zh.mp4`
- [ ] Q&A 稿打印件：`docs\rehearsal\qa.md`
- [ ] 电源、转接头、HDMI 线

---

## 7 分钟演示流程（无公网版）

### 0:00-0:30 · Hook + 项目介绍

> 打开 PPT 第 1-2 页。强调当前交付：MoonBit 原生、可执行文档、运行时 proof predicates、本地验收脚本、benchmark artifact 与 release readiness evidence。

### 0:30-1:40 · 一条命令展示验收链路

```powershell
Set-Location -LiteralPath "D:\demo\moonbit-pathfinding"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance.ps1 -SkipCoverage
```

> 解释：快速门禁会跑 `moon check`、`moon fmt --check`、`moon test`、README doctest、`moon doc`、公共 API 注释审计。

### 1:40-2:30 · 终端跑核心算法工作流

```powershell
moon run examples/network_routing
```

> 展示网络路由最短路径输出。重点讲 successor function API：用户无需适配复杂 Graph 类型。

### 2:30-3:20 · README 可执行文档

```powershell
moon test README.mbt.md
```

> 解释：README 中的代码块由 MoonBit 当作黑盒测试执行，文档过时会直接失败。

### 3:20-4:20 · Proof predicates 展示

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\proof_evidence.ps1
```

> 打开 `src\proofs\bfs_proof.mbt` 与 `src\proofs\bfs_proof_test.mbt`。
> 解释：BFS minimality 已经从无条件返回改为有界 BFS witness 检查；这是当前硬证据，不把它包装成静态 `moon prove` 已完成。

### 4:20-5:20 · 高级算法状态

> 翻 PPT 的 CH / JPS / ALT 页。
> 口径：实现与测试已存在，当前 native benchmark artifact 用于回归守卫；真实路网加速比要等 OSM artifact 落库后再讲。

### 5:20-6:20 · 质量与交付面

```powershell
moon doc
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\audit_doc.ps1
```

> 说明公共 API 注释审计和文档构建如何支撑“用户体验”和“可解释性”评分。

### 6:20-7:00 · 结尾

> 总结下一阶段：补齐负例/边界回归、打磨中英双语答辩口径、深化 CH/JPS/ALT 论文到代码证据、推进真实路网 benchmark，并决定 playground 是否做成真实本地 demo。

---

## 可选完整验收

如现场时间充足或评委要求看覆盖率：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance.ps1
```

> 完整验收会额外运行 coverage analyze/report 和 `scripts\check_coverage.ps1`，耗时更长，建议赛前先录屏留备份。

---

## 故障应急

| 故障 | 备用方案 |
|------|---------|
| 笔记本黑屏 | 切到 U 盘备份机 + 投影仪自带 USB 播放 PPT |
| MoonBit 工具链异常 | 播放预录视频，并展示 `D:\_offload\temp\agent-terminal-logs` 或 CI 日志截图 |
| 完整 coverage 太慢 | 改跑 `scripts\acceptance.ps1 -SkipCoverage`，说明完整门禁赛前已跑 |
| 投影仪不识别 HDMI | U 盘 PPT PDF 直接给评委 |
| 时间超限 | 跳过高级算法页，直接进入结尾路线图 |

---

## 演讲节奏关键点

- 0:10 内给出定位：MoonBit 原生 + 可复现证据
- 2:30 前必须跑出一个真实算法工作流
- 4:00 前讲清 proof predicates 的当前边界
- 6:30 开始收束，避免超时
