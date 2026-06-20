# Implementation Plan

> 实施计划 · 全程中文 · 档位 🟣3「业界顶尖（旗舰）」· 仅新增（bypass）· 三后端一致 · PBT ≥100 迭代

## Overview

本计划在现有 10 个方向包的公开 API 之上做增量加固，覆盖 requirements.md 的 12 条需求主线。执行顺序按依赖从底层到上层：先建共享叶子工具 `infra_text`（任务 1）与 PBT 基础设施增强 `infra_pbt`（任务 2），再逐方向加固（任务 3–11），随后统一替换循环拼接点（任务 12），最后做横切质量门禁校验（任务 13）。每个方向完成后运行 `moon info && moon fmt && moon test` 并做一次 git commit。

## Tasks

- [x] 1. 共享高效文本构建工具 `infra_text`（Requirement 1）
  - [x] 1.1 创建 `src/infra_text` 包与 `TextBuilder` 核心实现
    - 新建 `src/infra_text/moon.pkg`（叶子包，无方向依赖）与 `text_builder.mbt`
    - 实现 `TextBuilder`：`new`/`with_capacity`/`push_char`/`push_str`/`len`/`is_empty`/`build`/`reset`
    - `build` 先 flush `char_buf` 到 `chunks` 再 `join`，且不清空状态（支持再追加）
    - 运行 `moon info && moon fmt`，确认新增 `.mbti` 条目
    - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - [x] 1.2 为 `TextBuilder` 编写属性测试（≥100 迭代，三后端）
    - 等价性：`build()` == 等价顺序 `+` 拼接（随机片段序列）
    - 再追加保持：`build` 后继续 `push_*`，下次 `build` 含全部历史片段且顺序保持
    - 线性：大规模片段追加不超时（规模递增）
    - _Requirements: 1.2, 1.3, 1.4_

- [x] 2. PBT 框架增强 `infra_pbt`（Requirement 11）
  - [x] 2.1 生成器组合子 `one_of`/`frequency`/`sized`
    - 新增 `src/infra_pbt/combinators.mbt`
    - 复用既有 `Gen`/`Rng`，不改既有签名
    - _Requirements: 11.3_
  - [x] 2.2 shrink 收缩机制
    - 新增 `src/infra_pbt/shrink.mbt`：`Shrinkable`/`shrink_int`/`shrink_array`/`check_with_shrink`/`CheckResult`
    - _Requirements: 11.1, 11.2_
  - [x] 2.3 统计收集 `Stats`/`holds_for_all_stats`
    - 新增 `src/infra_pbt/stats.mbt`
    - _Requirements: 11.5_
  - [x] 2.4 PBT 增强属性测试（≥100 迭代，三后端）
    - shrink 产物仍使属性失败；`frequency` 大样本占比趋近权重；统计计数正确
    - _Requirements: 11.1, 11.2, 11.4, 11.5_

