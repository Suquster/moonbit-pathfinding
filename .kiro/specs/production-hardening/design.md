# Design Document

> 设计文档 · 全程中文撰写 · 档位 🟣3「业界顶尖（旗舰）」

## Overview

> 概述

本设计文档为 **Production_Hardening（生产级加固）** 规格提供完整的技术方案。目标是在仓库现有 10 个方向包的公开 API 之上，以「**冻结现有 API + 仅新增（bypass）**」策略做增量加固，把实现质量从教学/展示级拔高到生产级。

设计遵循三条不可破坏的基本盘：

1. **只增不减**：任何既有公开函数、类型、签名一律不修改、不删除；新能力通过新增类型/函数/方法实现。每个受影响包的 `.mbti` 接口文件相对加固前只增不减。
2. **逐字符等价**：凡是用 `Shared_Text_Builder` 替换旧 `out = out + ...` 拼接的函数，其输出与改造前逐字符相等（往返/等价属性测试守护）。
3. **三后端一致**：所有新增属性测试在 `wasm-gc`、`js`、`native` 三后端结果一致，每个属性测试迭代 ≥ 100 次。

### 设计映射总览（需求 → 新增包/模块）

| 需求 | 方向 | 新增载体 | 核心新增 API（bypass） |
|------|------|----------|------------------------|
| R1 | 共享 | 新包 `src/infra_text` | `TextBuilder`：`new`/`with_capacity`/`push_char`/`push_str`/`build`/`len`/`reset` |
| R2 | logging | `logging/sink_layer.mbt` | `ConsoleSink`/`CallbackSink`/`BufferedSink`/`SinkHandle`/`emit`/`set_level`/`flush` |
| R3 | build-tool | `build_tool/executor.mbt` | `Action`/`Executor`/`DryRunExecutor`/`CallbackExecutor`/`ParallelSchedule`/`BuildLog`/`run_actions` |
| R4 | serialization | `serialization/proto_service.mbt`、`codegen_ast.mbt`、`streaming.mbt` | `ServiceDef`/`RpcDef`/`Import`/`CodeNode`/`render_code`/`encode_to`/`decode_from`/`encode_any`/`decode_any` |
| R5 | regex-engine | `regex_engine/unicode_gc.mbt`、`hybrid.mbt`、`api_ext.mbt` | `unicode_category`/`HybridMatcher`/`find_at`/`split_n`/`replace_fn`/`CharSet::contains_binary` |
| R6 | parser-combinator | `parser_combinator/incremental_ext.mbt`、`bounded_packrat.mbt` | `with_recovery`/`run_packrat_bounded`/`BoundedCache`/`RecoveryStrategy` |
| R7 | codegen-infra | `codegen_infra/typed_ir.mbt`、`ir_validator.mbt`、`ir_interp.mbt` | `TypedInstr`/`Operand`/`TypedBlock`/`validate_ir`/`interp_ir` |
| R8 | dst | `dst/task_body.mbt`、`dst/eventually.mbt` | `TaskBody`/`SimContext`/`TaskResult`/`run_executable`/`eventually`/`EventuallyResult` |
| R9 | mini-compiler | `mini_compiler/match_ext.mbt`、`peephole.mbt`、`tco.mbt` | `EMatch`/`EList`/`Pattern`/`peephole_opt`/`tco_opt`/`TypeMismatch` |
| R10 | lsp | `lsp_server/jsonrpc_frame.mbt`、`incremental_sync.mbt` | `encode_frame`/`decode_frame`/`FrameError`/`apply_incremental`/`validate_jsonrpc` |
| R11 | infra_pbt | `infra_pbt/shrink.mbt`、`combinators.mbt`、`stats.mbt` | `Shrinkable`/`shrink_int`/`one_of`/`frequency`/`sized`/`check_with_shrink`/`Stats` |
| R12 | 横切 | 全包 | 质量门禁约束，无新增运行时 API |

### 包依赖约束

新增的共享工具包 `src/infra_text` 是**叶子基础设施包**，不依赖任何方向包；各方向包可单向依赖 `infra_text`。严禁方向包之间互相依赖（如 `regex_engine` 不得依赖 `serialization`）。`infra_pbt` 的增强仍保持其作为共享测试基础设施的地位。

---

## Architecture

> 架构

整体架构为「一个共享叶子基础设施包 + 十个方向包的 bypass 增量层」：

- **基础设施层**：新增 `src/infra_text`（`TextBuilder`，被多方向复用以消除 O(n²) 拼接）；增强 `src/infra_pbt`（shrink/组合子/统计，被全部新增属性测试复用）。
- **方向增量层**：每个方向包新增独立的 `*.mbt` 文件承载新能力，不修改既有文件中的公开签名；既有 `.mbt` 仅在「内部实现替换为 TextBuilder」时改动函数体，保持签名与输出逐字符不变。
- **依赖方向**：方向包 → `infra_text`（单向）；测试 → `infra_pbt`（单向）；方向包之间无横向依赖。
- **数据流**：源文本/字节/IR → 解析/构造为结构化模型 → 验证/优化/执行 → 经 `TextBuilder`/结构化 AST 物化为输出，全程线性复杂度热路径。

