# 实施计划（Implementation Plan）：Serialization_Framework 旗舰深化

## 概述（Overview）

本计划把 `design.md` 的双流水线增量架构落地为一系列**聚焦编码**的增量任务。总原则与设计契约一致：**既有公开类型与函数（`types.mbt`/`wire.mbt`/`proto_parser.mbt`/`codegen.mbt`/`release.mbt`）严格冻结、枚举不扩容、新能力全部以旁路扩展（新增 `.mbt` 文件、新增类型/函数/方法）提供**。实现语言为 **MoonBit**（沿用既有 `src/serialization/` 子包，设计已给出 MoonBit 签名级接口，无需选择语言）。

任务顺序遵循依赖：富模式模型/zigzag 基础层 → 完整文法解析/模式校验 → 类型化编解码 → 确定性编码/JSON/代码生成 → 端到端 demo/基准/文档/发布。每条 PBT 属性（Property 1~11）各自独立为一个可选 `*` 子任务，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`，每条至少运行 **100 次迭代**。

> 工程约定：涉及 native 后端的测试、基准与可执行文档校验，运行前必须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。所有新增源码位于 `src/serialization/`，基准位于 `benches/serialization_bench/`。

## 任务（Tasks）

- [x] 1. 富模式模型与基础位级辅助（基础层）
  - [x] 1.1 实现富模式模型 `src/serialization/schema_model.mbt`
    - 新增 `ProtoType`（区分 sint/fixed/sfixed/float/double 等完整 proto3 类型）、`FieldLabel`（`LSingular`/`LRepeated(packed~)`/`LOneof(group~)`）、`FieldOption`、`ProtoField`、`ReservedRange`、`MapEntry`、`OneofDef`、`ProtoMessage`、`ProtoSchema`，全部 `derive(Eq, Show)`
    - 实现 `ProtoSchema::empty`、`ProtoSchema::message(name)` 限定名查找，以及 `ProtoSchema::to_legacy` 向下投影桥（投影到既有冻结 `Schema`，与既有 `parse_proto` 在共同子集上的产物一致）
    - 严格旁路扩展：不修改既有 `types.mbt` 的任何 `pub`/`pub(all)` 声明
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 10.1, 10.3_

  - [x] 1.2 实现 zigzag 与定长位级辅助 `src/serialization/zigzag.mbt`
    - 实现 `zigzag_encode_32`/`zigzag_decode_32`/`zigzag_encode_64`/`zigzag_decode_64`（算术右移实现符号位扩散）
    - 实现 `double_to_bits`/`bits_to_double`/`float_to_bits`/`bits_to_float`（IEEE-754 位级 reinterpret，供 `I32`/`I64` 浮点编解码，规避 js 后端 float 精度漂移）
    - _Requirements: 1.2, 1.4_

  - [x]* 1.3 为 zigzag 编写属性测试 `src/serialization/prop_zigzag_test.mbt`
    - **Property 3: zigzag 双射（zigzag bijection）**
    - 以 `@infra_pbt` 对随机 32/64 位有符号整数断言 `zigzag_decode_*(zigzag_encode_*(n)) == n`，≥100 次迭代
    - **Validates: Requirements 1.2**

  - [x]* 1.4 为既有 wire 往返编写属性测试 `src/serialization/prop_legacy_roundtrip_test.mbt`
    - **Property 1: 既有 wire 往返（legacy wire round-trip）**
    - 以 `@infra_pbt` 生成字段记录序列消息 `m`，断言 `decode(encode(m), Schema::empty()) == Ok(m)`，≥100 次迭代；验证既有冻结 API 行为不变
    - **Validates: Requirements 10.2, 10.6**

- [x] 2. 检查点 —— 确保基础层全部测试通过
  - 在三后端运行测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保所有测试通过，遇问题询问用户。

- [x] 3. 完整 proto3 文法解析与模式校验
  - [x] 3.1 实现完整 proto3 文法解析 `src/serialization/proto_grammar.mbt`
    - 在 `@parser_combinator` 的 `Input`/`Pos`/`ParseResult` 之上实现 `parse_proto_full(src) -> Result[ProtoSchema, ParseError]`，覆盖 `message`/`enum`/全部标量类型/`oneof`/`map<K,V>`/嵌套类型（以限定名登记）/`reserved`/字段选项 `[packed=true]`/`[deprecated=true]`
    - 实现规范打印 `print_proto(schema) -> String`（字段号升序、固定缩进、规范关键字），用于解析 round-trip
    - 语法错误返回携带行列的 `ParseError`（复用既有 `ParseError::at`）且不构造 `ProtoSchema`；既有 `parse_proto` 保持冻结
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

  - [x]* 3.2 编写文法解析单元测试 `src/serialization/proto_grammar_test.mbt`
    - 覆盖 oneof/map/嵌套 message-enum/reserved/字段选项的具体样例，以及语法错误的行列定位
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x]* 3.3 为模式解析 round-trip 编写属性测试 `src/serialization/prop_parse_roundtrip_test.mbt`
    - **Property 11: proto 模式解析 round-trip（schema parse round-trip）**
    - 生成合法富模式 `s`，断言 `parse_proto_full(print_proto(s)) == Ok(s)`，≥100 次迭代
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

  - [x] 3.4 实现模式校验 `src/serialization/schema_validate.mbt`
    - 新增 `SchemaError`（`FieldNumberOutOfRange`/`DuplicateFieldNumber`/`ReservedConflict`/`UnresolvedTypeRef`/`EnumFirstValueNonZero`，携带定位）
    - 实现 `validate_schema(schema) -> Result[Unit, Array[SchemaError]]`：字段号 ∈ `[1, 536870911]` 且 ∉ `[19000, 19999]`、同消息字段号唯一、不触 `reserved`、`PMessage`/`PEnum` 引用按限定名可解析、proto3 枚举首值为 0；可一次性报告多条诊断
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x]* 3.5 编写模式校验单元测试 `src/serialization/schema_validate_test.mbt`
    - 覆盖重复字段号/命中 reserved/未解析引用/枚举首值非 0/字段号越界各错误场景与正向通过
    - _Requirements: 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x]* 3.6 为合法模式校验通过编写属性测试 `src/serialization/prop_validate_test.mbt`
    - **Property 7: 合法模式校验通过（valid-schema acceptance）**
    - 生成合法富模式，断言 `validate_schema` 返回成功且无任何诊断，≥100 次迭代
    - **Validates: Requirements 4.1, 4.6, 4.7**

- [x] 4. 检查点 —— 确保文法解析与模式校验全部测试通过
  - 在三后端运行测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保所有测试通过，遇问题询问用户。

- [x] 5. 模式驱动的类型化编解码
  - [x] 5.1 实现类型化取值模型与编解码 `src/serialization/typed.mbt`
    - 新增 `TypedValue`（`TInt`/`TUInt`/`TBoolV`/`TEnumV`/`TFloatV`/`TDoubleV`/`TStringV`/`TBytesV`/`TMsg`/`TList`/`TMap`）与 `TypedMessage`（`fields : Map[Int, TypedValue]` + `unknown : Array[FieldEntry]`）
    - 实现 `TypedMessage::new`/`set`/`get`/`get_or_default`（未设置标量按 schema 返回类型默认值）
    - 实现 `encode_typed`/`decode_typed`：字段号↔命名字段映射、sint zigzag、bool/enum、定长 float/double/fixed 位级解释、string/bytes、嵌套消息递归、repeated 聚合、packed 拆包、proto3 默认值省略、未知字段保留；复用既有 `encode`/`decode` 的 varint/定长/长度前缀读写
    - wire 类型与声明类型不符映射到既有 `InvalidWireType`（不扩容枚举），且失败时不产生部分构造消息
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.1, 11.3_

  - [x]* 5.2 编写类型化编解码单元测试 `src/serialization/typed_test.mbt`
    - 覆盖默认值标量不写入字节、未设置字段读取取默认值、嵌套消息递归、map/oneof 的 wire 等价编码
    - _Requirements: 1.7, 1.8, 3.3_

  - [x]* 5.3 为类型化往返编写属性测试 `src/serialization/prop_typed_roundtrip_test.mbt`
    - **Property 2: 类型化往返（typed round-trip）**
    - 生成（富模式, 类型化消息）对，断言 `decode_typed(encode_typed(m))` 内容与 `m` 相等，≥100 次迭代
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9**

  - [x]* 5.4 为 packed 与非 packed 等价编写属性测试 `src/serialization/prop_packed_test.mbt`
    - **Property 6: packed 与非 packed 等价（packed equivalence）**
    - 生成数值标量序列，断言 packed 编码与同字段号多次出现的非 packed 编码经解码得相同元素序列，≥100 次迭代
    - **Validates: Requirements 2.5, 2.8**

  - [x]* 5.5 为解码错误位置编写属性测试 `src/serialization/prop_decode_error_test.mbt`
    - **Property 10: 解码错误位置与无部分产物（decode-error offset）**
    - 生成非法字节序列，断言 `decode`/`decode_typed` 返回携带偏移（∈ `[0, 输入长度]`）的 `DecodeError` 且为 `Err` 而非 `Ok(部分消息)`，≥100 次迭代
    - **Validates: Requirements 11.3**

- [x] 6. 检查点 —— 确保类型化编解码全部测试通过
  - 在三后端运行测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保所有测试通过，遇问题询问用户。

- [x] 7. 确定性编码、JSON 映射与完整代码生成
  - [x] 7.1 实现确定性/规范化编码 `src/serialization/canonical.mbt`
    - 实现 `encode_canonical`（字段号升序、数值标量 repeated 一律 packed、每字段至多一次、未知字段按原始字段号并入同一升序序列写回）
    - 实现 `canonicalize_wire(msg : Message) -> Bytes`（不依赖 schema 的 wire 级稳定升序重排重编）
    - _Requirements: 2.2, 2.3, 2.4, 2.5_

  - [x]* 7.2 为规范编码幂等编写属性测试 `src/serialization/prop_canonical_test.mbt`
    - **Property 4: 规范编码幂等（canonical-encoding idempotence）**
    - 生成（富模式, 类型化消息）对，断言 `encode_canonical(decode_typed(encode_canonical(m)))` 与 `encode_canonical(m)` 逐字节相等，≥100 次迭代
    - **Validates: Requirements 2.3, 2.4, 2.6**

  - [x]* 7.3 为未知字段保留编写属性测试 `src/serialization/prop_unknown_test.mbt`
    - **Property 5: 未知字段保留（unknown-field preservation）**
    - 生成含未知字段消息，断言类型化解码再编码后未知字段的字段号与原始取值集合不变，≥100 次迭代
    - **Validates: Requirements 2.1, 2.2, 2.7**

  - [x] 7.4 实现 proto3 JSON 映射 `src/serialization/json.mbt`
    - 实现 `encode_json`/`decode_json` 与 `base64_encode`/`base64_decode`；字段名 snake_case↔camelCase、64 位整数表示为字符串、`bytes` 用 base64、取默认值标量省略
    - JSON 解析复用 `@parser_combinator` 位置模型；结构非法或类型不符返回携带定位的 `ParseError` 且不产生部分构造消息
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x]* 7.5 编写 JSON 映射单元测试 `src/serialization/json_test.mbt`
    - 覆盖 camelCase 字段名、64 位整数为字符串、bytes base64、非法 JSON 的错误定位
    - _Requirements: 5.1, 5.4_

  - [x]* 7.6 为 JSON↔二进制等价编写属性测试 `src/serialization/prop_json_test.mbt`
    - **Property 8: JSON↔二进制等价（JSON/binary equivalence）**
    - 生成（富模式, 类型化消息）对，断言经二进制往返与经 JSON 往返所得消息内容彼此相等，≥100 次迭代
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.5**

  - [x] 7.7 实现完整代码生成 `src/serialization/codegen_full.mbt`
    - 实现 `gen_moonbit_full(schema)`：每消息一个带全部字段及映射后 MoonBit 类型的 `pub struct`，repeated → `Array[元素类型]`，每结构体配套 `encode`/`decode` 方法且方法体委托共享 `encode_typed`/`decode_typed`
    - 既有 `gen_moonbit` 保持冻结
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x]* 7.8 编写代码生成单元测试 `src/serialization/codegen_full_test.mbt`
    - 断言生成文本含 `pub struct`/字段/`Array`/`encode`/`decode` 方法，并对固定 demo 生成模块做编译冒烟
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x]* 7.9 为生成代码往返编写属性测试 `src/serialization/prop_codegen_test.mbt`
    - **Property 9: 生成代码往返（generated-code round-trip）**
    - 生成合法富模式与该模式下消息，断言所委托的共享类型化模型满足 `decode ∘ encode == 恒等`，≥100 次迭代
    - **Validates: Requirements 6.3, 6.5**

- [x] 8. 检查点 —— 确保确定性编码/JSON/代码生成全部测试通过
  - 在三后端运行测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；确保所有测试通过，遇问题询问用户。

- [x] 9. 端到端 demo、性能基准、可执行文档与发布推进
  - [x] 9.1 实现端到端实战 demo `src/serialization/demo.mbt`
    - 实现 `demo_proto() -> String`（贯穿文档与基准的实战 `.proto`，覆盖标量/repeated/嵌套消息/enum/oneof/map 六类构造）与 `demo_message() -> TypedMessage`（匹配样例消息）
    - _Requirements: 9.1_

  - [x]* 9.2 编写 demo 端到端单元测试 `src/serialization/demo_test.mbt`
    - 串联 `parse_proto_full` → `validate_schema` → `gen_moonbit_full` → `encode_typed` → `decode_typed` → JSON 往返，断言二进制往返与 JSON 往返所得消息内容相等
    - _Requirements: 9.2, 9.3_

  - [x] 9.3 新增性能基准包 `benches/serialization_bench/`
    - 新增 `serialization_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`（结构对齐既有 `benches/astar_bench`），覆盖 varint 密集/大 repeated（packed 与非 packed 对比）/嵌套深度/字符串密集四类负载，对 `encode_typed`/`decode_typed`/`encode_canonical`/JSON 计时
    - 输出含机器标识、后端目标、输入规模与计时统计的 JSON/Markdown 工件到 `benches/results/`；文档记录运行命令并要求 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 7.1, 7.2, 7.4_

  - [x] 9.4 接入基准回归基线 guard（写入 `benches/serialization_bench/` 同一包）
    - 将新基准运行与已记入基线中位数比较，超声明容差时给出可审计的失败报告（复用既有 guard 模式）
    - _Requirements: 7.3_

  - [x] 9.5 扩充可执行文档 `src/serialization/README.mbt.md`
    - 覆盖类型化编解码/确定性编码/JSON 映射/模式校验/代码生成/端到端 demo；补充 paper-to-code 追溯（wire/varint、zigzag、proto3 JSON）、与 Protocol Buffers/Cap'n Proto/FlatBuffers/MessagePack 的对标、实现边界声明（不支持 group/extensions/import 跨文件等）
    - 记录 native 运行前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`，确保全部示例通过 `moon test *.mbt.md`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 9.4, 11.4, 11.5_

  - [x] 9.6 推进 SemVer 版本与更新 CHANGELOG
    - 更新 `src/serialization/release.mbt` 的 `serialization_version` 字符串（自 `0.1.0` 做次/主版本推进），保持 `release_info`/`release_info_with_gates` 语义不变
    - 扩充 `src/serialization/CHANGELOG.md` 记录本次旗舰深化
    - _Requirements: 10.5, 11.6_

