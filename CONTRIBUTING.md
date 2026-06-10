# Contributing to moonbit-pathfinding

> 🌐 Language: **English** · [简体中文](./CONTRIBUTING.zh-CN.md)

> **English body + 中文补充** · Thanks for contributing to the first
> formally-verified pathfinding library for MoonBit. This is a 5-minute
> cheat sheet for your first PR.

---

## 1. Prerequisites · 环境准备

You need **MoonBit 0.9.1+**, the toolchain pinned by
[`ci.yml`](./.github/workflows/ci.yml).

```bash
# macOS / Linux
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
moon version   # expect >= 0.9.1
```

> 💡 中文：首次克隆后建议启用本地 pre-commit 钩子提前拦截格式漂移：
> `git config core.hooksPath .githooks`（详见
> [`.githooks/README.md`](./.githooks/README.md)）。

---

## 2. Local build · 本地构建

```bash
moon check                  # type-check only · 秒级,CI 第 1 关
moon build                  # default target = wasm-gc
moon build --target native  # or js — multi-backend is CI-enforced
```

---

## 3. Style · 代码风格

```bash
moon fmt           # auto-fix
moon fmt --check   # verify — same as CI
```

- **Line length**: 100 columns soft limit; let `moon fmt` wrap.
- **Naming**: `snake_case` values, `PascalCase` types, `SCREAMING_SNAKE_CASE`
  constants.
- **Generics**: nodes are `N : Eq + Hash`, weights are `W : Weight`
  (see `src/core/prelude.mbt`).
- **Doc_Comment**: every `pub` item needs ≥ 3 lines of `///` doc.
  CI job `doc` runs [`scripts/audit_doc.ps1`](./scripts/audit_doc.ps1)
  to flag gaps.
- **Invariants**: annotate loop heads with `/// invariant: ...` to prepare
  for `moon prove` integration (see `src/unweighted/bfs.mbt`).

---

## 4. Tests · 测试

Three gates must be green before you open a PR:

```bash
moon test                       # blackbox + whitebox
moon test README.mbt.md         # executable docs (R24)
moon coverage analyze && moon coverage report   # target >= 85%
```

中文：黑盒测试放 `tests/**/*_test.mbt`；白盒放 `*_wbtest.mbt`；PBT 放
`tests/pbt/`，每个 property 单文件，头部标注
`**Validates: Requirements X.Y**`。测试数据构造参考
[`GRAPH_GUIDE.md`](./GRAPH_GUIDE.md) 的 4 种后继函数惯用写法。

---

## 5. PR flow · 提交流程

1. **Fork** → 2. **Branch** from `main`
   (`git checkout -b feat/yen-k-shortest`) → 3. **Commit**
   (Conventional, see §6) → 4. **Push** (`git push -u origin <branch>`)
   → 5. **Open PR** against `main`.

The template
[`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md)
pre-fills four required fields:

- **Linked Issue** (e.g. `Closes #42`)
- **Summary of changes**
- **Test evidence** (paste `moon test` output)
- **Proof impact** — did you touch any `moon prove` assertion?

Maintainers respond within 72 hours. 改动 > 500 LOC 时先开 draft PR
讨论方向再实现。

---

## 6. Commit format · 提交格式

We follow [Conventional Commits 1.0](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type       | When to use · 何时使用                                |
|------------|------------------------------------------------------|
| `feat`     | 新算法、新对外 API                                    |
| `fix`      | 已存在代码的缺陷修复                                  |
| `docs`     | 仅文档 (README / GRAPH_GUIDE / 注释)                 |
| `test`     | 新增或修复测试 (含 PBT / fuzz)                        |
| `refactor` | 无行为变更的重构                                      |
| `perf`     | 性能改进 (须附 `moon bench` 数据)                     |
| `chore`    | 构建脚本、CI、依赖版本                                |
| `proof`    | `moon prove` 断言或不变式相关                         |

Example:

```
feat(directed): add Yen's K-shortest-paths

Implements the candidate-pool variant per Yen 1971.
Returns Err(InvalidK) when k <= 0.

Closes #87
```

---

## 7. How to add a new algorithm · 新增算法 5 步

Use `src/unweighted/bfs.mbt` or `src/directed/dijkstra.mbt` as templates.

1. **Source · 源码** — pick the right subpackage:
   `src/unweighted/` (BFS/DFS), `src/directed/` (Dijkstra/A\*/Yen),
   `src/undirected/` (Kruskal/KM), `src/advanced/` (CH/JPS/ALT). Follow
   the "successor function" API family (never ship a custom `Graph`
   struct; see [`GRAPH_GUIDE.md`](./GRAPH_GUIDE.md)).
2. **Tests · 测试** — at least 3 blackbox cases (reachable / unreachable /
   start == goal), 1 whitebox case, and 1 PBT when a natural invariant
   exists (see Requirement 13 catalog).
3. **Doc_Comment · 文档注释** — ≥ 3 lines of `///` per `pub fn` (purpose,
   params, return). Cite the original paper for non-trivial algorithms.
4. **CHANGELOG · 变更日志** — append to the matching unreleased section
   in [`CHANGELOG.md`](./CHANGELOG.md); breaking API change lands as
   `### Changed — BREAKING`.
5. **mbti snapshot · 接口快照** — run `moon info` to regenerate
   `pkg.generated.mbti`, then commit them alongside the source. CI job
   `ci (wasm-gc)` fails on drift.

---

## 8. Further reading · 延伸阅读

- [`README.mbt.md`](./README.mbt.md) — executable README · 可执行文档
- [`GRAPH_GUIDE.md`](./GRAPH_GUIDE.md) — 4 graph input idioms · 4 种图输入
- [`CHANGELOG.md`](./CHANGELOG.md) — release history · 发布历史
- [`ci.yml`](./.github/workflows/ci.yml) — CI gate definitions · CI 关卡
- [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) — Contributor Covenant 2.1

Questions? Open a GitHub Discussion or drop by
[MoonBit Discourse](https://discuss.moonbitlang.com/). 祝编码愉快!
