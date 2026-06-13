# 实施计划（Implementation Plan）：Build_Tool 旗舰深化

## 概述（Overview）

本计划将 `design.md` 的旗舰深化拆解为一系列**增量、可执行、聚焦编码**的 MoonBit 任务，严格遵循「既有契约冻结、新能力旁路扩展」原则：

- **冻结不改**：`types.mbt`（`Target`/`BuildGraph`/`BuildCache`/`ParseError`/`Cycle`）、`build_tool.mbt`（`parse_rules`/`detect_cycle`/`topo_order`/`is_dirty`/`schedule`）、`release.mbt` 的既有 `pub` 声明签名与语义一律不动；`ParseError` 不扩容，列号诊断由新增 `GrammarError` 旁路承载并经 `to_legacy` 投影回退。
- **复用而非重写**：拓扑序 / 环检测复用 `@directed`，解析复用 `@parser_combinator`，属性测试复用 `@infra_pbt`，发布元数据复用 `@release_meta`。
- **任务依赖顺序**：完整规则文法解析 → 内容寻址缓存 / 持久化 → 脏传播与最小重建集 → 调度增强 / 动态依赖 → provenance / demo / 基准 / 文档 / 发布，并设阶段检查点。
- **实现语言**：MoonBit（仅 `.mbt` / `.mbt.md` / `.md`，不写其他语言）。所有源文件位于 `src/build_tool/`，基准位于 `benches/build_tool_bench/`。
- **属性测试**：P1–P15 每条独立成一个 `*` 可选子任务，统一以 `@infra_pbt` 的 `holds_for_all` / `round_trip` 实现，每条至少 100 次迭代，标注 `Feature: build-tool, Property N`。
- **native 前置约束**：凡在 native 后端运行测试、运行基准、或校验 `README.mbt.md` 可执行文档的环节，**必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（见各检查点、基准与文档任务，以及末尾 Notes）。

---

## 任务（Tasks）

- [x] 1. 完整规则文法解析与富模型（`rule_grammar.mbt`，旁路新增）
  - [x] 1.1 定义富模型类型与列号诊断及其向后兼容投影
    - 在 `src/build_tool/rule_grammar.mbt` 新增 `Recipe`、`Rule`、`PatternRule`、`RuleSet`（`derive(Eq, Show)`）与 `GrammarError`（携带 `@parser_combinator.Pos` 与 `expected` 期望描述）
    - 实现 `GrammarError::to_legacy()`：`line` 取 `pos.line`、`message` 内嵌列号，投影回既有 `ParseError`，**不修改** `ParseError` 结构
    - 文件头注释标注 paper-to-code 来源（《Build Systems à la Carte》规则文法层）
    - _Requirements: 1.2, 2.3, 13.1, 13.5_

  - [x] 1.2 实现 `parse_rules_full` 完整文法与图投影桥
    - 基于 `@parser_combinator`（`Input`/`Pos`/`satisfy`/`many`/`many1`/`alt`/`seq`/`optional`/`pchar`/`ptoken`）实现 `parse_rules_full(src) -> Result[RuleSet, GrammarError]`，覆盖：目标 + 依赖去重登记、缩进 recipe 原文保留、`name = value` 变量定义与 `$(name)` 展开（未定义展开为空串）、模式规则 `%.o: %.c` 词干回填、`.PHONY` 标记、`#` 注释与空行忽略
    - 实现 `parse_rules_full_with_includes(src, resolve)`：经调用方注入的 `resolve` 合并 include 源入同一 `RuleSet`，合并后去重与单文件一致
    - 实现 `RuleSet::to_graph()`（节点首次出现去重 + 全部 `(dep, target)` 边）、`print_rules`（确定性规范打印）、`RuleSet::recipe_of`、`RuleSet::is_phony`
    - 语法错误「先完整收集后构造」，失败返回 `Err(GrammarError)` 且不产部分 `RuleSet`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1, 2.2, 2.4_

  - [x]* 1.3 文法单元测试（示例 / 边界 / 错误位置）
    - 在 `src/build_tool/rule_grammar_test.mbt` 覆盖 recipe / 变量展开 / 模式规则实例化 / phony / include 合并的具体见证，以及缺 `:`、目标名为空的 `GrammarError` 行列号
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1, 2.2, 2.3_

  - [x]* 1.4 编写属性测试：规则解析 round-trip
    - **Property 1: 规则解析 round-trip（`parse_rules_full(print_rules(rs)) == Ok(rs)`）**
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.7**
    - 文件 `src/build_tool/prop_rule_grammar_roundtrip_test.mbt`，以 `@infra_pbt` 生成随机合法 `RuleSet`（含变量 / 模式 / phony），`round_trip` ≥100 迭代

  - [x]* 1.5 编写属性测试：最小文法向后兼容
    - **Property 2: 最小文法向后兼容（`RuleSet::to_graph(parse_rules_full(src))` 与 `parse_rules(src)` 逐字段一致）**
    - **Validates: Requirements 2.4, 2.5**
    - 文件 `src/build_tool/prop_minimal_compat_test.mbt`，生成随机最小文法文本（仅 `target: dep` / 注释 / 空行），`holds_for_all` ≥100 迭代