- [x] 3. 日志真实 I/O 落地与运行时调级（Requirement 2）
  - [x] 3.1 Sink 层实现
    - 新增 `src/logging/sink_layer.mbt`：`SinkTarget`/`SinkHandle`（`console`/`callback`/`buffered`/`set_level`/`emit`/`flush`）
    - Console 经 `format_event` + `println`；不改既有 `Sink`
    - 内部文本拼接用 `infra_text.TextBuilder`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_
  - [x] 3.2 Sink 层属性测试（≥100 迭代，三后端）
    - CallbackSink 恰好一次；BufferedSink 阈值前不下发、阈值/flush 后按序全发；低于级别不下发
    - _Requirements: 2.2, 2.3, 2.4, 2.6_
  - [x] 3.3 方向校验
    - `moon info && moon fmt && moon test`，确认 `.mbti` 只增不减、既有测试通过
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 4. 构建工具动作执行框架与持久化（Requirement 3）
  - [x] 4.1 Executor 框架实现
    - 新增 `src/build_tool/executor.mbt`：`Action`/`ActionResult`/`Executor` trait/`DryRunExecutor`/`CallbackExecutor`/`ParallelSchedule`/`build_parallel_schedule`/`BuildLog`/`run_actions`
    - 复用既有 `content_hash`/`cache_key`/`schedule` 分层逻辑
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
  - [x] 4.2 Executor 框架属性测试（≥100 迭代，三后端）
    - 波次内无依赖路径；全波次展开 == 全 Action 各一次；指纹相同则 up-to-date
    - _Requirements: 3.4, 3.6, 3.7_
  - [x] 4.3 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 5. 正则引擎 Unicode 类别、混合执行与实用 API（Requirement 5）
  - [x] 5.1 Unicode General Category 支持
    - 新增 `src/regex_engine/unicode_gc.mbt`：`GeneralCategory`/`unicode_category`/`category_charset`/`parse_unicode_class`（区间表为命名常量）
    - _Requirements: 5.1_
  - [x] 5.2 CharSet 二分查询与实用 API
    - 新增 `src/regex_engine/api_ext.mbt`：`CharSet::contains_binary`、`Pattern::find_at`/`split_n`/`replace_fn`（`replace_fn` 内部用 `TextBuilder`）
    - _Requirements: 5.2, 5.5, 5.6, 5.7_
  - [x] 5.3 Hybrid 匹配器
    - 新增 `src/regex_engine/hybrid.mbt`：`HybridMatcher`（缓存上限 + 切换 NFA）
    - _Requirements: 5.3, 5.4_
  - [x] 5.4 正则增强属性测试（≥100 迭代，三后端）
    - `is_match` 与 `find` 一致；`contains_binary` 与线性一致；Hybrid 与 NFA 一致；`find_at(k)` 起点约束
    - _Requirements: 5.2, 5.3, 5.4, 5.6, 5.7_
  - [x] 5.5 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 6. 解析器组合子增量解析、错误恢复与有界缓存（Requirement 6）
  - [x] 6.1 错误恢复组合子
    - 新增 `src/parser_combinator/incremental_ext.mbt`：`RecoveryStrategy`/`with_recovery`
    - _Requirements: 6.3_
  - [x] 6.2 有界 packrat 缓存
    - 新增 `src/parser_combinator/bounded_packrat.mbt`：`BoundedCache`/`Grammar::run_packrat_bounded`（LRU）
    - _Requirements: 6.4, 6.5_
  - [x] 6.3 解析器增强属性测试（≥100 迭代，三后端）
    - 任意分块 == 一次性解析（复用 `run_incremental`/`drive`）；有界缓存与无淘汰一致；条目 ≤ cap
    - _Requirements: 6.1, 6.2, 6.4, 6.5_
  - [x] 6.4 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 7. 序列化 proto3 增强、结构化代码生成与流式编解码（Requirement 4）
  - [x] 7.1 结构化代码生成 AST
    - 新增 `src/serialization/codegen_ast.mbt`：`CodeNode`/`render_code`（内部 `TextBuilder`）/`gen_moonbit_ast`/`gen_moonbit_structured`
    - _Requirements: 4.3_
  - [x] 7.2 proto3 service/rpc/import 解析与打印
    - 新增 `src/serialization/proto_service.mbt`：`RpcDef`/`ServiceDef`/`ImportDecl`/`ProtoFile`/`parse_proto_file`/`print_proto_file`（打印经 `CodeNode`）
    - _Requirements: 4.1, 4.7_
  - [x] 7.3 Any 类型与流式编解码
    - 新增 `src/serialization/streaming.mbt`：`AnyValue`/`encode_any`/`decode_any`/`ByteSink`/`ByteSource`/`encode_to`/`decode_from`
    - _Requirements: 4.2, 4.5_
  - [x] 7.4 序列化增强属性测试（≥100 迭代，三后端）
    - proto 文件 print→parse 往返；`encode_any`/`decode_any` 往返；`decode_from(encode_to(m))==m`
    - _Requirements: 4.4, 4.6_
  - [x] 7.5 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 8. 代码生成基础设施类型化 IR、验证器与解释器（Requirement 7）
  - [x] 8.1 类型化 IR 数据结构
    - 新增 `src/codegen_infra/typed_ir.mbt`：`Operand`/`TypedInstr`/`TypedBlock`/`TypedFunction`（替代字符串化指令，平行 bypass）
    - _Requirements: 7.1_
  - [x] 8.2 IR 验证器
    - 新增 `src/codegen_infra/ir_validator.mbt`：`IrError`/`validate_ir`（SSA/类型/控制流）
    - _Requirements: 7.2, 7.3, 7.4, 7.5_
  - [x] 8.3 IR 解释器
    - 新增 `src/codegen_infra/ir_interp.mbt`：`IrEvalResult`/`interp_ir`
    - _Requirements: 7.6_
  - [x] 8.4 IR 属性测试（≥100 迭代，三后端）
    - 合法 SSA 通过；重复定义→SsaViolation；类型不符→TypeMismatch；控制流缺失→ControlFlowError；解释器结果确定
    - _Requirements: 7.2, 7.3, 7.4, 7.5, 7.6_
  - [x] 8.5 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 9. 确定性仿真可执行任务、模拟网络与不变量（Requirement 8）
  - [x] 9.1 可执行任务体
    - 新增 `src/dst/task_body.mbt`：`SimContext`/`TaskResult`/`ExecutableTask`/`run_executable`（复用 `World`/`Protocol`/`NetworkSim`/`SimClock`）
    - _Requirements: 8.1, 8.2, 8.4_
  - [x] 9.2 eventually 最终性断言
    - 新增 `src/dst/eventually.mbt`：`EventuallyResult`/`eventually`（复用既有 `eval_invariants`）
    - _Requirements: 8.5, 8.6_
  - [x] 9.3 仿真属性测试（≥100 迭代，三后端）
    - 相同种子逐事件可复现；invariant 违例报告；eventually 未成立报告
    - _Requirements: 8.3, 8.5, 8.6_
  - [x] 9.4 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [x] 10. 迷你编译器语言特性与字节码优化（Requirement 9）
  - [x] 10.1 match/元组/列表特性
    - 新增 `src/mini_compiler/match_ext.mbt`：`Pattern`/`ExprX`/`check_x`/`eval_x`/`TypeMismatch`（复用既有 `Expr`/`Ty`/`Val`）
    - _Requirements: 9.1, 9.5_
  - [x] 10.2 peephole 与 TCO 优化
    - 新增 `src/mini_compiler/peephole.mbt` 与 `tco.mbt`：`peephole_opt`/`tco_opt`（复用既有 `Bytecode`/`Instr`/`VM`）
    - _Requirements: 9.2, 9.3_
  - [x] 10.3 编译器增强属性测试（≥100 迭代，三后端）
    - 优化前后求值相等；TCO 帧数不线性增长；类型错误含 expected/actual
    - _Requirements: 9.2, 9.3, 9.4, 9.5_
  - [x] 10.4 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [ ] 11. LSP 协议鲁棒性与增量同步（Requirement 10）
  - [-] 11.1 JSON-RPC 成帧与校验
    - 新增 `src/lsp_server/jsonrpc_frame.mbt`：`FrameError`/`encode_frame`/`decode_frame`（`\r\n`/`\n` 兼容）/`JsonRpcError`/`validate_jsonrpc`
    - _Requirements: 10.1, 10.2, 10.3, 10.6_
  - [~] 11.2 增量文档同步（O(N)）
    - 新增 `src/lsp_server/incremental_sync.mbt`：`apply_incremental`（`Array[Char]` 切片，次平方级）
    - _Requirements: 10.4, 10.5_
  - [~] 11.3 LSP 增强属性测试（≥100 迭代，三后端）
    - 成帧往返；增量同步 == 全量替换（对照 `apply_changes`）；换行兼容；非法结构返回错误对象
    - _Requirements: 10.2, 10.3, 10.4, 10.6_
  - [~] 11.4 方向校验
    - `moon info && moon fmt && moon test`
    - _Requirements: 12.2, 12.3, 12.6_