详见上文「设计映射总览」与各方向小节。

## Components and Interfaces

> 组件与接口

各组件的完整公开接口（全部为 bypass 新增）已在上文分方向给出，汇总如下：

- **Shared_Text_Builder**（R1）：`TextBuilder`，见「Shared_Text_Builder 设计」。
- **Logging_Sink_Layer**（R2）：`SinkHandle`/`SinkTarget`，见「Logging Sink 层设计」。
- **Build_Executor_Framework**（R3）：`Action`/`Executor`/`ParallelSchedule`/`BuildLog`，见「Build Executor 框架设计」。
- **Serialization_Enhancer**（R4）：`ProtoFile`/`ServiceDef`/`CodeNode`/`AnyValue`/`encode_to`/`decode_from`，见「Serialization 增强设计」。
- **Regex_Engine 扩展**（R5）：`unicode_category`/`HybridMatcher`/`find_at`/`split_n`/`replace_fn`/`contains_binary`，见「Regex 引擎增强设计」。
- **Parser_Combinator 扩展**（R6）：`with_recovery`/`run_packrat_bounded`/`RecoveryStrategy`，见「Parser Combinator 增强设计」。
- **Codegen_IR**（R7）：`TypedInstr`/`Operand`/`TypedFunction`/`validate_ir`/`interp_ir`，见「Codegen-infra 类型化 IR 设计」。
- **Dst_Simulator 扩展**（R8）：`ExecutableTask`/`SimContext`/`TaskResult`/`run_executable`/`eventually`，见「DST 可执行任务设计」。
- **Mini_Compiler 扩展**（R9）：`ExprX`/`Pattern`/`peephole_opt`/`tco_opt`/`TypeMismatch`，见「Mini-compiler 特性与优化设计」。
- **Lsp_Server 扩展**（R10）：`encode_frame`/`decode_frame`/`validate_jsonrpc`/`apply_incremental`，见「LSP 协议鲁棒性设计」。
- **Pbt_Framework 扩展**（R11）：`Shrinkable`/`one_of`/`frequency`/`sized`/`check_with_shrink`/`Stats`，见「PBT 框架增强设计」。

## Data Models

> 数据模型

核心数据模型（新增类型）按方向归类，定义见各方向小节的代码块：

- **文本构建**：`TextBuilder`。
- **日志**：`SinkTarget`、`SinkHandle`。
- **构建**：`Action`、`ActionResult`、`ParallelSchedule`、`BuildLog`。
- **序列化**：`RpcDef`、`ServiceDef`、`ImportDecl`、`ProtoFile`、`CodeNode`、`AnyValue`、`ByteSink`、`ByteSource`（复用既有 `ProtoSchema`/`TypedMessage`/`DecodeError`）。
- **正则**：`GeneralCategory`、`HybridMatcher`（复用既有 `CharSet`/`Nfa`/`LazyDfa`/`Match`/`Pattern`）。
- **解析器**：`RecoveryStrategy`、`BoundedCache`（复用既有 `Grammar`/`Step`/`Input`/`ParseResult`）。
- **代码生成 IR**：`Operand`、`TypedInstr`、`TypedBlock`、`TypedFunction`、`IrError`、`IrEvalResult`。
- **仿真**：`SimContext`、`TaskResult`、`ExecutableTask`、`EventuallyResult`（复用既有 `World`/`Protocol`/`Invariant`/`DesResult`）。
- **迷你编译器**：`Pattern`、`ExprX`、`TypeMismatch`（复用既有 `Expr`/`Bytecode`/`Instr`/`Ty`/`Val`）。
- **LSP**：`FrameError`、`JsonRpcError`（复用既有 `ContentChange`/`PositionEncoding`）。
- **PBT**：`Shrinkable[T]`、`CheckResult[T]`、`Stats`（复用既有 `Gen`/`Rng`）。

## Correctness Properties

> 正确性属性

每条属性对应一个 ≥100 迭代、三后端一致的属性测试。

### Property 1: R1 文本构建等价与线性
`TextBuilder.build()` 与等价顺序 `+` 拼接逐字符相等；`build` 后再追加仍按序包含全部片段。
**Validates: Requirements 1.2, 1.3, 1.4**

### Property 2: R2 Sink 派发语义
CallbackSink 对通过级别的记录恰好调用一次；BufferedSink 阈值前不下发、阈值或 flush 后按到达顺序全部下发；级别低于生效级别的记录不交付任何下游。
**Validates: Requirements 2.2, 2.3, 2.4, 2.6**

### Property 3: R3 调度完备性
ParallelSchedule 任一波次内两两 Action 无依赖路径；全波次展开为全部 Action 各一次；指纹相同则标记 up-to-date。
**Validates: Requirements 3.4, 3.6, 3.7**

