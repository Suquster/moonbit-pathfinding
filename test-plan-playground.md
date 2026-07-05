# PR #17 Playground go-live 测试计划

前置（已完成）：wasm-gc release 构建产物 `playground.wasm`（16,581 B）已复制到 `playground/web/`；`python3 -m http.server 8080` 已在仓库根运行；URL: `http://localhost:8080/playground/web/index.html`。

## Test 1: It should load the real wasm-gc engine (not pure-JS fallback)
1. 打开 URL。
- PASS: 页面 `#engine-state` 文本 = 「引擎就绪 · wasm 已加载」（app.js:843）。若 wasm 加载失败会显示「引擎加载失败」并回退纯 JS —— 修复前（无产物/无 pg_* 导出）必然走此失败分支，故该断言能区分好坏。

## Test 2: It should run BFS and find a path around painted walls
1. 用鼠标在网格上拖画一段墙。
2. 算法选 BFS → 点击 Run。
- PASS: frontier 动画逐帧扩散；结束后显示回溯路径绕过墙体；HUD 状态显示完成、算法名 BFS、进度 = 总步数。

## Test 3: It should show A*/JPS expanding far fewer nodes than BFS (same maze)
1. 同一迷宫下依次切换 A* 与 JPS 并 Run。
- PASS: 两者均找到路径；扩展节点数（HUD 进度总步数）明显小于 BFS（JPS 最少）。若桥接/算法坏了会出现无路径、报错或步数异常。

## Test 4: It should surface unreachable goal correctly
1. 用墙把终点完全围死（含对角），Run 任一算法。
- PASS: 状态显示不可达/无路径，页面不崩溃、无 JS 错误。

不测（说明）：GitHub Pages 线上部署要等 PR 合并到 main 后 pages.yml 运行才能验证；coverage(wasm-gc) CI 失败为 main 既有问题，与本 PR 无关。