- [x] 2. 内容寻址增量缓存与缓存持久化（`cache.mbt`，旁路新增）
  - [x] 2.1 实现内容寻址缓存键与动作缓存
    - 在 `src/build_tool/cache.mbt` 实现 `content_hash`、`action_fingerprint(recipe)`、`cache_key(target, input_hashes, action_fp)`（长度前缀单射编码，纯整型 / 字符串运算保三后端逐位一致）
    - 实现 `ActionCache`（`new`/`record`/`hit`/`get`）与 `needs_rebuild_by_key`（命中→false 排除重建、未命中→true 纳入重建；内容哈希变而 mtime 未变仍判键变）
    - 文件头注释标注内容寻址来源（Bazel / Nix / Ninja）
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 2.2 实现 `BuildCache` 序列化往返
    - 在 `cache.mbt` 续写 `serialize_cache`（四张指纹映射、键升序、行式 section 确定性输出）、`deserialize_cache`（非法标记 / 字段数不符 / 数值非法返回带行号 `ParseError` 且不产部分缓存）、`cache_eq`（四张映射逐字段比较）
    - 不修改既有 `BuildCache` 结构
    - _Requirements: 4.1, 4.2, 4.3_

  - [x]* 2.3 缓存单元测试（内容敏感 / 命中未命中 / 反序列化错误）
    - 在 `src/build_tool/cache_test.mbt` 覆盖 mtime 同而内容哈希不同仍重建、命中 / 未命中判定、反序列化非法格式错误
    - _Requirements: 3.2, 3.3, 3.5, 4.3_

  - [x]* 2.4 编写属性测试：缓存键确定且内容敏感
    - **Property 3: 缓存键确定且内容敏感（相同输入产相同键；任一分量改变产不同键）**
    - **Validates: Requirements 3.1, 3.4, 3.6**
    - 文件 `src/build_tool/prop_cache_key_test.mbt`，`@infra_pbt` 生成随机（目标, 输入哈希序列, 动作指纹），≥100 迭代

  - [x]* 2.5 编写属性测试：缓存往返一致性
    - **Property 4: 缓存往返一致性（`deserialize_cache(serialize_cache(c))` 与 `c` 逐字段相等）**
    - **Validates: Requirements 4.1, 4.2, 4.4**
    - 文件 `src/build_tool/prop_cache_roundtrip_test.mbt`，`round_trip` 随机 `BuildCache`，≥100 迭代

- [x] 3. 检查点 —— 确保文法与缓存全部测试通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行至此为止的测试套件；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. 脏传播与最小重建集（`rebuild.mbt`，旁路新增）
  - [x] 4.1 实现脏传播与最小重建集及重建调度
    - 在 `src/build_tool/rebuild.mbt` 实现 `dirty_targets`（复用冻结的 `is_dirty`）、`propagate_dirty`（沿边 `(u,v)` 前向可达闭包 BFS/DFS）、`minimal_rebuild_set`（= 脏输入及其传递下游并集）、`rebuild_schedule`（取重建集导出子图后复用冻结 `schedule`，重建集外不参与）
    - 文件头注释标注 rebuilder 维（《Build Systems à la Carte》）与图可达性
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 6.1, 6.2, 6.3, 6.4_

  - [x]* 4.2 重建单元测试（排除 / 仅重建集内调度 / 干净脏边界）
    - 在 `src/build_tool/rebuild_test.mbt` 覆盖未受影响目标被排除、仅重建集内目标进入调度、指纹缺失 / 不一致判脏
    - _Requirements: 5.3, 5.4, 6.1, 6.2_

  - [x]* 4.3 编写属性测试：最小重建集充分性
    - **Property 5: 最小重建集充分性（每个从脏输入前向可达的目标都被包含）**
    - **Validates: Requirements 5.1, 5.2, 5.5, 6.4**
    - 文件 `src/build_tool/prop_rebuild_sufficiency_test.mbt`，生成随机无环图 + 脏子集，≥100 迭代

  - [x]* 4.4 编写属性测试：最小重建集最小性
    - **Property 6: 最小重建集最小性（每个被包含目标可由某脏输入沿边到达）**
    - **Validates: Requirements 5.3, 5.6**
    - 文件 `src/build_tool/prop_rebuild_minimality_test.mbt`，生成随机无环图 + 脏子集，≥100 迭代

  - [x]* 4.5 编写属性测试：增量空操作幂等
    - **Property 7: 增量空操作幂等（无变更时连续两次重建集均空且相等）**
    - **Validates: Requirements 6.1, 6.3, 6.5**
    - 文件 `src/build_tool/prop_rebuild_noop_test.mbt`，生成随机图 + 已固化基线缓存，≥100 迭代