### Property 4: R4 序列化往返一致
`parse_proto_file(print_proto_file(f))` 与 `f` 等价；`decode_any(encode_any(a))==a`；`decode_from(encode_to(m))==m`。
**Validates: Requirements 4.4, 4.6**

### Property 5: R5 正则一致性
`is_match` 与 `find` 是否产出匹配一致；`contains_binary` 与线性 `contains` 一致；`HybridMatcher.find` 与 `Nfa.find` 一致；`find_at(s,k)` 仅返回 `start>=k` 的匹配。
**Validates: Requirements 5.2, 5.3, 5.4, 5.6, 5.7**

### Property 6: R6 增量解析等价
任意分块方式的增量解析结果 == 一次性解析；有界 packrat 结果与无淘汰一致且条目数 ≤ cap。
**Validates: Requirements 6.2, 6.4, 6.5**

### Property 7: R7 IR 正确性
合法 SSA 验证通过；重复定义→SsaViolation；类型不符→TypeMismatch；控制流缺失→ControlFlowError；解释器对通过验证的 IR 求值结果确定。
**Validates: Requirements 7.2, 7.3, 7.4, 7.5, 7.6**

### Property 8: R8 可复现与不变量
相同种子+相同任务集逐事件可复现；invariant 违例报告状态；eventually 未成立报告。
**Validates: Requirements 8.3, 8.5, 8.6**

### Property 9: R9 优化等价与 TCO
peephole/TCO 优化前后求值结果相等；深度 N 尾递归帧数不随 N 线性增长；类型错误同含 expected 与 actual。
**Validates: Requirements 9.2, 9.3, 9.4, 9.5**

### Property 10: R10 成帧与增量同步
`decode_frame(encode_frame(b))` 还原 b；增量同步结果与全量替换一致；`\r\n`/`\n` 头兼容；非法 JSON-RPC 结构返回错误对象。
**Validates: Requirements 10.2, 10.3, 10.4, 10.5, 10.6**

### Property 11: R11 收缩与分布
shrink 产物仍使属性失败；`frequency` 大样本占比趋近配置权重；统计计数与样本分类一致。
**Validates: Requirements 11.1, 11.2, 11.4, 11.5**

## Error Handling

> 错误处理

- **解析类错误**（R4 `ParseError`、R10 `FrameError`/`JsonRpcError`、R7 `IrError`）：返回含位置/原因的结构化错误值，不 panic、不 abort。
- **编解码类错误**（R4 `DecodeError`）：复用既有错误枚举，越界/畸形输入返回带 offset 的错误。
- **校验类错误**（R7 `validate_ir`、R8 invariant/eventually）：以 `Result`/报告值返回，附带定位信息（reg/block/step/state）。
- **恢复类**（R6 `with_recovery`）：子解析失败时按策略同步并产出占位结果，使整体解析得以继续而非中断。
- 全程禁止 `abort()`/`todo!()`/`panic` 作为占位（遵循 anti-patterns 约束）。

---

## Testing Strategy

## Shared_Text_Builder 设计（Requirement 1）

### 包与类型

新建包 `src/infra_text`，`moon.pkg` 不依赖任何方向包。核心类型：

```
pub struct TextBuilder {
  mut chunks : Array[String]   // 已追加片段，物化时一次性 join
  mut char_buf : Array[Char]   // 字符级追加缓冲，延迟合并到 chunks
  mut total_len : Int          // 已追加字符总数（O(1) 维护）
}
```

设计动机：MoonBit 中 `String + String` 每次分配新串，循环内累积为 O(n²)。`TextBuilder` 以 `Array[String]` 收集片段、最终 `String::concat`（join）一次物化，得到摊还 O(1) 追加、O(n) 物化。字符级追加先进入 `char_buf`，在 `push_str` 或 `build` 时把 `char_buf` 折叠为一个 `String` 片段，避免每字符一次数组装箱开销。

### 公开 API（全部新增）

```
pub fn TextBuilder::new() -> TextBuilder
pub fn TextBuilder::with_capacity(Int) -> TextBuilder   // 预留 chunks 容量
pub fn TextBuilder::push_char(Self, Char) -> Unit       // 追加单字符
pub fn TextBuilder::push_str(Self, String) -> Unit      // 追加字符串
pub fn TextBuilder::len(Self) -> Int                    // 当前总字符数
pub fn TextBuilder::is_empty(Self) -> Bool
pub fn TextBuilder::build(Self) -> String               // 物化为最终字符串（不清空，可继续追加）
pub fn TextBuilder::reset(Self) -> Unit                 // 清空缓冲复用
```

### 关键不变量

- **AC1/AC3**：`build()` 结果与等价顺序 `+` 拼接逐字符相等。实现上 `build` 先 flush `char_buf` 到 `chunks`，再 `chunks.join("")`。
- **AC2 线性**：`push_char`/`push_str` 均摊 O(1)（仅 push 到数组并累加 `total_len`），`build` 为 O(总长度)。
- **AC4 再追加保持**：`build` **不**清空内部状态；flush 后 `char_buf` 已并入 `chunks`，后续 `push_*` 继续累积，下次 `build` 含全部历史片段且顺序保持。