- [ ] 12. 消除 O(n²) 拼接：方向内循环拼接替换（Requirement 1.5）
  - [~] 12.1 审计并替换 serialization 循环拼接点
    - grep 定位 `serialization` 中循环内 `out = out + ...`，逐个替换为 `TextBuilder`；新增等价性快照测试
    - _Requirements: 1.5, 1.6_
  - [~] 12.2 审计并替换 build_tool 循环拼接点（`print_rules` 等）
    - _Requirements: 1.5, 1.6_
  - [~] 12.3 审计并替换 regex_engine 循环拼接点（`print_ast`/`print_regex` 等）
    - _Requirements: 1.5, 1.6_
  - [~] 12.4 审计并替换 parser_combinator 循环拼接点（`print_json`/`print_expr` 等）
    - _Requirements: 1.5, 1.6_
  - [~] 12.5 审计并替换 logging 循环拼接点（格式化器等）
    - _Requirements: 1.5, 1.6_
  - [~] 12.6 替换后等价性属性测试与全方向校验
    - 每个被改造函数输出与改造前逐字符相等；`moon info && moon fmt && moon test`
    - _Requirements: 1.5, 12.2, 12.3, 12.6_

- [ ] 13. 横切质量门禁最终校验（Requirement 12）
  - [~] 13.1 三后端全量测试
    - `moon test --target wasm-gc`、`moon test --target js`、`moon test --target native` 全通过
    - _Requirements: 12.4, 12.5_
  - [~] 13.2 `.mbti` 只增不减审计与文档更新
    - diff 全部 `.mbti` 确认既有条目不变；更新 `README.mbt.md` 与 `CHANGELOG.md`
    - _Requirements: 12.1, 12.2, 12.3_

