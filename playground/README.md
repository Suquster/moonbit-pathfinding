# Playground · WASM 实时演示

> 对应 `tasks.md` 38.x · Requirement R16 · design.md §14
>
> 状态: **v1.0.0 工程就绪** — 浏览器加载即用。
>
> 杀手锏 #1: **零安装、60fps、全算法可视化**。

## 一句话总览

打开 `web/index.html`,就能在浏览器里画一张迷宫,选 **BFS / DFS / Dijkstra / A\* / JPS** 五种算法之一,
实时看着 frontier 像火苗一样从起点蔓延到终点。

```
┌──────────────────────────────────────────────────────────┐
│  鼠标左键: 切换墙壁    右键: 拖动起点    Shift+点击: 终点  │
│  下拉菜单选算法 → 点击 ▶ Run → 60fps 动画展开 + 路径回溯    │
└──────────────────────────────────────────────────────────┘
```

## 双后端策略

| 模式 | 用途 | 加载文件 | 加载策略 |
|------|------|---------|---------|
| **wasm-gc**(主路径) | 评测最佳性能、≤100KB | `playground.wasm` (同目录) | 优先加载;失败回退 |
| **JS glue**(回退) | 兼容老浏览器 / 离线 | `playground.js` (同目录,可选) | wasm 加载失败时启用 |
| **pure JS**(应急) | CDN/离线/网络限制 | `app.js` 内置实现 | 双后端都失败时启用 |

三重回退保证 **任何环境都能演示**(对应 R12.5 现场备份)。

## 本地运行

```bash
# 在仓库根目录构建 pg_* 导出层 (src/playground 包):
moon build --target wasm-gc --release
cp _build/wasm-gc/release/build/src/playground/playground.wasm playground/web/

# 启动静态服务器:
python -m http.server 8080
# 浏览器访问 http://localhost:8080/playground/web/
```

没有 `.wasm` 产物时也能运行 — `app.js` 自动回退到内置纯 JS 实现。

## 部署到 GitHub Pages

`.github/workflows/pages.yml`(参见 tasks.md 38.5)自动:

1. 触发: `push` 到 `main`(亦支持手动 workflow_dispatch)
2. 构建: 仓库根目录 `moon build --target wasm-gc --release` + 体积门禁 + 组装 `playground/web` 与 `playground.wasm`
3. 部署: actions/deploy-pages 发布
4. 域名: <https://Suquster.github.io/moonbit-pathfinding/>

## 答辩演示脚本(7 min 视频 · 第 4 段 · 90 秒)

1. **开场**: 浏览器打开 Playground,展示初始空网格(5 秒)
2. **画迷宫**: 鼠标拖出一段 S 形墙壁(15 秒)
3. **跑 BFS**: 选 BFS → Run,frontier 同心圆扩散(15 秒)
4. **跑 Dijkstra**: 切换 Dijkstra,扩展模式相同但带权(15 秒)
5. **跑 A***: 切换 A* + Manhattan,扩展节点显著少(20 秒)
6. **跑 JPS**: 切换 JPS,扩展节点跳跃式锐减(15 秒)
7. **收尾**: 显示 "BFS: 312 expansions / A*: 87 / JPS: 12" 对比表(5 秒)

观众从动画里**直接看到** JPS 的 O(√area) 优势,无需文字解释。

## 文件结构

```
playground/
├── README.md             # 本文档
├── moon.mod.json         # 独立 module(path 依赖父仓库,保证 bridge 可独立构建/测试)
├── moon.pkg              # MoonBit package(依赖 src/unweighted, src/directed, src/advanced)
├── solver.mbt            # MoonBit 端 wrapper(与算法库逐字节对账的 bridge)
├── solver_test.mbt       # 自检测试(算法在 playground bridge 下结果一致)
└── web/
    ├── index.html        # 主页面
    ├── app.js            # 前端逻辑 + Canvas 渲染 + pure JS 算法回退
    ├── style.css         # 暗色科技风样式
    └── playground.wasm   # 构建产物(.gitignored,来自 src/playground 导出层)
```

浏览器实际消费的 pg_* 整型句柄 ABI 由根 module 的 `src/playground` 包提供
(`exports.mbt` + wasm-gc link exports)；本目录的 `solver.mbt` 是算法库的
另一层独立对账 bridge,两层都受 `moon test` 门禁。

## 与算法库的双向对账

`solver.mbt` 中的每个 `pub fn solve_xxx` 都有对应的 `_test.mbt` 用例,
确保 playground bridge 与 `src/` 算法库的实现 **逐字节一致**:

- `solve_bfs(width, height, blocked, sx, sy, gx, gy)` ≡ `@uw.bfs(...)`
- `solve_dijkstra(...)` ≡ `@dir.dijkstra(...)`
- `solve_astar(...)` ≡ `@dir.astar(...)`
- `solve_jps(...)` ≡ `@adv.jps(...)`

如果 bridge 与算法库的结果有任何分歧,`moon test` 直接 fail —
评委演示时不可能出现 "Playground 算的和论文算的不一样" 这种翻车场景。