### 替换策略（AC5/AC6）

对 `serialization`/`build-tool`/`logging`/`regex-engine`/`parser-combinator` 中**循环内**的 `out = out + ...` 点，逐个改为 `TextBuilder`。每个被改造函数：保留原公开签名不变，仅替换内部实现；新增「等价性属性测试」断言改造后输出 == 改造前快照（或与等价 join 实现逐字符相等）。**非循环单次拼接**（≤3 次顺序 `+`）按 AC6 保留，不强制替换。

---

## Logging Sink 层设计（Requirement 2）

现状：`Sink` 仅含内存 `mut buffer : Array[String]`，`dispatch` 写入 buffer；有 `set_threshold`/`current_threshold`。加固以新增 sink 抽象与运行时调级，**不改 `Sink` 既有结构**。

### 新增类型（`logging/sink_layer.mbt`）

```
pub enum SinkTarget {
  TConsole                              // println 到 stdout
  TCallback((Event) -> Unit)            // 交给回调
  TBuffered(threshold~ : Int, down~ : SinkHandle)  // 缓冲到阈值再下发
}

pub struct SinkHandle {
  target : SinkTarget
  formatter : Formatter
  mut buffer : Array[Event]   // 仅 TBuffered 使用
  mut level : Level           // 运行时可调级（每 sink 独立）
}

pub fn SinkHandle::console(Formatter, level? : Level) -> SinkHandle
pub fn SinkHandle::callback((Event) -> Unit, level? : Level) -> SinkHandle
pub fn SinkHandle::buffered(Int, SinkHandle, level? : Level) -> SinkHandle
pub fn SinkHandle::set_level(Self, Level) -> Unit
pub fn SinkHandle::emit(Self, Event) -> Unit   // 按级别过滤后派发
pub fn SinkHandle::flush(Self) -> Unit         // 强制下发缓冲
```

### 行为映射

- **AC1 ConsoleSink**：`emit` 中若 `event.level.rank() >= self.level.rank()`，则 `format_event(formatter, event)` 后 `println` 到 stdout。
- **AC2 CallbackSink**：级别通过时，对回调恰好调用一次（计数断言）。
- **AC3/AC4 BufferedSink**：未达 `threshold` 时仅 `buffer.push`；达到阈值或 `flush` 时按到达顺序对 `down` 逐条 `emit` 并清空 `buffer`。
- **AC5 set_level**：调用后，级别低于新生效级别的记录在 `emit` 中被丢弃。
- **AC6**：级别低于生效级别的记录不交付任何下游（包括不进入 BufferedSink 的 buffer）。

注：stdout 副作用难以在 PBT 中断言，故对 Console 用 `CallbackSink` 等价建模做属性测试（往返/计数），Console 仅做 demo 与 snapshot 验证。

---

## Build Executor 框架设计（Requirement 3）

现状：有 `BuildGraph`/`schedule`（返回 `Array[Array[Target]]` 波次）/`BuildCache`/`action_fingerprint`/`ActionCache`。加固新增执行框架，复用既有 `schedule` 与指纹。

### 新增类型（`build_tool/executor.mbt`）

```
pub struct Action {
  id : String
  inputs : Array[String]
  outputs : Array[String]
  command : String
} derive(Eq, Show)
pub fn Action::fingerprint(Self) -> String   // 复用 content_hash/cache_key

pub enum ActionResult {
  Executed(output_hash~ : String)
  Skipped                       // up-to-date
} derive(Eq, Show)

pub trait Executor {
  execute(Self, Action) -> ActionResult
}

pub struct DryRunExecutor { mut log : Array[Action] }
pub struct CallbackExecutor { cb : (Action) -> String }   // 返回 output_hash

pub struct ParallelSchedule { waves : Array[Array[Action]] }
pub fn build_parallel_schedule(Array[Action], Array[(String, String)]) -> ParallelSchedule

pub struct BuildLog { entries : Map[String, (String, ActionResult)] }  // id -> (fp, result)
pub fn BuildLog::new() -> Self
pub fn BuildLog::record(Self, Action, ActionResult) -> Unit
pub fn BuildLog::is_up_to_date(Self, Action) -> Bool

pub fn run_actions(ParallelSchedule, &Executor, BuildLog) -> BuildLog
```

### 行为映射

- **AC1**：`Action` 声明 inputs/outputs/command。
- **AC2 DryRun**：`execute` 仅 `log.push(action)`，返回 `Skipped` 或记录态，无外部副作用。
- **AC3 Callback**：`execute` 调用 `cb(action)` 并采用其返回结果。
- **AC4/AC7 ParallelSchedule**：基于依赖边做 Kahn 分层；同一波次内任意两 Action 无依赖路径（属性测试：对每个波次内 pair 验证图上无路径）；全部波次展开 == 全部 Action 各一次（多重集合相等）。
- **AC5 BuildLog**：记录每个 Action 的 `fingerprint` 与 `ActionResult`。
- **AC6 增量**：`is_up_to_date` 比对当前指纹与 BuildLog 记录指纹，相同则标记可跳过。

