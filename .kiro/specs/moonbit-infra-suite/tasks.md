# 实现计划（Implementation Plan）：moonbit-infra-suite

## 概述（Overview）

本计划将 **moonbit-infra-suite** umbrella 设计转化为一系列增量推进的编码任务。遵循用户的 **广度优先（breadth-first）** 策略：先落地阶段 0 的共享地基（PBT 生成器、证明谓词约定、三后端 CI 矩阵与发布门禁），再按依赖关系与风险分级，把 10 个方向的子项目骨架逐一立起来。每个方向第一版只需达成"可编译 + 跑通三后端 + 一条 round-trip/不变量属性测试（≥100 迭代）+ 一个 `*.mbt.md` 可执行文档 + 独立 SemVer 0.1.0"即视为骨架达成，算法深度由各方向独立子 spec 后续迭代。

所有任务在现有 `Suquster/moonbit-pathfinding` 模块内以"方向即子包 `src/{方向}`"的方式扩展。复用既有图算法资产的方向（Build_Tool、Codegen_Infra）在任务中显式标注。

- 标注 `*` 的子任务为可选项（属性测试、单元测试、可执行文档），可为加速 MVP 跳过，但建议完成以满足 Requirement 11 质量门禁。
- 每个任务引用具体需求编号（Requirements X.Y）与正确性属性编号（Property N）。

---

## 任务（Tasks）

### 阶段 0：共享地基（横切，必须先行）

