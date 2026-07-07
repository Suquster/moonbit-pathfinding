# Changelog —— Serialization（方向九）

本文件记录 **Serialization**（序列化框架）方向（子包 `src/serialization`）
作为**独立发布单元**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`）。

---

## [Unreleased]

### Added
- **schema 演进 / 版本兼容检查器（C3，2026-07-07）**：`schema_evolution.mbt`
  旁路新增——wire 级破坏性变更静态判定（对标 protobuf 官方 Updating A
  Message Type 规则与 Buf breaking 检查）：varint / zigzag / I32 / I64 / Len
  兼容组、删除字段必须 reserve 号与名、reserved 复用、singular↔repeated、
  oneof 归属变化、消息删除；输出结构化 `BreakingChange` 列表（空即兼容），
  可作 CI 门禁。`check_message_evolution` / `check_schema_evolution` 纯函数、
  无 panic。测试 `schema_evolution_test.mbt`。

## [0.2.0] - 2026-06-12

旗舰深化（🟣 档位 3「业界顶尖」）：在冻结的 `0.1.0` 骨架之上做**严格向后兼容**的
增量深化，对标 Protocol Buffers / Cap'n Proto / FlatBuffers / MessagePack。全部新
能力以**旁路新增** API 提供，既有 `WireType`/`FieldValue`/`FieldType`/`DecodeError`
枚举不扩容，`encode`/`decode`/`parse_proto`/`gen_moonbit` 公开签名与行为不变。

### Added
- 富模式模型（`schema_model.mbt`）：`ProtoType`（区分 sint/fixed/sfixed/float/
  double）、`FieldLabel`、`FieldOption`、`ProtoField`、`ReservedRange`、`MapEntry`、
  `OneofDef`、`ProtoMessage`、`ProtoSchema`，及 `ProtoSchema::to_legacy` 向下投影桥。
- zigzag 与定长位级辅助（`zigzag.mbt`）：`zigzag_encode/decode_32/64`、
  `double_to_bits`/`bits_to_double`/`float_to_bits`/`bits_to_float`（位级 reinterpret，
  规避 js 后端浮点漂移，三后端位级一致）。
- 完整 proto3 文法解析（`proto_grammar.mbt`）：`parse_proto_full` 覆盖
  message/enum/全部标量/oneof/map<K,V>/嵌套类型（限定名登记）/reserved/字段选项；
  配套规范打印 `print_proto` 支撑解析 round-trip。
- 模式驱动的类型化编解码（`typed.mbt`）：`TypedValue`/`TypedMessage` 与
  `encode_typed`/`decode_typed`（sint zigzag、bool/enum、定长 float/double/fixed
  位级、string/bytes、嵌套递归、repeated 聚合、packed 拆包、proto3 默认值省略、
  未设置字段语义、未知字段保留）。
- 确定性/规范化编码（`canonical.mbt`）：`encode_canonical`（字段号升序 + packed +
  每字段一次 + 未知字段并入）与 wire 级 `canonicalize_wire`，编码幂等。
- 模式校验（`schema_validate.mbt`）：`SchemaError` 与 `validate_schema`（字段号范围/
  唯一/保留冲突/类型引用解析/proto3 枚举首值 0），一次性多诊断。
- proto3 JSON 映射（`json.mbt`）：`encode_json`/`decode_json` 与 `base64_encode`/
  `base64_decode`（camelCase、64 位整数为字符串、bytes base64、默认值省略）。
- 完整代码生成（`codegen_full.mbt`）：`gen_moonbit_full` 产出带字段 `pub struct` +
  委托共享类型化模型的编解码函数。
- 端到端实战 demo（`demo.mbt`）：`demo_proto`/`demo_message`（UserProfile，覆盖
  标量/repeated/嵌套/enum/oneof/map 六类构造）。
- 性能基准（`benches/serialization_bench`）：varint 密集 / 大 repeated（packed 对比）/
  嵌套深度 / 字符串密集四类负载 + 往返/紧凑度/字节基线回归 guard。
- 属性测试：11 条正确性属性（既有 wire 往返、类型化往返、zigzag 双射、规范编码
  幂等、未知字段保留、packed 等价、合法模式校验、JSON↔二进制等价、生成代码往返、
  解码错误位置、模式解析 round-trip），每条 ≥100 迭代，三后端一致。
- 可执行文档：`README.mbt.md` 扩充覆盖六大新能力 + paper-to-code 追溯 + 开源对标 +
  实现边界声明。

### Changed
- release: `serialization_version` 自 `0.1.0` 推进至 `0.2.0`（次版本，向后兼容）。

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ protobuf wire format 编解码 + `.proto` 解析 + 代码生成 + 往返/错误
属性测试 + 可执行文档」的方向骨架基线。

### Added
- 核心类型：`Message`、`Schema`（消息 / 字段 / 枚举的模式描述）、
  `DecodeError`（含出错字节偏移）、`ParseError`（含行列位置）等数据模型
  （新增序列化核心类型与模式描述）。
- wire format 编解码：`encode`（内存对象 → protobuf wire format 字节序列）
  与 `decode`（字节 + 模式 → 消息对象）；解码失败返回**含出错字节偏移**的
  错误且不产生部分构造对象（新增 protobuf wire format 编解码）。
- `.proto` 解析：`parse_proto` 构建于 `@parser_combinator`，将 `.proto`
  文件解析为消息 / 字段 / 枚举模式描述，语法错误返回含行列位置的解析错误
  （新增 `.proto` 解析器）。
- 代码生成：`gen_moonbit` 由合法 `.proto` 模式产出对应的 MoonBit 消息类型
  定义与编解码代码（新增模式驱动的代码生成）。
- 属性测试：编码 ↔ 解码往返性质与非法字节错误条件性质，跨三后端一致
  （新增往返 / 错误属性测试）。
- 可执行文档：覆盖编码再解码往返用法的 `*.mbt.md` 端到端样例
  （新增序列化可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/serialization/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/serialization-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/serialization-v0.1.0...serialization-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/serialization-v0.1.0