---

## Serialization 增强设计（Requirement 4）

现状：`parse_proto_full` → `ProtoSchema`（message/enum/oneof/map/reserved），`gen_moonbit_full` 用字符串拼接生成；`encode_typed`/`decode_typed`。加固分三块。

### 4.1 proto3 service/rpc/import（`proto_service.mbt`）

```
pub struct RpcDef { name : String; input_type : String; output_type : String;
                    client_stream : Bool; server_stream : Bool } derive(Eq, Show)
pub struct ServiceDef { name : String; rpcs : Array[RpcDef] } derive(Eq, Show)
pub struct ImportDecl { path : String; public : Bool } derive(Eq, Show)
pub struct ProtoFile {
  package_name : String
  imports : Array[ImportDecl]
  schema : ProtoSchema       // 复用既有
  services : Array[ServiceDef]
} derive(Eq, Show)

pub fn parse_proto_file(String) -> Result[ProtoFile, ParseError]
pub fn print_proto_file(ProtoFile) -> String   // 经 CodeNode 渲染
```

- **AC1**：解析含 `service`/`rpc`/`import`/`package` 的源文本为 `ProtoFile`。
- **AC4 往返**：`parse_proto_file(print_proto_file(f))` 与 `f` 等价模型（属性测试，生成随机合法 `ProtoFile`）。
- **AC7**：非法语法返回含 `ParseError`（line/col/offset/message）的描述性错误。

### 4.2 结构化代码生成 AST（`codegen_ast.mbt`）

```
pub enum CodeNode {
  CRaw(String)
  CLine(String)
  CBlock(header~ : String, body~ : Array[CodeNode], close~ : String)
  CSeq(Array[CodeNode])
  CIndent(CodeNode)
} derive(Eq, Show)

pub fn render_code(CodeNode, indent_unit? : String) -> String   // 用 TextBuilder 物化
pub fn gen_moonbit_ast(ProtoSchema) -> CodeNode                 // 构造结构化节点
pub fn gen_moonbit_structured(ProtoSchema) -> String           // = render_code(gen_moonbit_ast(...))
```

- **AC3**：通过 `CodeNode` + `render_code`（内部 `TextBuilder`）物化，替代直接字符串拼接。新增 `gen_moonbit_structured` 为 bypass，不动既有 `gen_moonbit_full`。

### 4.3 Any 类型与流式编解码（`streaming.mbt`）

```
pub struct AnyValue { type_url : String; value : Bytes } derive(Eq, Show)
pub fn encode_any(AnyValue) -> Bytes
pub fn decode_any(Bytes) -> Result[AnyValue, DecodeError]

pub struct ByteSink { mut buf : Array[Byte] }
pub struct ByteSource { data : Bytes; mut pos : Int }
pub fn encode_to(ByteSink, ProtoSchema, String, TypedMessage) -> Result[Unit, DecodeError]
pub fn decode_from(ByteSource, ProtoSchema, String) -> Result[TypedMessage, DecodeError]
```

- **AC2 Any**：`encode_any`/`decode_any` 往返一致。
- **AC5/AC6 流式**：`decode_from(encode_to(m))` == m（编解码往返属性测试，复用 `encode_typed`/`decode_typed` 语义，包一层流式接口）。

---

## Regex 引擎增强设计（Requirement 5）

现状：`CharSet`（intervals 数组，已有 `contains`）、`Nfa`/`Dfa`/`LazyDfa`、`Pattern`（已有 `is_match`/`find`/`split`/`replace_all`）。

### 5.1 Unicode General Category（`unicode_gc.mbt`）

```
pub enum GeneralCategory { Lu; Ll; Lt; Lm; Lo; Nd; Nl; No; Pc; Pd; Ps; /* ... */ Zs; Cc } derive(Eq, Show)
pub fn unicode_category(Int) -> GeneralCategory          // 码点 → 类别（区间表查表）
pub fn category_charset(GeneralCategory) -> CharSet      // 类别 → CharSet（区间）
pub fn parse_unicode_class(String) -> CharSet?           // \p{L} 等
```

- **AC1**：字符类匹配支持按 GC。以区间表（`Array[(lo, hi, GeneralCategory)]`）实现，覆盖核心类别（拉丁/数字/标点/空白/控制）。区间表为命名常量，不硬编码散落数字。

### 5.2 CharSet 二分查询（`api_ext.mbt`）

```
pub fn CharSet::contains_binary(Self, Int) -> Bool   // 在已排序 intervals 上二分
```

- **AC6**：`contains_binary` 结果与线性 `contains` 一致（等价属性测试）。

### 5.3 Hybrid 匹配（`hybrid.mbt`）

```
pub struct HybridMatcher { nfa : Nfa; lazy : LazyDfa; cache_cap : Int }
pub fn HybridMatcher::new(Nfa, cap~ : Int) -> Self
pub fn HybridMatcher::find(Self, String) -> Match?
```