## Task Dependency Graph

```json
{
  "waves": [
    { "wave": 1, "tasks": ["1.1", "1.2"] },
    { "wave": 2, "tasks": ["2.1", "2.2", "2.3", "2.4"] },
    { "wave": 3, "tasks": ["3.1", "3.2", "3.3", "4.1", "4.2", "4.3", "5.1", "5.2", "5.3", "5.4", "5.5", "6.1", "6.2", "6.3", "6.4", "7.1", "7.2", "7.3", "7.4", "7.5", "8.1", "8.2", "8.3", "8.4", "8.5", "9.1", "9.2", "9.3", "9.4", "10.1", "10.2", "10.3", "10.4", "11.1", "11.2", "11.3", "11.4"] },
    { "wave": 4, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5", "12.6"] },
    { "wave": 5, "tasks": ["13.1", "13.2"] }
  ]
}
```

依赖图（可读形式）：

```
1 (infra_text)  ──┬─> 3 (logging)      ──> 12.5
                  ├─> 5 (regex)        ──> 12.3
                  ├─> 7 (serialization)──> 12.1
                  ├─> 12.2 (build_tool 拼接)
                  └─> 12.4 (parser 拼接)

2 (infra_pbt)   ──> 所有方向的属性测试子任务（2.4/3.2/4.2/5.4/6.3/7.4/8.4/9.3/10.3/11.3）

3 (logging)        依赖 1、2
4 (build_tool)     依赖 2（4.1 复用既有 schedule）
5 (regex)          依赖 1、2
6 (parser)         依赖 2
7 (serialization)  依赖 1、2
8 (codegen IR)     依赖 2
9 (dst)            依赖 2
10 (mini_compiler) 依赖 2
11 (lsp)           依赖 2

12 (循环拼接替换)  依赖 1，且各子任务依赖对应方向已加固（3/4/5/6/7）
13 (横切门禁)      依赖 全部 1–12 完成
```

依赖说明：
- 任务 1 必须最先完成（被 logging/regex/serialization/各拼接替换复用）。
- 任务 2 次之（被所有属性测试子任务复用）。
- 任务 3–11 在 1、2 完成后可并行推进（彼此无横向依赖）。
- 任务 12 的各子任务需对应方向核心加固完成后进行。
- 任务 13 为最终汇总校验，依赖全部前序任务。

## Notes

- **bypass 原则**：所有新能力以新增类型/函数/方法实现，严禁修改或删除既有公开签名；每次 `moon info` 后 diff `.mbti` 确认只增不减。
- **禁止改既有测试**：新代码致既有测试失败时修新代码，不改测试。
- **PBT 标准**：每个新增公开函数至少一个属性测试，`iters >= 100`，覆盖往返/等价/代数律/边界。
- **三后端**：完成方向后跑 `wasm-gc`/`js`/`native` 三后端。
- **反模式禁令**：禁止循环内 `out = out + ...`、字符串模拟结构化数据、`abort()`/`todo!()`/`panic` 占位。
- **语言**：代码注释与文档全程中文。