- [x] 1. 建立共享 PBT 基础设施包 infra_pbt
  - [x] 1.1 创建 `src/infra_pbt` 子包与 `moon.pkg`，实现统一生成器与断言模板
    - 定义 `Gen[T]` 生成器结构与种子驱动伪随机源 `Rng`（线性同余/xorshift，要求三后端逐位一致）
    - 实现 `round_trip`（往返断言模板）与 `holds_for_all`（不变量断言模板，默认 `iters~ : Int = 100`）
    - 约定测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`
    - _Requirements: 11.2, 11.3_
  - [x] 1.2 为 infra_pbt 自身编写属性测试
    - 验证 `Rng` 同种子产生逐位一致序列（确定性，三后端一致）
    - 验证 `holds_for_all` 默认达到 100 次迭代
    - _Requirements: 11.1, 11.2_

- [x] 2. 扩展共享证明谓词约定 proofs
  - [x] 2.1 扩展 `src/proofs`，建立各方向 `{方向}_proof.mbt` 占位与通用谓词复用约定
    - 复用既有 `predicates.mbt` 模式，谓词均为纯、全（total）的 `pub fn ... -> Bool`
    - 在相关包启用 `options("proof-enabled": true)`，预留 `moon prove` 升级路径
    - _Requirements: 11.2_

- [x] 3. 固化全方向质量门禁模板
  - [x] 3.1 将既有 `ci.yml` 三后端矩阵与可执行文档门禁固化为全方向模板
    - 配置 `matrix.backend = [wasm-gc, js, native]` 对每个方向运行同一测试套件
    - 增加 `moon test *.mbt.md` 门禁，输出分歧（含快照不一致）即构建失败
    - _Requirements: 11.1, 11.4_
  - [x] 3.2 建立独立发布元数据模型与 release-ready 聚合门禁
    - 实现 `DirectionRelease` 数据模型（name / version / changelog_path / release_ready）
    - 聚合检查：方向的测试、证明谓词、可执行文档全绿才允许进入 release-ready
    - 约定各方向独立 SemVer 与 changelog 结构
    - _Requirements: 11.5, 11.6_

- [x] 4. 检查点 —— 确认共享地基可用
  - 确保所有测试通过，如有疑问请询问用户。

---

### 阶段 1：地基库 + 高性价比方向

- [x] 5. Parser_Combinator 骨架（R4 公共地基）
  - [x] 5.1 创建 `src/parser_combinator` 子包与 `moon.pkg`，定义核心类型与原语桩
    - 定义 `Parser[T]`、`ParseResult[T]`（`Ok(T, Input)` / `Fail(Pos, expected~)`）
    - 提供基础原语桩：`pchar`、字符/词法单元匹配
    - 声明对 `@core` 的依赖
    - _Requirements: 4.1, 4.2_
  - [x] 5.2 实现组合子与回溯控制
    - 实现 `seq`、`alt`、`many`、`many1`、`optional`
    - 实现回溯模式：择一分支失败时恢复到分支起始位置；失败时不消费输入并返回含位置与期望符号的错误
    - _Requirements: 4.2, 4.3, 4.4_
  - [x] 5.3 编写解析器契约不变量属性测试
    - **Property 9：解析器组合子契约不变量**
    - **Validates: Requirements 4.2, 4.3, 4.4**
  - [x] 5.4 编写语法结构往返属性测试
    - **Property 10：解析器组合子语法结构往返**
    - **Validates: Requirements 4.5**
  - [x] 5.5 编写 `*.mbt.md` 端到端可执行文档（≥3 个解析样例）
    - 覆盖序列、择一、重复三类组合子的端到端解析样例
    - _Requirements: 4.7, 11.4_
  - [x] 5.6 建立 Parser_Combinator 独立 SemVer 0.1.0 与 changelog
    - 登记 `DirectionRelease`（version 0.1.0）
    - _Requirements: 11.5_

- [x] 6. Regex_Engine 骨架（R2，复用 parser_combinator）
  - [x] 6.1 创建 `src/regex_engine` 子包与 `moon.pkg`，定义 `Regex` 类型与解析/打印桩
    - 定义 `Regex` 枚举（Char/Class/Star/Plus/Opt/Repeat/Concat/Alt/Anchor/Group）
    - `parse_regex` 构建于 `@parser_combinator`；提供配套 `print_regex` 打印器
    - 非法表达式返回含位置的解析错误且不构造自动机
    - _Requirements: 2.1, 2.2, 2.3_
  - [x] 6.2 实现 NFA/DFA 构造与匹配执行
    - `build_nfa`（Thompson 构造）、`to_dfa`（子集构造确定化）、`find`（返回是否匹配 + 匹配区间）
    - _Requirements: 2.4, 2.5_
  - [x] 6.3 编写正则语法树往返属性测试
    - **Property 4：Regex 语法树往返**
    - **Validates: Requirements 2.2, 2.7**
  - [x] 6.4 编写 NFA/DFA 差分一致性属性测试
    - **Property 5：Regex NFA/DFA 差分一致性**
    - **Validates: Requirements 2.6**
  - [x] 6.5 编写非法表达式错误条件属性测试
    - **Property 6：Regex 非法表达式错误条件**
    - **Validates: Requirements 2.3**
  - [x] 6.6 编写 `*.mbt.md` 可执行文档示例
    - 展示解析、匹配与匹配区间返回
    - _Requirements: 11.4_
  - [x] 6.7 建立 Regex_Engine 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 7. Serialization 骨架（R9，复用 parser_combinator）
  - [x] 7.1 创建 `src/serialization` 子包与 `moon.pkg`，定义编解码与 `.proto` 解析桩
    - 定义 `encode` / `decode` / `parse_proto` / `gen_moonbit` 高层接口桩
    - `proto_parser` 构建于 `@parser_combinator`
    - 解码失败返回含出错字节偏移的错误且不产生部分构造对象
    - _Requirements: 9.1, 9.2, 9.4, 9.5_
  - [x] 7.2 实现 protobuf wire format 编解码
    - 实现 `encode`（内存对象 → wire format）与 `decode`（字节 + 模式 → 消息对象）
    - _Requirements: 9.1, 9.2_
  - [x] 7.3 编写编解码往返属性测试
    - **Property 20：Protobuf 编解码往返**
    - **Validates: Requirements 9.3**
  - [x] 7.4 编写非法字节错误条件属性测试
    - **Property 21：Protobuf 非法字节错误条件**
    - **Validates: Requirements 9.4**
  - [x] 7.5 编写 `*.mbt.md` 可执行文档示例
    - 展示编码再解码的往返用法
    - _Requirements: 11.4_
  - [x] 7.6 建立 Serialization 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 8. 检查点 —— 阶段 1 地基库就绪
  - 确保所有测试通过，如有疑问请询问用户。

---

### 阶段 2：复用既有图资产的方向

- [x] 9. Build_Tool 骨架（R6，复用 @directed.topo_sort / condensation）
  - [x] 9.1 创建 `src/build_tool` 子包与 `moon.pkg`，定义 `BuildGraph` 类型与接口桩
    - 定义 `BuildGraph`、`parse_rules`、`is_dirty`、`schedule` 接口桩
    - 声明对 `@directed` 的依赖（复用 `topo_sort` 与 `condensation`）
    - _Requirements: 6.1, 6.4_
  - [x] 9.2 实现环检测、拓扑排序与并行调度（复用既有图资产）
    - `detect_cycle` 复用 `@directed.condensation` / `tarjan_scc` 识别环并报告节点序列
    - `topo_order` 复用 `@directed.topo_sort`；`schedule` 产出无依赖任务并行批次
    - `is_dirty` 基于 mtime 与内容哈希；实现增量空操作（输入未变 → 零重建）
    - _Requirements: 6.2, 6.3, 6.4, 6.5, 6.6_
  - [x] 9.3 编写构建调度拓扑不变量属性测试
    - **Property 14：构建调度拓扑不变量**
    - **Validates: Requirements 6.7**
  - [x] 9.4 编写环检测与增量幂等属性测试
    - **Property 13：构建图环检测错误条件**
    - **Property 15：增量构建幂等（空操作）**
    - **Validates: Requirements 6.2, 6.6**
  - [x] 9.5 编写 `*.mbt.md` 可执行文档示例
    - 展示构建图解析与拓扑调度
    - _Requirements: 11.4_
  - [x] 9.6 建立 Build_Tool 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 10. Logging_Library 骨架（R7）
  - [x] 10.1 创建 `src/logging` 子包与 `moon.pkg`，定义 `Event`/`Span`/`Level` 类型与接口桩
    - 定义 `Level`、`Event`、`Span` 类型及 `log` / `enter_span` / `exit_span` / `format_json` / `parse_json_log` 桩
    - 声明对 `moonbitlang/async` 的依赖
    - _Requirements: 7.1, 7.3_
  - [x] 10.2 实现级别过滤、span 树、trace 传播与结构化输出
    - `log` 丢弃低于阈值的事件；`enter_span` 关联父 span 形成 span 树；`exit_span` 记录时长
    - 跨异步任务边界传播 trace 标识；`format_json` 产出可解析结构化输出
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_
  - [x] 10.3 编写级别过滤与 span/trace 不变量属性测试
    - **Property 16：日志级别阈值过滤**
    - **Property 17：Span 树与 trace 上下文传播不变量**
    - **Validates: Requirements 7.2, 7.3, 7.4, 7.6**
  - [x] 10.4 编写结构化日志往返属性测试
    - **Property 18：结构化日志往返**
    - **Validates: Requirements 7.7**
  - [x] 10.5 编写 `*.mbt.md` 可执行文档示例
    - 展示结构化字段记录与 span 进入/退出
    - _Requirements: 11.4_
  - [x] 10.6 建立 Logging_Library 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 11. Codegen_Infra 骨架（R3，复用图着色资产）
  - [x] 11.1 创建 `src/codegen_infra` 子包与 `moon.pkg`，定义 `InterferenceGraph`/SSA 类型与接口桩
    - 定义 `InterferenceGraph`、`Location`、`SsaProgram` 类型及分配/SSA/指令选择接口桩
    - 声明对既有图着色与 `@directed` 干涉图资产的依赖
    - _Requirements: 3.1, 3.4, 3.7_
  - [x] 11.2 实现寄存器分配、SSA 构造与 pass 流水线（复用图着色）
    - `allocate_coloring` 复用既有图着色资产；`allocate_linear_scan` 提供线性扫描策略
    - `build_ssa`（含 φ 函数插入）；`run_passes` 按声明顺序执行并保持 SSA 不变量
    - `select` 提供指令选择 DSL
    - _Requirements: 3.1, 3.2, 3.4, 3.6, 3.7_
  - [x] 11.3 编写寄存器分配干涉不变量属性测试
    - **Property 7：寄存器分配干涉不变量**
    - **Validates: Requirements 3.3**
  - [x] 11.4 编写 SSA 单赋值不变量属性测试与证明谓词
    - **Property 8：SSA 单赋值不变量（建立与保持）**
    - 在 `src/proofs/codegen_infra_proof.mbt` 实现 `ssa_single_assignment` 谓词
    - **Validates: Requirements 3.5, 3.6**
  - [x] 11.5 编写 `*.mbt.md` 可执行文档示例
    - 展示干涉图着色分配与 SSA 构造
    - _Requirements: 11.4_
  - [x] 11.6 建立 Codegen_Infra 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 12. 检查点 —— 阶段 2 复用图资产方向就绪
  - 确保所有测试通过，如有疑问请询问用户。

---

### 阶段 3：高难度 / 高风险方向

- [x] 13. DST_Framework 骨架（R8，复用 infra_pbt 随机源）
  - [x] 13.1 创建 `src/dst` 子包与 `moon.pkg`，定义 `Rng`/`Sim` 类型与接口桩
    - 复用 `infra_pbt` 的种子驱动伪随机源理念，定义 `Rng`、`Sim` 及 `step`/`run`/`replay` 桩
    - _Requirements: 8.1, 8.3_
  - [x] 13.2 实现确定性调度、故障注入与重放
    - `step` 依确定性随机源选择下一任务；`inject_fault` 在指示注入点触发故障
    - `run` 保证同种子 → 同调度序列 + 同终态；失败输出可重放种子与事件轨迹；`replay` 复现相同失败
    - _Requirements: 8.3, 8.4, 8.5, 8.6_
  - [x] 13.3 编写确定性可重放不变量属性测试
    - **Property 19：DST 确定性可重放不变量**
    - **Validates: Requirements 8.2, 8.6**
  - [x] 13.4 编写 `*.mbt.md` 可执行文档示例
    - 展示同种子两次运行产生一致调度序列
    - _Requirements: 11.4_
  - [x] 13.5 建立 DST_Framework 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 14. LSP_Binding / LSP_Server 骨架（R5，复用 serialization JSON）
  - [x] 14.1 创建 `src/lsp_binding` 子包与 `moon.pkg`，定义 `JsonRpcMessage` 类型与编解码/分发桩
    - 定义 `JsonRpcMessage`（Request/Response/Notification）与 `decode_message`/`encode_message`/`dispatch` 桩
    - 复用 `@serialization` 的 JSON 编解码骨架
    - 非法消息返回符合规范的错误响应且不终止进程
    - _Requirements: 5.1, 5.2, 5.3_
  - [x] 14.2 创建 `src/lsp_server` 子包与能力处理器桩
    - 实现 `on_initialize`（在 capabilities 声明诊断/补全/定义/悬停）、`on_did_change`（重分析 + publishDiagnostics）、`on_completion`、`on_definition`、`on_hover` 桩，针对某通用 DSL
    - _Requirements: 5.4, 5.5, 5.6, 5.7, 5.8_
  - [x] 14.3 编写 JSON-RPC 消息往返属性测试
    - **Property 11：JSON-RPC 消息往返**
    - **Validates: Requirements 5.9**
  - [x] 14.4 编写非法消息错误条件属性测试
    - **Property 12：LSP_Server 非法消息错误条件**
    - **Validates: Requirements 5.3**
  - [x] 14.5 编写 `*.mbt.md` 可执行文档示例
    - 展示 JSON-RPC 请求解码、分发与编码响应
    - _Requirements: 11.4_
  - [x] 14.6 建立 LSP_Binding / LSP_Server 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 15. Mini_Compiler 骨架（R1，复用 parser_combinator）
  - [x] 15.1 创建 `src/mini_compiler` 子包与 `moon.pkg`，定义 `Token`/`Ast`/`TypedAst` 类型与流水线桩
    - 在文档中声明目标语言文法（产生式规则）
    - 定义 `lex`/`parse`/`check`/`eval`/`print_ast` 桩；`parse` 构建于 `@parser_combinator`
    - 词法/语法错误返回含行列位置的诊断且不产生 AST
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 15.2 实现树遍历解释器与配套 AST 打印器
    - `eval` 产生与语义规范一致的运行结果；`print_ast` 配套打印器支撑往返性质
    - `check` 对类型不一致返回含冲突类型与节点位置的类型错误
    - _Requirements: 1.4, 1.5, 1.6_
  - [x] 15.3 编写 AST 往返属性测试
    - **Property 1：Mini_Compiler AST 往返**
    - **Validates: Requirements 1.2, 1.8**
  - [x] 15.4 编写词法/语法错误条件属性测试
    - **Property 2：Mini_Compiler 词法/语法错误条件**
    - **Validates: Requirements 1.3**
  - [x] 15.5 编写求值确定性与作用域不变量属性测试及证明谓词
    - **Property 3：Mini_Compiler 求值确定性与作用域不变量**
    - 在 `src/proofs/mini_compiler_proof.mbt` 实现作用域绑定一致性谓词
    - **Validates: Requirements 1.9**
  - [x] 15.6 编写 `*.mbt.md` 可执行文档示例
    - 展示源码 → AST → 求值的端到端流程
    - _Requirements: 11.4_
  - [x] 15.7 建立 Mini_Compiler 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 16. Actor_Framework 骨架（R10，基于 moonbitlang/async）
  - [x] 16.1 创建 `src/actor` 子包与 `moon.pkg`，定义 `ActorRef`/`Mailbox` 类型与接口桩
    - 定义 `ActorRef[M]`、`Mailbox[M]` 及 `spawn`/`send`/`stop` 桩
    - 声明对 `moonbitlang/async` 的依赖
    - _Requirements: 10.1, 10.2_
  - [x] 16.2 实现邮箱 FIFO、串行处理与监督错误隔离
    - `send` 追加到邮箱队列；保证单 actor 一次仅处理一条消息；空邮箱时挂起不占资源
    - 未捕获错误终止该 actor 并通知 supervisor，不影响其他 actor；`stop` 处理完当前消息后停止
    - _Requirements: 10.2, 10.3, 10.5, 10.6, 10.7_
  - [x] 16.3 编写串行与 FIFO 顺序不变量属性测试
    - **Property 22：Actor 串行与 FIFO 顺序不变量**
    - **Validates: Requirements 10.3, 10.4**
  - [x] 16.4 编写错误隔离不变量属性测试
    - **Property 23：Actor 错误隔离不变量**
    - **Validates: Requirements 10.6**
  - [x] 16.5 编写 `*.mbt.md` 可执行文档示例
    - 展示 spawn / send / stop 的消息传递用法
    - _Requirements: 11.4_
  - [x] 16.6 建立 Actor_Framework 独立 SemVer 0.1.0 与 changelog
    - _Requirements: 11.5_

- [x] 17. 检查点 —— 阶段 3 方向骨架就绪
  - 确保所有测试通过，如有疑问请询问用户。

---

### 收尾：全方向三后端一致性与发布门禁聚合

- [x] 18. 接入并验证全方向横切门禁
  - [x] 18.1 将全部 10 个方向接入三后端 CI 矩阵与 release-ready 聚合门禁
    - 将各方向纳入 `matrix.backend = [wasm-gc, js, native]` 同一测试套件，任一后端分歧判定为构建失败
    - 将各方向 `DirectionRelease` 聚合到 release-ready 门禁
    - _Requirements: 11.1, 11.6_
  - [x] 18.2 编写全方向三后端差分一致性属性测试
    - **Property 24：三后端差分一致性（横切）**
    - **Validates: Requirements 1.10, 2.9, 3.8, 4.8, 6.8, 8.7, 9.9, 11.1**

- [x] 19. 最终检查点 —— 确认全套件三后端通过
  - 确保所有测试通过，如有疑问请询问用户。

---

## 注意事项（Notes）

- 标注 `*` 的子任务为可选项，可为加速 MVP 跳过；核心实现任务（子包搭建、核心实现、SemVer 登记）不可标注为可选。
- 每个任务引用具体需求以保证可追溯性；属性测试任务显式引用设计文档中的正确性属性编号（Property N）。
- 检查点用于增量验证；可执行文档（`*.mbt.md`）与属性测试共同支撑 Requirement 11 横切质量门禁。
- 复用既有资产：Build_Tool（任务 9）复用 `@directed.topo_sort` / `condensation`；Codegen_Infra（任务 11）复用既有图着色与干涉图资产。
- 依赖驱动排序：地基包（Parser_Combinator、Serialization 的 JSON 编解码）领先于其消费者（Regex / Mini_Compiler / LSP）。
- 本计划仅创建编码、测试与可执行文档相关任务，不含部署、用户验收、性能采集等非编码活动。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "3.1", "3.2", "5.1", "9.1", "10.1", "11.1", "16.1"] },
    { "id": 2, "tasks": ["5.2", "9.2", "10.2", "11.2", "13.1", "16.2"] },
    { "id": 3, "tasks": ["5.3", "5.4", "5.5", "5.6", "6.1", "7.1", "9.3", "9.4", "9.5", "9.6", "10.3", "10.4", "10.5", "10.6", "11.3", "11.4", "11.5", "11.6", "13.2", "16.3", "16.4", "16.5", "16.6"] },
    { "id": 4, "tasks": ["6.2", "7.2", "13.3", "13.4", "13.5"] },
    { "id": 5, "tasks": ["6.3", "6.4", "6.5", "6.6", "6.7", "7.3", "7.4", "7.5", "7.6", "14.1", "15.1"] },
    { "id": 6, "tasks": ["14.2", "15.2"] },
    { "id": 7, "tasks": ["14.3", "14.4", "14.5", "14.6", "15.3", "15.4", "15.5", "15.6", "15.7"] },
    { "id": 8, "tasks": ["18.1"] },
    { "id": 9, "tasks": ["18.2"] }
  ]
}
```