- **AC3/AC4**：LazyDfa 缓存达 `cache_cap` 上限时按 LRU/清空淘汰；缓存压力下切换到 NFA/Pike VM 路径，结果与 DFA 一致（等价属性测试：HybridMatcher.find == Nfa.find）。

### 5.4 实用 API（`api_ext.mbt`）

```
pub fn Pattern::find_at(Self, String, Int) -> Match?
pub fn Pattern::split_n(Self, String, Int) -> Array[String]
pub fn Pattern::replace_fn(Self, String, (Match) -> String) -> String   // 用 TextBuilder 物化
```

- **AC5/AC7**：`find_at(s, k)` 仅返回 `start >= k` 的匹配或无匹配；`split_n` 限定份数；`replace_fn` 以回调计算替换文本。

---

## Parser Combinator 增强设计（Requirement 6）

现状：`Grammar::run_incremental` 返回 `Step`，`drive` 驱动分块输入；有 `recover`/`memoize`/`run_packrat`。

### 新增（`incremental_ext.mbt`、`bounded_packrat.mbt`）

```
pub enum RecoveryStrategy {
  SkipUntil(Char)          // 跳到指定标记
  SyncTo(Array[Char])      // 同步到任一标记
} derive(Eq, Show)
pub fn[T] with_recovery(Grammar[T], RecoveryStrategy, T) -> Grammar[T]

pub struct BoundedCache { cap : Int; mut entries : Map[Int, ...]; mut order : Array[Int] }
pub fn[T] Grammar::run_packrat_bounded(Self[T], Input, cap~ : Int) -> ParseResult[T]
```

- **AC1/AC2 增量**：复用 `run_incremental`/`drive`；属性测试断言「任意分块方式」结果 == 一次性解析（`run_naive_string`）。生成随机输入 + 随机切分点。
- **AC3 withRecovery**：子解析失败时按策略同步到标记并产出占位结果继续。
- **AC4/AC5 有界缓存**：条目达 `cap` 时 LRU 淘汰；结果与无淘汰 `run_packrat` 相等；内存条目数 ≤ cap。

---

## Codegen-infra 类型化 IR 设计（Requirement 7）

现状：`BasicBlock { instrs : Array[String] }`、`TargetInstr { op : String }` —— **字符串化**，是核心反模式。加固新增**平行的类型化 IR**，不动既有字符串 IR（bypass）。

### 新增（`typed_ir.mbt`）

```
pub enum Operand {
  Reg(Int)      // 虚拟寄存器
  Imm(Int)      // 立即数
  Mem(Int)      // 内存槽
} derive(Eq, Show)

pub enum TypedInstr {
  Add(dst~ : Int, lhs~ : Operand, rhs~ : Operand)
  Sub(dst~ : Int, lhs~ : Operand, rhs~ : Operand)
  Mul(dst~ : Int, lhs~ : Operand, rhs~ : Operand)
  Load(dst~ : Int, addr~ : Operand)
  Store(addr~ : Operand, value~ : Operand)
  Call(dst~ : Int, callee~ : String, args~ : Array[Operand])
  Ret(value~ : Operand?)
  Br(target~ : String)
  CondBr(cond~ : Operand, then_~ : String, else_~ : String)
  Phi(dst~ : Int, args~ : Array[(String, Operand)])
} derive(Eq, Show)

pub struct TypedBlock { label : String; instrs : Array[TypedInstr]; terminator : TypedInstr? } derive(Eq, Show)
pub struct TypedFunction { entry : String; blocks : Array[TypedBlock] } derive(Eq, Show)
```

### IR 验证器（`ir_validator.mbt`）

```
pub enum IrError {
  SsaViolation(reg~ : Int)
  TypeMismatch(instr~ : String, detail~ : String)
  ControlFlowError(block~ : String, detail~ : String)
} derive(Eq, Show)
pub fn validate_ir(TypedFunction) -> Result[Unit, Array[IrError]]
```

- **AC2**：合法 SSA → 验证通过。
- **AC3**：某 reg 被定义 > 1 次 → `SsaViolation`。
- **AC4**：操作数类型不符（如 `Store` 地址用 `Imm` 写入非法）→ `TypeMismatch`。
- **AC5**：块缺终结指令或跳到不存在块 → `ControlFlowError`。

### IR 解释器（`ir_interp.mbt`）

```
pub struct IrEvalResult { regs : Map[Int, Int]; returned : Int? } derive(Eq, Show)
pub fn interp_ir(TypedFunction, args~ : Map[Int, Int]) -> IrEvalResult
```

- **AC6**：对通过验证的 IR 按语义求值，产出确定结果。

---

## DST 可执行任务设计（Requirement 8）

现状：`Task { id, name }` 占位；有 `World`/`Protocol`/`Invariant`/`EventQueue`/`SimClock`（`World.clock`）；`run_des` 可复现。

### 新增（`task_body.mbt`、`eventually.mbt`）

