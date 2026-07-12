# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Working rules

- When asked to improve, optimize, or clean up the codebase, do it
  **comprehensively, not selectively**: audit every module and address every
  identified weakness (performance, robustness, API completeness, test
  coverage), rather than cherry-picking only the highest-impact items.

- You are an AI agent, not a human: you are not limited by time, fatigue, or
  attention. Your throughput is extremely high, so **never scale down scope
  because "time is short"** — as long as token budget allows, keep executing
  the backlog end-to-end (deepen, broaden, and polish without pause). Work
  through items completely and continuously instead of deferring them.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.

## OSC 2026 大赛合规规约（官方验收，必须遵守）

### 提交身份（强制）

- 所有 git 提交的 author 与 committer 必须统一为仓库所有者身份：
  `Suquster <289166199+Suquster@users.noreply.github.com>`（提交时通过
  GIT_AUTHOR_NAME/EMAIL 与 GIT_COMMITTER_NAME/EMAIL 环境变量指定）。
- 官方硬标准：主要贡献者 = 仓库所有者 = 申报人；章程第九条禁止虚假信息。
  2026-07-12 已用 git-filter-repo 重写全史统一身份，不得再引入其他作者。

### 7·7 预验收未通过的教训（已整改，不得回退）

1. `moon fmt --deny-warn` / `moon info --deny-warn` 在新工具链返回参数错误
   → `scripts/acceptance.sh` 做版本探测，不支持时以等价语义执行
   （fmt/info + `git diff --exit-code` 无漂移）。改动验收脚本必须保持该语义。
2. CI 必须包含 fmt/info 两个 deny-warn 过程 → ci.yml wasm-gc 关卡运行
   `scripts/acceptance.sh`，不得删除。
3. actor benchmark regression guard 曾报 `massive_actor_scheduling` FAIL
   → 基线容差需容纳 runner 波动；出现 FAIL 先复测再调基线，不得删守卫。
4. 根目录曾同时存在 `moon.mod` 与弃用 `moon.mod.json` 产生警告
   → 已删除 moon.mod.json；不得再生成。

### 验收硬标准清单（每次推 main 前自查）

- MoonBit 为主要实现语言；GitHub 与 Gitlink 双仓公开且 main 同步
  （GitHub: Suquster/moonbit-pathfinding；Gitlink: Taoyouce/moonbit-pathfinding）。
- CI 覆盖 check / fmt / test（四后端矩阵）且最新 run 全绿；本地
  `bash scripts/acceptance.sh` 全门禁通过（需干净工作区）。
- README 可复现（安装/示例命令用跨平台正斜杠路径）；至少一个
  `moon run examples/...` 可运行示例；完整测试覆盖核心路径。
- 已发布 mooncakes.io（发版后同步刷新 README/申报书版本口径）。
- 仓库不含临时产物：*.log、缓存、构建产物不入库（.gitignore 已配置）。
- 第三方数据/代码注明来源与许可（cache/ OSM 数据已注明 ODbL）。
- 推 main 用 `./push-to-upstream.sh main`（需 GitHubPAT），并同步 Gitlink
  （需 gitlinktoken，push 到 Taoyouce/moonbit-pathfinding main）。
