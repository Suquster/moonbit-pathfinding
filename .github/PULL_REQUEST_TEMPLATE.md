<!--
Thanks for sending a pull request to moonbit-pathfinding!
Please fill in this template. 🟢 items are required, 🔵 optional.
See CONTRIBUTING.md §5 for the full PR flow.

感谢向 moonbit-pathfinding 提交 PR！请完整填写本模板。
🟢 为必填项，🔵 为可选项；完整流程见 CONTRIBUTING.md 第 5 节。
-->

## 🟢 Linked Issue / 关联 Issue

<!-- Use `Closes #NN`, `Fixes #NN`, or `Refs #NN` so the issue is
auto-closed on merge. One PR = one logical issue whenever possible.

请使用 `Closes #NN` / `Fixes #NN` / `Refs #NN` 语法，合并时自动关闭。
原则上 1 个 PR 对应 1 个 Issue。 -->

Closes #

## 🟢 Summary of changes / 改动摘要

<!-- A short bilingual paragraph: what problem, what approach, what files.
Link to the spec requirement (e.g. R2.3) when relevant.

简短中英双语说明：解决了什么问题、采用什么方案、改动了哪些文件。
如有对应的规格需求编号 (例如 R2.3)，请一并标注。 -->

-
-
-

Spec requirement ID / 对应需求编号:

## 🟢 Test evidence / 测试证据

<!-- Paste the `moon test` output (or the relevant slice) proving all
gates are green. Coverage delta is welcome.

粘贴 `moon test` 的输出 (或相关片段)，证明所有关卡通过。
欢迎附覆盖率变化。 -->

```text
$ moon test
<paste output here / 在此粘贴输出>
```

```text
$ moon coverage report   # optional / 可选
<paste output here / 在此粘贴输出>
```

## 🟢 Formal proof impact / 形式化证明影响

<!-- Did this PR touch any `moon prove` assertion, `/// invariant:` loop
annotation, or termination measure? If yes, briefly describe the change
and the verification status.

本 PR 是否触及 `moon prove` 断言、`/// invariant:` 循环不变式，
或终止性度量？若有，请简述改动与验证状态。 -->

- [ ] No proof assertions touched / 未触及形式化断言
- [ ] Added / updated `moon prove` assertion(s) / 新增或修改断言
- [ ] Added / updated `/// invariant:` annotation(s) / 新增或修改不变式注释
- [ ] Other proof-related change / 其他证明相关改动:

Proof status / 证明状态:

```text
$ moon prove   # if applicable / 如适用
<paste output or N/A>
```

## 🔵 Type of change / 改动类型

<!-- Tick all that apply. Matches the Conventional Commits types in
CONTRIBUTING.md §6.

勾选全部相关项，对应 CONTRIBUTING.md 第 6 节的 Conventional Commits 类型。 -->

- [ ] `feat` — new algorithm or public API / 新算法或对外 API
- [ ] `fix` — bug fix / 缺陷修复
- [ ] `docs` — documentation only / 仅文档
- [ ] `refactor` — no behaviour change / 无行为变更的重构
- [ ] `perf` — performance improvement (attach `moon bench` data)
      / 性能优化 (附 `moon bench` 数据)
- [ ] `chore` — build / CI / deps / 构建、CI、依赖
- [ ] `proof` — `moon prove` assertion or invariant / 证明相关
- [ ] `test` — tests only (incl. PBT / fuzz) / 仅测试 (含 PBT / fuzz)

## 🔵 Backend compatibility / 多后端兼容性

<!-- moonbit-pathfinding targets three backends. Tick the ones you have
exercised locally; CI still enforces all three.

本项目需兼容三后端。勾选本地已测试项；CI 仍会强制校验全部后端。 -->

- [ ] `moon test --target wasm-gc` passes / 通过
- [ ] `moon test --target js` passes / 通过
- [ ] `moon test --target native` passes / 通过
- [ ] Backend-independent change / 与后端无关 (no test needed / 无需测试)

## ✅ Self-check / 提交前自查

- [ ] `moon fmt --check` is clean / 格式化通过
- [ ] `moon check` passes / 类型检查通过
- [ ] `moon test` passes (blackbox + whitebox + `README.mbt.md`)
      / 测试全部通过 (黑盒 + 白盒 + 可执行 README)
- [ ] `moon coverage report` meets the ≥ 85% target (new code) /
      覆盖率达到 ≥ 85% (针对新增代码)
- [ ] Doc_Comment ≥ 3 lines on every new `pub` item /
      每个新增 `pub` 项均有 ≥ 3 行 `///` 注释
- [ ] `CHANGELOG.md` updated under the appropriate unreleased section /
      已在对应未发布段落更新变更日志
- [ ] `moon info` regenerated `pkg.generated.mbti` when signatures
      changed / 签名变化时已重新生成 mbti 快照
- [ ] PR title follows Conventional Commits (e.g. `feat(directed): ...`)
      / 标题遵循 Conventional Commits 规范

<!-- Maintainers respond within 72 hours. For changes > 500 LOC, please
open a draft PR to align direction first.

维护者将在 72 小时内响应。改动 > 500 LOC 时请先开 draft PR 对齐方向。 -->