```
pub struct SimContext {
  node_id : Int
  clock : UInt64
  mut sends : Array[(Int, Int, UInt64)]   // (to, payload, after)
  mut appends : Array[Int]
}
pub enum TaskResult { TDone; TYield; TFailed(reason~ : String) } derive(Eq, Show)
pub struct ExecutableTask { id : Int; name : String; body : (SimContext) -> TaskResult }
pub fn ExecutableTask::new(Int, String, (SimContext) -> TaskResult) -> Self

pub fn run_executable(UInt64, Array[ExecutableTask], Protocol, Array[Invariant], max_steps~ : Int) -> DesResult

pub enum EventuallyResult { EHolds(step~ : Int); ENeverHeld } derive(Eq, Show)
pub fn eventually(DesResult, (World) -> Bool) -> EventuallyResult
```

- **AC1**：`TaskBody` 签名 `(SimContext) -> TaskResult`，取代占位任务。
- **AC2**：复用既有 `NetworkSim`（`NetFaultKind`：Delay/Drop/Reorder/Partition）。
- **AC3**：相同种子 + 相同任务集 → 逐事件相同 trace（确定性属性测试）。
- **AC4**：`SimClock` 仅按事件推进（复用 `World.clock`/`order_seq`）。
- **AC5 invariant**：复用既有 `eval_invariants`；违例报告状态。
- **AC6 eventually**：终止时仍未成立 → `ENeverHeld`。

---

## Mini-compiler 特性与优化设计（Requirement 9）

现状：`Expr` 已有 `ETuple`；`Instr` 已有 `MkTuple`；HM 推断 + 字节码 VM。缺 match/list/peephole/TCO/类型错误细节。

### 新增（`match_ext.mbt`、`peephole.mbt`、`tco.mbt`）

```
// 新增表达式与模式（在新 enum 中 bypass，提供到既有 Expr 的桥接编译）
pub enum Pattern {
  PWild
  PVar(String)
  PInt(Int)
  PBool(Bool)
  PTuple(Array[Pattern])
  PCons(Pattern, Pattern)   // 列表 head::tail
  PNil
} derive(Eq, Show)
pub enum ExprX {
  XBase(Expr)
  XMatch(ExprX, Array[(Pattern, ExprX)], Span)
  XList(Array[ExprX], Span)
}
pub fn check_x(ExprX) -> Result[Ty, TypeMismatch]
pub fn eval_x(ExprX) -> Val

pub struct TypeMismatch { expected : Ty; actual : Ty; span : Span } derive(Eq, Show)

pub fn peephole_opt(Bytecode) -> Bytecode
pub fn tco_opt(Bytecode) -> Bytecode
```

- **AC1**：`match`/元组/列表的解析、类型检查、求值。
- **AC2 peephole**：消除相邻冗余（如 `Push;Pop`、`Jump 到下一条`），指令数不增加。
- **AC3 TCO**：尾位置 call 复用帧；深度 N 尾递归帧数不随 N 线性增长（计数属性测试）。
- **AC4**：优化前后求值结果相等（等价属性测试）。
- **AC5**：类型不匹配报告同含 expected 与 actual 的 `TypeMismatch`。

---

## LSP 协议鲁棒性设计（Requirement 10）

现状：`apply_changes`/`VersionedDocument::apply`（增量同步，PositionEncoding），`LspSession`（生命周期），经 `lsp_binding` 的 JSON-RPC。

### 新增（`jsonrpc_frame.mbt`、`incremental_sync.mbt`）

```
pub enum FrameError {
  MissingContentLength
  InvalidContentLength(raw~ : String)
  IncompleteBody(need~ : Int, got~ : Int)
} derive(Eq, Show)
pub fn encode_frame(String) -> String                       // 加 Content-Length 头
pub fn decode_frame(String) -> Result[(String, String), FrameError]   // (body, rest)

pub enum JsonRpcError { ParseErr; InvalidRequest; MethodNotFound; InvalidParams; InternalErr } derive(Eq, Show)
pub fn validate_jsonrpc(@lsp_binding.Json) -> Result[Unit, JsonRpcError]

pub fn apply_incremental(String, ContentChange, PositionEncoding) -> Result[String, @lsp_binding.RpcError]
```

- **AC1**：完整 JSON-RPC 2.0 请求/响应/通知/错误语义校验。
- **AC2**：`Content-Length` 帧头兼容 `\r\n` 与 `\n` 换行。
- **AC3 成帧往返**：`decode_frame(encode_frame(body))` 还原 body（属性测试）。
- **AC4**：基于范围的增量变更仅改受影响范围，结果与全量替换一致（等价属性测试，对照既有 `apply_changes`）。
- **AC5**：单次增量变更对长度 N 次平方级（优于 O(n²)）—— 用 `Array[Char]` 切片拼接，O(N)。
- **AC6**：非法 JSON-RPC 结构返回相应错误对象。

---

## PBT 框架增强设计（Requirement 11）

现状：`Gen`/`Rng`/`holds_for_all`/`round_trip`。缺 shrink/组合子/统计。

### 新增（`shrink.mbt`、`combinators.mbt`、`stats.mbt`）