- [x] 5. 并行调度增强（`scheduler.mbt`，旁路新增；既有 `schedule` 冻结复用）
  - [x] 5.1 实现关键路径长度与最小批次层数
    - 在 `src/build_tool/scheduler.mbt` 基于 `topo_order` 拓扑序做最长路径 DP，实现 `critical_path_length`（`longest[v]=1+max(longest[u])`，O(V+E)）与 `min_layers`
    - 文件头注释标注 DAG 最长路径（拓扑序 DP）
    - _Requirements: 7.4_

  - [x]* 5.2 调度增强单元测试（不限并行整层一批 / 关键路径 == 层数）
    - 在 `src/build_tool/scheduler_test.mbt` 覆盖 `jobs<=0` 整层一批、`critical_path_length(g) == len(schedule(g,0))` 的具体见证
    - _Requirements: 7.3, 7.4_

  - [x]* 5.3 编写属性测试：调度尊重依赖
    - **Property 8: 调度尊重依赖（批次展平后每目标排在其全部依赖之后）**
    - **Validates: Requirements 7.1, 7.5**
    - 文件 `src/build_tool/prop_schedule_topo_test.mbt`，生成随机无环图，≥100 迭代

  - [x]* 5.4 编写属性测试：批内独立
    - **Property 9: 批内独立（同批任意两目标间无依赖边）**
    - **Validates: Requirements 7.6**
    - 文件 `src/build_tool/prop_schedule_indep_test.mbt`，生成随机无环图，≥100 迭代

  - [x]* 5.5 编写属性测试：调度确定性
    - **Property 10: 调度确定性（同图同 jobs 两次调度逐元素一致）**
    - **Validates: Requirements 7.7**
    - 文件 `src/build_tool/prop_schedule_determinism_test.mbt`，生成随机无环图 + jobs，≥100 迭代

  - [x]* 5.6 编写属性测试：并行度约束
    - **Property 11: 并行度约束（`jobs>0` 时每批长度 ≤ jobs）**
    - **Validates: Requirements 7.2**
    - 文件 `src/build_tool/prop_schedule_jobs_test.mbt`，生成随机无环图 + `jobs>0`，≥100 迭代

  - [x]* 5.7 编写属性测试：关键路径等于最小批次层数
    - **Property 12: 关键路径等于最小批次层数（`critical_path_length(g) == len(schedule(g,0))`）**
    - **Validates: Requirements 7.3, 7.4**
    - 文件 `src/build_tool/prop_critical_path_test.mbt`，生成随机无环图，≥100 迭代

- [x] 6. 动态依赖发现与重新调度（`dynamic.mbt`，旁路新增）
  - [x] 6.1 实现动态依赖追加与重调度
    - 在 `src/build_tool/dynamic.mbt` 实现 `add_dynamic_deps`（登记缺失节点、追加边 `(dyn_dep, target)`、返回不可变新图，既有图不变）与 `reschedule_with_dynamic`（先 `add_dynamic_deps` 再复用冻结 `detect_cycle`：有环返回 `Err(Cycle)`，无环复用冻结 `schedule`）
    - _Requirements: 8.1, 8.2, 8.3_

  - [x]* 6.2 动态依赖单元测试（引入环返回 `Err(Cycle)`）
    - 在 `src/build_tool/dynamic_test.mbt` 覆盖追加引入环时返回承载环节点序列的 `Err(Cycle)` 并拒绝调度
    - _Requirements: 8.3_

  - [x]* 6.3 编写属性测试：环检测可靠性
    - **Property 13: 环检测可靠性（`detect_cycle` 返回 `Some` 当且仅当图含环；与 `topo_order` 的 `Err(Cycle)` 等价）**
    - **Validates: Requirements 8.3, 13.2, 13.3**
    - 文件 `src/build_tool/prop_cycle_detection_test.mbt`，生成随机含环 / 无环图，≥100 迭代

  - [x]* 6.4 编写属性测试：动态依赖拓扑保持
    - **Property 14: 动态依赖拓扑保持（不引入环的追加后仍无环且重调度满足拓扑不变量）**
    - **Validates: Requirements 8.1, 8.2, 8.4**
    - 文件 `src/build_tool/prop_dynamic_topo_test.mbt`，生成随机无环图 + 不引入环的动态边，≥100 迭代

