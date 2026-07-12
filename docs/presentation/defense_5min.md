# 现场答辩台本 · 5 分钟 + 操作清单

> 目标：5 分钟内让评委记住三件事——**填补 MoonBit 生态空白、工程标杆、
> 真实数据端到端**。每个镜头都有离线兜底，任何一步翻车都能继续。
>
> 所有口径与 README / `benches/results/latest-rust-comparison.json` 一致：
> 同算法层对 Rust 中位加速 ≈2.67×（2.1–3.6×）；双向变体是单独的
> capability bonus（相对自身单向 8–68×），不混入同算法口径。

---

## 时间轴（严格 5:00）

| 时间 | 段落 | 讲什么 | 演示什么 |
|------|------|--------|----------|
| 0:00–0:30 | Hook + 生态空白 | MoonBit 生态缺图算法基础设施；本库 38+ 算法、successor-function API、mooncakes.io 已发布 | 标题页 / README 徽章行 |
| 0:30–1:30 | 在线 Playground | 打开即玩、零安装、wasm-gc ≤100KB | 网格模式跑 A*/JPS 动画 |
| 1:30–2:30 | 真实 OSM 路网 | 厦门 12.5 万节点真实路网进浏览器；单向 vs 双向 Dijkstra 现场对比 | osm.html 点两点，看 settle 节点数与耗时差 |
| 2:30–3:20 | 性能对标 Rust | 正式 18/18 同算法矩阵中位 2.67×；双向 bonus 单独口径，不夸大 | README 内嵌 SVG 图表 |
| 3:20–4:10 | 工程标杆 | 3337 测试四后端、97%+ 覆盖、零警告、CI 验收门禁、WIT 组件模型 | ci.yml 绿勾 / acceptance.sh 尾部输出 |
| 4:10–4:40 | 生态被使用 | mooncakes 包被独立下游仓消费（机器人路径规划 demo，自带 CI）；awesome-moonbit PR | demo 仓 README + `moon run cmd/main` 输出 |
| 4:40–5:00 | 收尾 | 可验证、可调用、可持续维护；欢迎评委现场复现任何一条命令 | 结尾页 |

---

## 关键台词

### Hook（0:00–0:30）

> “大家好，我是 Suquster。moonbit-pathfinding 是一个 MoonBit 原生的路径
> 规划与图算法库：38+ 算法、successor-function API、已发布 mooncakes.io。
> 接下来 5 分钟我不讲口号，只演示三件可以当场复现的事。”

### 在线 Playground（0:30–1:30）

> “第一件：打开即玩。这个页面由本库编译成的 wasm-gc 驱动，产物不到
> 100KB，有 CI 体积硬门禁。画几堵墙，跑 A* 和 JPS，逐帧看 frontier
> 扩展——所有帧数据都来自 MoonBit 侧的 StepTrace。”

操作：浏览器已预开 <https://Suquster.github.io/moonbit-pathfinding/>，
画 3–4 堵墙 → 选 JPS → ▶ 播放。

### 真实 OSM 路网（1:30–2:30）

> “第二件：真实数据。这是厦门驾车路网，12.5 万节点、21.6 万边，
> OpenStreetMap 数据，ODbL 许可注明。我点任意两个点，MoonBit 引擎跑
> 单向和双向 Dijkstra——注意 settle 节点数：双向明显更少，耗时更短，
> 而两者代价每次都交叉校验一致。这不是预置动画，评委可以自己点。”

操作：点「真实 OSM 路网模式」→ 算法选「两者对比」→ 点地图两点
（建议跨岛长途，效果最明显）。

### 性能对标 Rust（2:30–3:20）

> “第三件：诚实的性能。对 Rust pathfinding crate 的正式对比是 18/18
> 完整矩阵、最大 10 万节点 160 万边、共享 xorshift 负载、结果签名
> 逐元素一致：同算法层中位加速 2.67 倍。本库特有的双向变体单独列为
> capability bonus，8 到 68 倍，但我们不把它混进同算法口径——这套
> 方法学全部写在 JSON artifact 里，可复现。”

操作：README 滚动到内嵌 SVG 图表；如追问，打开
`benches/results/latest-rust-comparison.json`。

### 工程标杆（3:20–4:10）

> “质量上：3337 个测试跑在 wasm-gc、js、native、wasm 四个后端；核心库
> 覆盖率 97% 以上；`moon check` 零警告；CI 里跑与官方验收同语义的
> acceptance 脚本；playground 协议还提升成了 WIT 组件模型显式类型接口，
> 由 wasmtime 逐函数类型化调用把关。”

操作：展示 GitHub Actions 最新绿勾；或本地终端
`bash scripts/acceptance.sh` 的尾部「全部验收门禁通过」。

### 生态被使用（4:10–4:40）

> “生态贡献不是自我声明：mooncakes.io 的包已被独立仓库
> moonbit-pathfinding-demo 以常规 `moon add` 依赖消费——一个仓库机器人
> 路径规划器，自带测试和 CI；同时已向 moonbitlang/awesome-moonbit
> 提交收录 PR。”

操作：切到 demo 仓 README；备用终端 `moon run cmd/main` 展示 ASCII 路线。

### 收尾（4:40–5:00）

> “moonbit-pathfinding 的定位是：评委能验证、开发者能调用、社区能持续
> 维护的 MoonBit 图算法基础设施。以上每一步都欢迎现场复现。谢谢！”

---

## 现场操作清单（答辩前 30 分钟逐项过）

1. [ ] 浏览器预开 3 个标签页：Playground 网格模式、osm.html、GitHub
   Actions 页面（全部提前加载完成，osm.html 等路网渲染出来再收起）。
2. [ ] 本地终端预热：`export PATH="$HOME/.moon/bin:$PATH"`；预跑一次
   `moon run examples/network_routing` 与 `bash scripts/acceptance.sh`
   确认可复现。
3. [ ] demo 仓终端预热：`cd moonbit-pathfinding-demo && moon run cmd/main`
   跑通一次。
4. [ ] README 滚动位置书签：徽章行、SVG 图表、Playground 小节。
5. [ ] 断网兜底预案（见下）逐项确认可用。

## 翻车兜底

| 风险 | 兜底 |
|------|------|
| 现场断网 / Pages 打不开 | 本地 `python3 -m http.server 8080` + 仓库内 `playground/web/`（wasm 提前 build 好，`cp _build/wasm-gc/release/build/src/playground/playground.wasm playground/web/`），全功能离线可用 |
| wasm 加载失败 | 网格模式自动回退纯 JS 实现，演示照常 |
| OSM 页面首次加载慢 | 提前加载完成并保留标签页；数据同源 5.4MB，本地 http.server 秒开 |
| 浏览器崩溃 | 备用离线截图/录屏：`docs/presentation/offline_demo.md` 索引 |
| 评委追问性能口径 | 打开 `benches/results/latest-rust-comparison.json` 的 methodology 字段逐条念 |
| 评委追问许可证 | Apache-2.0 + OSM/ODbL 属名在 README「数据来源」小节 |
