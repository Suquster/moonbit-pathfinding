# 贡献指南

> 🌐 Language: **简体中文** · [English](./CONTRIBUTING.md)

感谢愿意为全球首个带形式化证明的 MoonBit 路径规划库添砖加瓦。这是一份
5 分钟上手的速查表。

---

## 1. 环境准备

你需要 **MoonBit 0.9.1+**（CI 中 `ci.yml` 锁定的版本）。

```bash
# macOS / Linux
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
moon version   # 预期 >= 0.9.1
```

> 💡 首次克隆后建议启用本地 pre-commit 钩子提前拦截格式漂移：
> `git config core.hooksPath .githooks`

---

## 2. 本地构建

```bash
moon check                  # 类型检查（秒级）
moon build                  # 默认目标 wasm-gc
moon build --target native  # 或 js — 多后端由 CI 强制
```

---

## 3. 代码风格

```bash
moon fmt           # 自动修复
moon fmt --check   # 校验（与 CI 一致）
```

- **行长**：100 列软限制，`moon fmt` 自动折行
- **命名**：`snake_case` 值，`PascalCase` 类型，`SCREAMING_SNAKE_CASE` 常量
- **泛型**：节点 `N : Eq + Hash`，权重 `W : Weight`（定义见
  `src/core/prelude.mbt`）
- **Doc_Comment**：每个 `pub` 项至少 3 行 `///` 注释；CI 的 `doc` job 会用
  `scripts/audit_doc.ps1` 审计
- **不变式**：循环头上方写 `/// invariant: ...`，为 `moon prove` 做准备

---

## 4. 测试

提 PR 前三关必须全绿：

```bash
moon test                       # 黑盒 + 白盒
moon test README.mbt.md         # 可执行文档（R24）
moon coverage analyze && moon coverage report   # 目标 ≥ 85%（当前 91.62%）
```

黑盒测试放 `tests/**/*_test.mbt`，白盒测试用 `whitebox:` 前缀，属性测试
放 `tests/pbt/`，文件头标注 `**Validates: Requirements X.Y**`。
测试数据构造参考 [GRAPH_GUIDE.zh-CN.md](./GRAPH_GUIDE.zh-CN.md) 的四种
后继函数惯用写法。

---

## 5. PR 流程

1. **Fork** → 2. 基于 `main` **创建分支**
   （`git checkout -b feat/yen-k-shortest`）→ 3. **提交**
   （Conventional Commits，见 §6）→ 4. **推送**（`git push -u origin <branch>`）
   → 5. **向 `main` 提 PR**

[PR 模板](./.github/PULL_REQUEST_TEMPLATE.md)有四个必填字段：

- **关联 Issue**（`Closes #42`）
- **改动摘要**
- **测试证据**（粘贴 `moon test` 输出）
- **证明影响**（是否触及 `moon prove` 断言）

维护者将在 72 小时内响应。改动 > 500 LOC 时请先开 draft PR 对齐方向。

---

## 6. 提交格式

遵循 [Conventional Commits 1.0](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <简短摘要>
```

| Type       | 何时使用                                      |
|------------|----------------------------------------------|
| `feat`     | 新算法、新对外 API                            |
| `fix`      | 已存在代码的缺陷修复                          |
| `docs`     | 仅文档（README / GRAPH_GUIDE / 注释）         |
| `test`     | 新增或修复测试（含 PBT / fuzz）               |
| `refactor` | 无行为变更的重构                              |
| `perf`     | 性能改进（需附 `moon bench` 数据）            |
| `chore`    | 构建脚本、CI、依赖版本                        |
| `proof`    | `moon prove` 断言或不变式                     |

---

## 7. 新增算法 5 步走

以 `src/unweighted/bfs.mbt` 或 `src/directed/dijkstra.mbt` 为模板。

1. **源码**：按类型选子包（`src/unweighted/` / `src/directed/` /
   `src/undirected/` / `src/advanced/`），遵循"后继函数"API 家族，
   不内置 `Graph` 结构
2. **测试**：至少 3 个黑盒用例（可达 / 不可达 / start == goal），
   1 个白盒用例，1 个 PBT（如果自然不变式存在）
3. **Doc_Comment**：`pub fn` 至少 3 行 `///`，算法非平凡时引用原始论文
4. **CHANGELOG**：在 `CHANGELOG.md` 对应 unreleased 段落追加条目；
   破坏性改动用 `### Changed — BREAKING`
5. **mbti 快照**：运行 `moon info` 重新生成 `pkg.generated.mbti`，
   连同源码一起提交；CI 的 `ci (wasm-gc)` job 会检测漂移

---

## 延伸阅读

- 英文完整版：[CONTRIBUTING.md](./CONTRIBUTING.md)
- [README.mbt.md](./README.mbt.md) — 可执行 README
- [GRAPH_GUIDE.zh-CN.md](./GRAPH_GUIDE.zh-CN.md) — 图输入写法
- [CHANGELOG.md](./CHANGELOG.md) — 发布历史
- [ci.yml](./.github/workflows/ci.yml) — CI 门禁定义
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) — Contributor Covenant 2.1

有问题？欢迎开 GitHub Discussion，或到
[MoonBit Discourse](https://discuss.moonbitlang.com/) 交流。祝编码愉快！