- [x] 7. 可复现构建与 provenance 溯源（`provenance.mbt`，旁路新增）
  - [x] 7.1 实现溯源记录与确定性输出哈希
    - 在 `src/build_tool/provenance.mbt` 新增 `Provenance`（`derive(Eq, Show)`），实现 `derive_output_hash(input_hashes, action_fp)`（长度前缀单射编码）与 `record_provenance(target, input_hashes, recipe)`（内部用 `action_fingerprint`、对 `input_hashes` 规范升序）
    - 文件头注释标注可复现内核（Bazel / Nix）
    - _Requirements: 9.1, 9.2, 9.3_

  - [x]* 7.2 provenance 单元测试（相同输入同记录 / 差异可区分）
    - 在 `src/build_tool/provenance_test.mbt` 覆盖相同输入与动作产逐字段一致记录、任一分量变异记录不同
    - _Requirements: 9.2, 9.3_

  - [x]* 7.3 编写属性测试：可复现性与溯源确定
    - **Property 15: 可复现性与溯源确定（相同输入与动作恒得相同记录；任一变异记录不同）**
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.4**
    - 文件 `src/build_tool/prop_provenance_test.mbt`，生成随机（目标, 输入哈希集合, recipe），≥100 迭代

- [x] 8. 检查点 —— 确保重建 / 调度 / 动态 / 溯源全部测试通过
  - 在三后端运行至此为止的全部测试与 15 条属性测试；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. 旗舰端到端示例（`demo.mbt`，旁路新增）
  - [x] 9.1 实现多模块工程实战规则集
    - 在 `src/build_tool/demo.mbt` 实现 `demo_rules()`（多模块 C / MoonBit 工程：`app` 依赖 `libcore.a`/`libutil.a`，各库依赖若干 `.o`，各 `.o` 依赖对应源与共享头）与 `demo_graph()`（`parse_rules` 期望产物，供断言）
    - _Requirements: 10.1_

  - [x]* 9.2 端到端 demo 单元测试（解析 / 无环 / 调度 / 单源增量缩减）
    - 在 `src/build_tool/demo_test.mbt` 断言 `parse_rules(demo_rules())` 节点 / 边与 `demo_graph()` 一致、`detect_cycle` 返回 `None`、`schedule` 满足拓扑 + 批内独立、单源变更下 `minimal_rebuild_set` 仅含该源下游且相对全量目标数缩减
    - _Requirements: 10.2, 10.3, 10.4, 10.5_