- [x] 10. 最终检查点 —— 三后端 + 可执行文档 + 门禁全绿
  - 在 `wasm-gc`/`js`/`native` 三后端运行同一测试套件（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`），任一后端分歧判失败；运行 `moon test *.mbt.md` 校验可执行文档；确认 `release_info_with_gates` 在门禁全绿时方可标记 release-ready。确保所有测试通过，遇问题询问用户。

## 备注（Notes）

- 标记 `*` 的子任务为可选（单元测试、属性测试），可为更快 MVP 跳过；顶层任务不带 `*`。
- 每条 PBT 属性（Property 1~11）各自独立成一个 `*` 子任务，复用 `@infra_pbt`，每条 ≥100 次迭代，并以 `**Validates: Requirements X.Y**` 链接验收标准。
- 严格向后兼容：`types.mbt`/`wire.mbt`/`proto_parser.mbt`/`codegen.mbt` 全程冻结，`release.mbt` 仅推进版本字符串；枚举不扩容，类型不符复用既有 `InvalidWireType`。
- 所有新增能力以新增 `.mbt` 文件旁路扩展；每个测试位于独立文件以便并行调度且不冲突。
- 涉及 native 后端的测试、基准与文档校验，运行前必须 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
- 检查点用于增量验证，确保前序成果在三后端一致后再推进下一阶段。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.4"] },
    { "id": 1, "tasks": ["1.3", "3.1", "3.4", "5.1"] },
    { "id": 2, "tasks": ["3.2", "3.3", "3.5", "3.6", "5.2", "5.3", "5.4", "5.5", "7.1", "7.4", "7.7", "9.1"] },
    { "id": 3, "tasks": ["7.2", "7.3", "7.5", "7.6", "7.8", "7.9", "9.2", "9.3"] },
    { "id": 4, "tasks": ["9.4", "9.5", "9.6"] }
  ]
}
```