```
pub struct Shrinkable[T] { value : T; shrinks : () -> Array[T] }
pub fn shrink_int(Int) -> Array[Int]          // 向 0 收缩：减半 + 邻近
pub fn[T] shrink_array(Array[T], (T) -> Array[T]) -> Array[Array[T]]   // 去元素 + 元素收缩

pub fn[T] one_of(Array[Gen[T]]) -> Gen[T]                    // 等概率
pub fn[T] frequency(Array[(Int, Gen[T])]) -> Gen[T]          // 按权重
pub fn[T] sized((Int) -> Gen[T]) -> Gen[T]                   // 按规模

pub struct CheckResult[T] { passed : Bool; counterexample : T? }
pub fn[T] check_with_shrink(Gen[T], (T) -> Bool, (T) -> Array[T], iters? : Int) -> CheckResult[T]

pub struct Stats { mut counts : Map[String, Int] }
pub fn[T] holds_for_all_stats(Gen[T], (T) -> Bool, (T) -> String, iters? : Int) -> (Bool, Stats)
```

- **AC1/AC2**：失败时迭代收缩到最小仍失败反例；收缩产物仍使属性失败。
- **AC3**：`one_of`/`frequency`/`sized` 组合子。
- **AC4**：`frequency` 大样本下各分支占比趋近配置权重（统计属性测试，容差判定）。
- **AC5**：统计收集报告各分类计数/占比。

---

## 横切质量门禁（Requirement 12）

- **AC1/AC2 API 冻结**：所有新增以新类型/函数/方法实现；每次 `moon info` 后 diff `.mbti`，确认既有条目不变、仅新增。
- **AC3 既有测试不改**：严禁修改既有 `_test.mbt`；新代码若致既有测试失败，修新代码。
- **AC4 三后端**：所有新增属性测试在 `wasm-gc`/`js`/`native` 跑通。
- **AC5 ≥100 迭代**：所有 `holds_for_all`/`check_with_shrink` 的 `iters >= 100`。
- **AC6 校验**：每方向加固后 `moon info && moon fmt && moon test`。

---

## Testing Strategy

> 测试策略

### 属性测试（PBT，≥100 迭代，三后端）

每个新增公开函数至少一个属性测试，覆盖：往返一致性、代数律、新旧等价、边界条件。关键属性清单：

- **R1**：`build()` == 等价顺序拼接；线性时间（构造大输入不超时）；再追加保持顺序。
- **R2**：CallbackSink 恰好一次调用；BufferedSink 阈值前不下发、阈值/flush 后按序全发；低于级别不下发。
- **R3**：波次内无依赖路径；全波次展开 == 全 Action 各一次；指纹相同则 up-to-date。
- **R4**：proto 文件 print→parse 往返；`encode_any`/`decode_any` 往返；`decode_from(encode_to(m))==m`。
- **R5**：`is_match` 与 `find` 一致；`contains_binary` 与线性一致；Hybrid 与 NFA 一致；`find_at(k)` 起点约束。
- **R6**：任意分块 == 一次性解析；有界缓存与无淘汰一致；缓存条目 ≤ cap。
- **R7**：合法 SSA 通过；重复定义→SsaViolation；类型不符→TypeMismatch；控制流缺失→ControlFlowError；解释器结果确定。
- **R8**：相同种子逐事件可复现；invariant 违例报告；eventually 未成立报告。
- **R9**：优化前后求值相等；TCO 帧数不线性增长；类型错误含 expected/actual。
- **R10**：成帧往返；增量同步 == 全量替换；`\r\n`/`\n` 兼容；非法结构返回错误对象。
- **R11**：shrink 反例仍失败；frequency 占比趋近权重；统计计数正确。

### 等价性快照

对每个被 `TextBuilder` 改造的函数，新增黑盒测试断言其在代表性输入上的输出与改造前一致（必要时用 `moon test --update` 固化快照后冻结）。

### 后端矩阵

```
moon test --target wasm-gc
moon test --target js
moon test --target native
```

每完成一个方向，跑 `moon info && moon fmt && moon test`，并按方向做一次 git commit。

---

## 设计决策与权衡

> Design Decisions

1. **新建 `infra_text` 而非塞进 `core`/`infra_pbt`**：保持职责单一与叶子依赖，避免污染既有包接口与引入循环依赖。
2. **codegen-infra 采用平行类型化 IR 而非改造字符串 IR**：满足「只增不减」与 anti-patterns「禁止字符串模拟结构化数据」，旧字符串 IR 冻结保留，新类型化 IR 承载生产级能力。
3. **Console sink 副作用以 Callback 等价建模做 PBT**：stdout 不可在纯属性测试中断言，用 CallbackSink 验证派发逻辑，Console 仅 demo/snapshot。
4. **trait `Executor` + 具体实现**：以接口抽象执行，DryRun/Callback 覆盖测试与真实委派两类场景，不引入真实进程执行（仓库无 shell 执行能力，符合确定性测试）。
5. **有界缓存统一 LRU**：packrat 与 LazyDfa 缓存均用 LRU，行为可预测、便于等价测试。