- [x] 10. 性能基准（`benches/build_tool_bench/`，新增包）
  - [x] 10.1 创建基准包骨架
    - 新增 `benches/build_tool_bench/moon.pkg` 与 `benches/build_tool_bench/pkg.generated.mbti`，结构对齐既有 `benches/astar_bench`，声明对 `build_tool` 的依赖
    - _Requirements: 11.1_

  - [x] 10.2 实现四类工作负载基准与回归工件
    - 在 `benches/build_tool_bench/build_tool_bench.mbt` 实现参数化 DAG 生成（链 / 扇出 / 分层网格）与四类负载：拓扑排序（`topo_order`）、并行调度（`schedule`）、脏检查（`dirty_targets`/`is_dirty`）、最小重建集（`minimal_rebuild_set`）；输出含机器标识、后端目标、图规模（节点数 / 边数）与计时统计的 JSON / Markdown 工件至 `benches/results/`，并接入 guard 与基线中位数比较的回归报告
    - 在基准文档 / 脚本注明：运行 native 基准前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`，并记录可复现运行命令与规模参数
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [x] 11. 集成、文档与发布推进
  - [x] 11.1 同步公开接口签名文件
    - 重新生成并提交 `src/build_tool/pkg.generated.mbti`，使其追加全部新增 `pub` 声明（`RuleSet`/`GrammarError`/`ActionCache`/`Provenance` 及新增函数 / 方法），既有条目保持稳定不删改
    - _Requirements: 13.1, 13.2_

  - [x] 11.2 扩充 `README.mbt.md` 可执行文档（集成 / 对标 / 边界）
    - 在 `src/build_tool/README.mbt.md` 串联完整规则文法、内容寻址缓存、最小重建集、增强调度与端到端 demo 的可运行示例（经 `moon test *.mbt.md` 验证），并补充：rebuilder/scheduler 追溯（《Build Systems à la Carte》）、Kahn / Tarjan 追溯（复用 `@directed`）、与 GNU Make / Ninja / Bazel / Buck2 的调度 / 缓存 / 可复现对比、实现边界声明（不读写真实 FS、不派生进程、不调编译器）与差异声明
    - 注明：校验 native 后端可执行文档前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 10.2, 12.1, 12.2, 12.3, 12.4, 12.5, 14.3, 14.4_

  - [x] 11.3 推进 SemVer 版本字符串
    - 在 `src/build_tool/release.mbt` 仅更新 `build_tool_version` 字符串（自 `0.1.0` 起做次 / 主版本推进），保持 `release_info` / `release_info_with_gates` 语义不变
    - _Requirements: 14.5_

  - [x] 11.4 更新方向 CHANGELOG
    - 在 `src/build_tool/CHANGELOG.md` 追加本次旗舰深化的新增能力与版本条目
    - _Requirements: 14.5_

  - [x]* 11.5 既有 API 向后兼容回归测试
    - 在 `src/build_tool/build_tool_test.mbt` 补充回归断言：`parse_rules` / `detect_cycle` / `topo_order` / `is_dirty` / `schedule` 行为与 `0.1.0` 逐字段一致，`ParseError` 形态不变
    - _Requirements: 13.1, 13.2, 13.5_

  - [x]* 11.6 发布门禁真值表测试
    - 在 `src/build_tool/release_test.mbt` 覆盖 `release_info_with_gates`：三后端测试 / 属性测试 / 可执行文档任一未过即阻止 release-ready
    - _Requirements: 14.1, 14.2, 14.6_

- [x] 12. 最终检查点 —— 确保三后端全部测试与文档校验通过
  - 在 `wasm-gc` / `js` / `native` 三后端运行全部单元测试、15 条属性测试（各 ≥100 迭代）与 `moon test *.mbt.md`；运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。任一后端输出分歧即判失败。
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- 标记 `*` 的子任务为可选测试任务（单元 / 属性 / 集成 / 门禁），可为加速 MVP 跳过，但 P1–P15 属性测试是 Requirement 14.2 的质量门禁，发布前应全部补齐。
- 每个任务引用具体需求条款（`_Requirements: X.Y_`）以保证可追溯；每条属性子任务标注 `Property N` 与 `**Validates: Requirements X.Y**`。
- 检查点用于增量验证；属性测试以 `@infra_pbt` 验证通用不变量（每条 ≥100 迭代），单元测试锁定具体见证与边界 / 错误条件。
- **既有契约冻结**：`types.mbt` / `build_tool.mbt` / `release.mbt`（除版本字符串）既有 `pub` 声明不改；新能力一律以新增 `.mbt` 文件旁路扩展；`ParseError` 不扩容，列号诊断由 `GrammarError` 旁路并经 `to_legacy` 投影回退；图算法复用 `@directed`，不重写。
- **native 前置**：凡涉及 native 后端测试、基准运行、`README.mbt.md` 文档校验的任务（含任务 3、8、10.2、11.2、12），均须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "4.1", "5.1", "6.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "9.1", "4.2", "4.3", "4.4", "4.5", "5.2", "5.3", "5.4", "5.5", "5.6", "5.7", "6.2", "6.3", "6.4"] },
    { "id": 2, "tasks": ["2.2", "7.1", "10.1", "1.3", "1.4", "1.5", "9.2"] },
    { "id": 3, "tasks": ["2.3", "2.4", "2.5", "7.2", "7.3", "10.2"] },
    { "id": 4, "tasks": ["11.1", "11.3", "11.4"] },
    { "id": 5, "tasks": ["11.2", "11.5", "11.6"] }
  ]
}
```
