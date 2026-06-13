# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 `serialization 0.1.0` 骨架之上，做**增量式、严格向后兼容**的旗舰级（🟣 档位 3）深化，目标对标 Protocol Buffers、Cap'n Proto、FlatBuffers 与 MessagePack。核心原则一句话：**既有公开类型与函数（`WireType`/`FieldValue`/`FieldEntry`/`Message`/`FieldType`/`FieldDef`/`MessageDef`/`EnumDef`/`Schema`/`DecodeError`/`ParseError` 与 `encode`/`decode`/`parse_proto`/`gen_moonbit`）的签名、字段、变体与运行时语义一律冻结，所有新能力以旁路扩展（新增类型、新增 `.mbt` 文件、新增函数/方法）的方式提供，绝不改写既有 wire 粒度通用编解码与既有 `.proto` 解析结果。**

既有两条流水线保持不变：

```
message → wire → bytes → message      （encode / decode，wire 粒度通用编解码）
.proto → Schema → 代码                 （parse_proto / gen_moonbit，骨架级）
```

旗舰深化在其旁侧新增一条**模式驱动的类型化流水线**与一条**JSON 互转旁路**，二者通过「向下投影」桥接既有骨架以支撑差分一致性验证：

```
                         ┌──────────── 富模式模型（旁路新增）────────────┐
.proto ─ parse_proto_full ─▶ ProtoSchema ─ validate_schema ─▶ ✔/SchemaError
  │                              │  │
  │ parse_proto（冻结，骨架）       │  └─ ProtoSchema::to_legacy ─▶ Schema（既有）
  ▼                              ▼
Schema（既有，骨架）          gen_moonbit_full ─▶ MoonBit 源码（struct + encode/decode 方法）

TypedMessage ─ encode_typed ──▶ bytes ─ decode_typed ──▶ TypedMessage      （类型化往返）
     │            └ encode_canonical ─▶ 规范字节（升序 + packed，幂等）        （确定性编码）
     │
     └ encode_json ──▶ proto3 JSON 文本 ─ decode_json ──▶ TypedMessage       （JSON↔二进制等价）

Message ─ encode（既有）──▶ bytes ─ decode（既有，Schema::empty()）──▶ Message  （既有 wire 往返，冻结）
```

旗舰能力分八条主线落地：① 模式驱动的类型化编解码；② wire 完整性与确定性编码；③ 完整 proto3 文法解析；④ 模式校验；⑤ proto3 JSON 映射；⑥ 完整代码生成；⑦ 性能基准；⑧ 端到端 demo。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、三后端一致性策略、错误处理与正确性属性。

---

## 架构（Architecture）

### 设计原则与向后兼容契约

1. **冻结即契约**：`types.mbt`/`wire.mbt`/`proto_parser.mbt`/`codegen.mbt`/`release.mbt` 中现有的 `pub`/`pub(all)` 声明，其签名、字段、变体与运行时行为一律不改。`pkg.generated.mbti` 现有条目保持稳定，新增条目仅追加。
2. **枚举不扩容**：`WireType`/`FieldValue`/`FieldType`/`DecodeError` 均为 `pub(all) enum`，新增变体会改变其形态、破坏既有穷尽匹配的调用方，故**一律不新增变体**。富类型信息（sint/zigzag、float/double、fixed、map、oneof）通过**新增的旁路类型**承载，而非改写既有枚举（此为刻意取舍，见「设计权衡」）。
3. **既有解析/编解码语义不变**：`encode`/`decode` 继续做 wire 粒度通用编解码（不依赖 schema 类型信息）；`parse_proto` 继续产出骨架级 `Schema`（顶层 message/enum + 简单字段）；`gen_moonbit` 继续产出结构体骨架。类型化、确定性、JSON、校验、完整文法、完整代码生成全部以新入口提供。
4. **既有错误模型复用**：类型化解码遇到的 wire 类型与声明类型不符等错误，**映射到既有 `DecodeError` 变体**（主要是 `InvalidWireType`，以 `tag` 负载携带定位），不新增变体；JSON 解析错误复用既有 `ParseError`（已含 `line`/`col`/`offset`/`message`）。**模式校验错误**则是全新语义，单列新类型 `SchemaError`（可自由携带定位）。
5. **infra 复用**：全部新增属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`（每条属性 ≥100 迭代）；`.proto` 解析继续构建于 `@parser_combinator` 的 `Input`/`Pos`/`ParseResult`；发布元数据复用 `@release_meta`，`release_info`/`release_info_with_gates` 语义不变。

### 模块 / 文件划分

下表为 `src/serialization/` 下的文件规划。**既有文件**保持冻结（仅可追加新方法所需的 import）；**新增文件**承载旗舰能力。

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `types.mbt` | 冻结 | 既有 wire/模式/错误模型 | R10.1 |
| `wire.mbt` | 冻结 | 既有 `encode`/`decode`（wire 粒度通用编解码） | R10.2/R10.6 |
| `proto_parser.mbt` | 冻结 | 既有 `parse_proto`（骨架级 .proto 解析） | R10.2 |
| `codegen.mbt` | 冻结 | 既有 `gen_moonbit`（结构体骨架） | R10.2 |
| `release.mbt` | 冻结/版本字符串更新 | 发布元数据登记（仅推进 SemVer 字符串） | R10.5/R11.6 |
| `schema_model.mbt` | 新增 | 富模式模型 `ProtoSchema`/`ProtoMessage`/`ProtoField`/`ProtoType`/`OneofDef`/`MapEntry`/`ReservedRange`/`FieldOption`，及 `ProtoSchema::to_legacy` 向下投影桥 | R3/R1/R6 |
| `proto_grammar.mbt` | 新增 | 完整 proto3 文法解析 `parse_proto_full` + 规范打印 `print_proto`，构建于 `@parser_combinator` | R3 |
| `zigzag.mbt` | 新增 | zigzag 32/64 编解码与定长位级 reinterpret 辅助 | R1.2/R1.4 |
| `typed.mbt` | 新增 | 类型化取值模型 `TypedValue`/`TypedMessage` 与 `encode_typed`/`decode_typed`（含默认值省略、未设置语义、repeated/packed、嵌套递归） | R1 |
| `canonical.mbt` | 新增 | 确定性/规范化编码 `encode_canonical`、wire 级排序 `canonicalize_wire`、未知字段保留与重编 | R2 |
| `schema_validate.mbt` | 新增 | `SchemaError` 与 `validate_schema`（字段号范围/唯一/保留/类型引用/枚举首值 0） | R4 |
| `json.mbt` | 新增 | proto3 JSON 映射 `encode_json`/`decode_json` + base64 编解码 | R5 |
| `codegen_full.mbt` | 新增 | 完整代码生成 `gen_moonbit_full`（带字段结构体 + 配套编解码方法） | R6 |
| `demo.mbt` | 新增 | 端到端实战 `.proto` 与样例消息 | R9 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖新能力 | R9.4/R11.4 |
| `CHANGELOG.md` | 扩充 | SemVer 推进记录 | R11.6 |
| `prop_*_test.mbt` | 新增/既有 | 属性测试（见「测试策略」「正确性属性」） | R11.2 |

`benches/` 下新增基准包 `benches/serialization_bench/`（`serialization_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`），结构对齐既有 `benches/astar_bench` 等，产出 `benches/results/` 工件并接入 guard（R7）。

### 依赖方向

```
schema_model ─┐
              ├─▶ typed ─▶ canonical
proto_grammar ┤            json
zigzag ───────┘            codegen_full
schema_validate ◀─ schema_model
（全部向下依赖既有 types/wire；解析依赖 @parser_combinator；测试依赖 @infra_pbt）
```

无反向依赖：既有冻结文件不感知任何新增文件；新增文件单向依赖既有模型与既有 `encode`/`decode`/读写 varint 等底层能力。

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt`/`.mbti` 风格（`pub(all)` 暴露可构造数据，`pub` 暴露只读结构与函数）。

### 4.1 富模式模型 `ProtoSchema`（R3/R1/R6）

既有 `FieldType` 不区分 sint（zigzag）、float/double、fixed/sfixed，也无 oneof/map/嵌套/reserved，故新增**富模式模型**承载完整 proto3 类型信息（既有 `Schema`/`FieldType` 冻结不动）。

```moonbit
// schema_model.mbt

/// 完整 proto3 字段类型（含 wire 编码语义区分）。
pub enum ProtoType {
  PInt32; PInt64; PUInt32; PUInt64        // 普通 varint
  PSInt32; PSInt64                        // zigzag varint
  PFixed32; PFixed64                      // 定长无符号
  PSFixed32; PSFixed64                    // 定长有符号
  PFloat; PDouble                         // 定长浮点（I32 / I64）
  PBool
  PString; PBytes
  PMessage(String)                        // 引用消息（限定名）
  PEnum(String)                           // 引用枚举（限定名）
} derive(Eq, Show)

/// 字段标签：proto3 默认（singular）、repeated、或属于某 oneof。
pub enum FieldLabel {
  LSingular
  LRepeated(packed~ : Bool)               // packed 默认对数值标量为 true
  LOneof(group~ : String)
} derive(Eq, Show)

pub(all) struct FieldOption {
  name : String
  value : String                          // 原样保留（如 "true"），不解释语义
} derive(Eq, Show)

pub(all) struct ProtoField {
  name : String
  number : Int
  ptype : ProtoType
  label : FieldLabel
  options : Array[FieldOption]
} derive(Eq, Show)

pub(all) struct ReservedRange {
  lo : Int                                // 含
  hi : Int                                // 含（单个号时 lo==hi）
} derive(Eq, Show)

pub(all) struct MapEntry {
  name : String
  number : Int
  key : ProtoType                         // 仅允许整型/bool/string
  value : ProtoType
} derive(Eq, Show)

pub(all) struct OneofDef {
  name : String
  members : Array[Int]                    // 成员字段号（互斥组）
} derive(Eq, Show)

pub(all) struct ProtoMessage {
  name : String                           // 限定名（嵌套以 '.' 连接）
  fields : Array[ProtoField]
  maps : Array[MapEntry]
  oneofs : Array[OneofDef]
  reserved_numbers : Array[ReservedRange]
  reserved_names : Array[String]
  nested_messages : Array[String]         // 嵌套消息限定名（登记于顶层 messages）
  nested_enums : Array[String]
} derive(Eq, Show)

pub(all) struct ProtoSchema {
  messages : Array[ProtoMessage]          // 含嵌套，按限定名唯一登记（R3.4）
  enums : Array[EnumDef]                   // 复用既有 EnumDef
} derive(Eq, Show)

pub fn ProtoSchema::empty() -> ProtoSchema

/// 向下投影到既有骨架 Schema（用于桥接既有 API 与差分验证）。
/// 投影规则：sint*/sfixed* → 既有 TInt*；fixed* → 既有 T(U)Int*；
/// float/double → 既有最接近的标量占位；map/oneof 展平为对应字段集合。
/// 该投影**与既有 parse_proto 在共同子集上的产物一致**，从而既有调用方无感。
pub fn ProtoSchema::to_legacy(self : ProtoSchema) -> Schema

/// 按限定名查找消息定义。
pub fn ProtoSchema::message(self : ProtoSchema, name : String) -> ProtoMessage?
```

设计要点：`ProtoType` 显式区分 sint 与普通 int、float/double 与 fixed，使类型化层能据此选择 zigzag、定长位级解释（既有 `FieldType` 做不到，这正是新增富模型的根因）。`map<K,V>` 单列 `MapEntry`（wire 上等价于 `repeated` 的 `{key=1, value=2}` 条目消息，R3.3）；`oneof` 以 `OneofDef.members` 记录互斥成员号（R3.2）；嵌套类型登记到顶层 `messages`/`enums` 并以限定名引用（R3.4）。

### 4.2 完整 proto3 文法解析 `parse_proto_full`（R3）

既有 `parse_proto` 冻结。新增 `parse_proto_full` 在 `@parser_combinator` 之上扩展为覆盖完整 proto3 文法，并提供规范打印 `print_proto` 以支撑解析 round-trip（解析器易错，强制 round-trip 验证）。

```moonbit
// proto_grammar.mbt
pub fn parse_proto_full(src : String) -> Result[ProtoSchema, ParseError]
pub fn print_proto(schema : ProtoSchema) -> String     // 规范化打印（供 round-trip 与调试）
```

文法（EBNF 概要，构建于 `@parser_combinator` 的 `Input`/`Pos`/`satisfy`/`many1`/`alt`/`seq`）：

```
proto      := (syntax | package | import | option | topdef)*
topdef     := message | enum
message    := 'message' ident '{' member* '}'
member     := field | mapfield | oneof | message | enum | reserved | option | ';'
field      := label? type ident '=' number fieldopts? ';'
label      := 'repeated' | 'optional' | 'singular'
mapfield   := 'map' '<' type ',' type '>' ident '=' number fieldopts? ';'
oneof      := 'oneof' ident '{' (type ident '=' number fieldopts? ';')* '}'
reserved   := 'reserved' ( ranges | strings ) ';'
fieldopts  := '[' option (',' option)* ']'
enum       := 'enum' ident '{' (option | ident '=' number fieldopts? ';')* '}'
type       := 'int32'|'sint32'|'sfixed32'|'fixed32'|'int64'|'sint64'|'sfixed64'
            | 'fixed64'|'uint32'|'uint64'|'float'|'double'|'bool'|'string'|'bytes'| ident
```

解析期职责：① 完整标量关键字精确映射为 `ProtoType`（区分 sint/fixed/sfixed/float/double，R3.1）；② `oneof` 块成员登记为互斥组并保留各成员号/类型（R3.2）；③ `map<K,V>` 建模为 `MapEntry`（R3.3）；④ 嵌套 `message`/`enum` 递归解析并以限定名（`Outer.Inner`）登记到顶层（R3.4）；⑤ `reserved` 记录号区间与名（R3.5）；⑥ 字段选项 `[packed=true]`/`[deprecated=true]` 解析进 `FieldOption` 而非报错，`packed` 选项回写到 `LRepeated.packed`（R3.6）；⑦ 任何语法错误返回携带 `Pos`（行列+偏移）的 `ParseError` 且**不构造 `ProtoSchema`**（R3.7，复用既有 `ParseError::at`）。

`print_proto` 以**确定性规范形态**输出（字段按号升序、固定缩进、标量类型用规范关键字），使 `parse_proto_full(print_proto(s))` 与 `s` 等价（解析 round-trip，见正确性属性 11）。

### 4.3 zigzag 与定长位级辅助（R1.2/R1.4）

```moonbit
// zigzag.mbt
pub fn zigzag_encode_32(n : Int) -> UInt        // (n << 1) ^ (n >> 31)
pub fn zigzag_decode_32(u : UInt) -> Int        // (u >> 1) ^ -(u & 1)
pub fn zigzag_encode_64(n : Int64) -> UInt64    // (n << 1) ^ (n >> 63)
pub fn zigzag_decode_64(u : UInt64) -> Int64    // (u >> 1) ^ -(u & 1)

// 定长位级 reinterpret（IEEE-754，跨后端位级一致；MoonBit 标准库内建语义）
pub fn double_to_bits(d : Double) -> UInt64
pub fn bits_to_double(u : UInt64) -> Double
pub fn float_to_bits(f : Float) -> UInt
pub fn bits_to_float(u : UInt) -> Float
```

zigzag 把有符号整数映射为无符号，使小幅负值得到短 varint（`-1→1`、`1→2`，避免负数恒占 10 字节）。算术右移（`>> 31` / `>> 63`）实现符号位扩散。位级 reinterpret 直接映射 IEEE-754 比特，配合既有 `write_fixed`/`read_fixed` 完成 `I32`/`I64` 浮点编码——**位级而非数值层往返**，规避 js 后端"全是 double"导致的 float 精度漂移（见「三后端一致性」）。

### 4.4 类型化取值模型与编解码 `TypedValue` / `encode_typed` / `decode_typed`（R1）

```moonbit
// typed.mbt

/// 经 Schema 解释后的字段取值（模式驱动编解码的目标表示）。
pub enum TypedValue {
  TInt(Int64)              // int32/int64/sint32/sint64/sfixed*/fixed*（小整型以 Int64 承载）
  TUInt(UInt64)            // uint32/uint64/fixed32/fixed64
  TBoolV(Bool)
  TEnumV(Int)              // 枚举序数
  TFloatV(Float)
  TDoubleV(Double)
  TStringV(String)
  TBytesV(Bytes)
  TMsg(TypedMessage)       // 嵌套消息（递归）
  TList(Array[TypedValue]) // repeated（含 packed）
  TMap(Array[(TypedValue, TypedValue)])  // map<K,V>
} derive(Eq, Show)

/// 类型化消息：命名字段取值 + 保留的未知字段。
pub(all) struct TypedMessage {
  // 仅记录"已显式设置"的字段（取默认值的标量被省略；读取时按 schema 补默认）
  fields : Map[Int, TypedValue]          // 字段号 → 取值
  unknown : Array[FieldEntry]            // 未知字段（号/wire/原始取值）原样保留
} derive(Eq, Show)

pub fn TypedMessage::new() -> TypedMessage
pub fn TypedMessage::set(self : TypedMessage, number : Int, v : TypedValue) -> TypedMessage
pub fn TypedMessage::get(self : TypedMessage, number : Int) -> TypedValue?
/// 按 schema 读取：未设置标量返回其类型默认值（R1.8）。
pub fn TypedMessage::get_or_default(
  self : TypedMessage, msg : ProtoMessage, number : Int
) -> TypedValue

/// 模式驱动的类型化编码（R1.1–1.7）。取默认值的标量省略（R1.7）。
pub fn encode_typed(
  schema : ProtoSchema, msg_name : String, msg : TypedMessage
) -> Result[Bytes, DecodeError]

/// 模式驱动的类型化解码（R1.1–1.6, 1.8；未知字段保留 R2.1）。
pub fn decode_typed(
  schema : ProtoSchema, msg_name : String, bytes : Bytes
) -> Result[TypedMessage, DecodeError]
```

编解码算法（建立在既有 wire 通用扫描之上，**复用 `decode` 的 varint/定长/长度前缀读取与 `encode` 的写出**）：

- **编码**：遍历消息定义字段；对已设置字段按 `ProtoType` 选择 wire 编码：
  - `PSInt*` → 先 `zigzag_encode_*` 再写 varint；`PInt*`/`PUInt*`/`PBool`/`PEnum` → 直接 varint；
  - `PFloat`/`PFixed32`/`PSFixed32` → `I32` 定长（float 先 `float_to_bits`）；`PDouble`/`PFixed64`/`PSFixed64` → `I64`（double 先 `double_to_bits`）；
  - `PString`/`PBytes`/`PMessage` → `Len`（嵌套消息递归 `encode_typed` 得载荷）；
  - `LRepeated(packed=true)` 的数值标量 → 全部元素打包进单个 `Len` 载荷（R2.4）；非 packed 或 string/message repeated → 每元素一条记录；
  - `map<K,V>` → 每键值对编码为 `{1:key, 2:value}` 的嵌套消息条目（R3.3 wire 等价）；
  - **默认值省略**：标量等于其类型默认值（0/0.0/false/""/空 bytes/枚举 0）时不写入（R1.7）；
  - 末尾追加 `unknown` 中保留的未知字段记录（R2.2）。
- **解码**：先以既有 wire 扫描得字段记录序列，再按 schema 把字段号映射为命名字段（R1.1），按声明 `ProtoType` 反向解释（zigzag/bool/enum/定长位级/字符串/字节/递归嵌套，R1.2–1.5）；同号字段聚合为 `TList`（R1.6）；packed `Len` 载荷拆为元素序列；schema 中无定义的字段进入 `unknown`（R2.1）。wire 类型与声明类型不符时返回 `InvalidWireType`（复用既有变体），且**不产生部分构造的消息**（沿用 `decode` 的"先收集后构造"契约，R11.3）。

### 4.5 确定性/规范化编码与未知字段保留（R2）

```moonbit
// canonical.mbt
/// 类型化消息的确定性编码：字段号升序、数值标量 repeated 用 packed、
/// 每字段至多一次、未知字段按号并入升序序列（R2.3/2.4/2.2）。
pub fn encode_canonical(
  schema : ProtoSchema, msg_name : String, msg : TypedMessage
) -> Result[Bytes, DecodeError]

/// wire 级规范化：对任意 Message 的字段记录按字段号升序稳定重排后重编，
/// 不依赖 schema（供未知字段排序与既有 Message 的确定性比对）。
pub fn canonicalize_wire(msg : Message) -> Bytes
```

确定性规则（对标 protobuf deterministic serialization）：① 字段号升序输出（R2.3）；② 数值标量 repeated 一律 packed（R2.4）；③ 每字段至多一条记录；④ 未知字段以其原始字段号参与同一升序排序后写回（R2.2）。由此对同一消息内容产出唯一字节序列，从而**幂等**：`encode_canonical(decode_typed(encode_canonical(m)))` 与首次结果逐字节相等（R2.6）。`packed` 与「同号多次出现的非 packed」解码得相同元素序列（R2.5/2.8）。

### 4.6 模式校验 `SchemaError` / `validate_schema`（R4）

```moonbit
// schema_validate.mbt
pub enum SchemaError {
  FieldNumberOutOfRange(message~ : String, field~ : String, number~ : Int)
  DuplicateFieldNumber(message~ : String, number~ : Int)
  ReservedConflict(message~ : String, which~ : String)       // 号或名命中 reserved
  UnresolvedTypeRef(message~ : String, field~ : String, ref_~ : String)
  EnumFirstValueNonZero(enum_~ : String, first~ : Int)
} derive(Eq, Show)

/// 全量校验：通过返回 Ok(())；否则返回全部诊断（含定位）。
pub fn validate_schema(schema : ProtoSchema) -> Result[Unit, Array[SchemaError]]
```

校验项：① 每字段号 ∈ `[1, 536870911]` 且 ∉ `[19000, 19999]`（R4.1）；② 同消息内字段号唯一（R4.2）；③ 字段号/名不得命中本消息 `reserved`（R4.3）；④ `PMessage`/`PEnum` 引用须在 `schema` 中可解析（按限定名，R4.4）；⑤ proto3 枚举首值须为 0（R4.5）；⑥ 全通过返回成功且无诊断（R4.6）。对所有由生成器产出的**合法**模式，校验恒返回成功（R4.7，正确性属性 7）。

### 4.7 proto3 JSON 映射 `encode_json` / `decode_json`（R5）

```moonbit
// json.mbt
pub fn encode_json(
  schema : ProtoSchema, msg_name : String, msg : TypedMessage
) -> Result[String, DecodeError]
pub fn decode_json(
  schema : ProtoSchema, msg_name : String, json : String
) -> Result[TypedMessage, ParseError]

pub fn base64_encode(data : Bytes) -> String
pub fn base64_decode(text : String) -> Bytes?
```

映射规则（proto3 JSON 规范）：① 字段名 snake_case → camelCase（R5.1）；② `int64`/`uint64`/`sint64`/`fixed64`/`sfixed64` 表示为 JSON **字符串**（避免 IEEE-754 53 位精度损失，R5.1）；③ `bytes` 表示为 base64 文本（R5.1）；④ `bool`/`int32`/`float`/`double`/`string` 用原生 JSON 类型；⑤ 枚举默认以名输出（无名则数值）；⑥ 取默认值的标量字段默认省略（R5.3）；⑦ 解码按 `schema` 把各 JSON 字段还原为类型化取值（R5.2）；⑧ JSON 结构非法或类型不符返回含 `Pos` 的 `ParseError` 且**不产生部分构造消息**（R5.4）。JSON 解析复用 `@parser_combinator` 的位置模型以获得行列定位。由此**经二进制往返与经 JSON 往返所得消息内容相等**（R5.5，正确性属性 8）。

### 4.8 完整代码生成 `gen_moonbit_full`（R6）

既有 `gen_moonbit(Schema)` 冻结（结构体骨架）。新增 `gen_moonbit_full(ProtoSchema)` 产出带字段结构体 + 配套编解码方法。

```moonbit
// codegen_full.mbt
pub fn gen_moonbit_full(schema : ProtoSchema) -> String
```

生成内容：① 每消息一个带全部字段及映射后 MoonBit 类型的 `pub struct`（`PSInt*/PInt*`→`Int`/`Int64`，`PUInt*/PFixed*`→`UInt`/`UInt64`，`PFloat`→`Float`，`PDouble`→`Double`，`PBool`→`Bool`，`PString`→`String`，`PBytes`→`Bytes`，`PMessage(n)`→`n`，`PEnum(n)`→`n`，R6.1）；② repeated 字段 → `Array[元素类型]`（R6.2）；③ 每结构体配套 `encode(self) -> Bytes` 与 `decode(Bytes) -> Result[Self, DecodeError]` 方法，方法体**委托共享类型化编解码**（`encode_typed`/`decode_typed`）以保证与库语义一致（R6.3）。生成代码可被工具链编译（R6.4，以固定的 demo 生成模块作编译冒烟）。生成的 `encode`/`decode` 互逆（R6.5，正确性属性 9——因委托同一类型化模型，往返性质由该模型保证）。

### 4.9 端到端实战 demo（R9）

```moonbit
// demo.mbt
pub fn demo_proto() -> String        // 覆盖标量/repeated/嵌套/enum/oneof/map 六类构造
pub fn demo_message() -> TypedMessage // 与 demo_proto 匹配的样例消息
```

`demo_proto` 提供贯穿文档与基准的实战 `.proto`（如一个含嵌套地址、repeated 标签、枚举状态、oneof 联系方式、map 元数据的"用户档案"消息）。`README.mbt.md` 与基准复用同一 `.proto`，演示 `parse_proto_full` → `validate_schema` → `gen_moonbit_full` → `encode_typed` → `decode_typed` → JSON 往返的端到端流程，全部经 `moon test *.mbt.md` 验证（R9.1–9.4）。

### 4.10 性能基准设计（R7）

`benches/serialization_bench/` 覆盖四类工作负载：① **varint 密集**（大量小整型字段/元素）；② **大 repeated**（长数值标量序列，packed 与非 packed 对比）；③ **嵌套深度**（深层嵌套消息编解码）；④ **字符串密集**（大量/长 string/bytes）。对 `encode_typed`/`decode_typed`/`encode_canonical`/JSON 计时，输出含机器标识、后端目标、输入规模与计时统计的 JSON/Markdown 工件（R7.2），写入 `benches/results/`；新运行与基线中位数比较、超声明容差给可审计失败报告（R7.3，复用既有 guard 模式）。文档记录运行命令，并要求 native 后端先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R7.4）。

---

## 数据模型（Data Models）

新增类型一览（既有 `WireType`/`FieldValue`/`FieldEntry`/`Message`/`FieldType`/`FieldDef`/`MessageDef`/`EnumDef`/`Schema`/`DecodeError`/`ParseError` 不变）：

| 类型 | 文件 | 说明 |
|---|---|---|
| `ProtoType` / `FieldLabel` / `FieldOption` | `schema_model.mbt` | 完整 proto3 字段类型/标签/选项 |
| `ProtoField` / `ProtoMessage` / `ProtoSchema` | `schema_model.mbt` | 富模式模型（含 map/oneof/reserved/嵌套） |
| `ReservedRange` / `MapEntry` / `OneofDef` | `schema_model.mbt` | 保留区间 / map 条目 / oneof 组 |
| `TypedValue` / `TypedMessage` | `typed.mbt` | 类型化取值与消息（含未知字段） |
| `SchemaError` | `schema_validate.mbt` | 模式校验诊断（携带定位） |

**未知字段保留**：`TypedMessage.unknown : Array[FieldEntry]` 原样保留 schema 中无定义的字段（号/wire/原始取值），重编码写回（R2.1/2.2/2.7）。**默认值与未设置语义**：`fields` 仅含显式设置项，取默认值的标量在编码时省略、读取时由 `get_or_default` 按类型补默认（R1.7/1.8）。**发布元数据**：版本自 `0.1.0` 起按旗舰深化做次/主版本推进（R11.6），`release_info`/`release_info_with_gates` 语义不变，仅 `serialization_version` 字符串与 `CHANGELOG.md` 更新（R10.5）。

---

## 错误处理（Error Handling）

- **wire 解码错误（既有）**：`decode`/`decode_typed` 遇非法字节返回携带出错字节偏移的 `DecodeError`（`UnexpectedEof`/`MalformedVarint`/`InvalidWireType`/`InvalidFieldNumber`），且**不产生部分构造的消息**——所有字段先收集到局部数组，仅当合法扫描至末尾才构造（R11.3，沿用既有 `wire.mbt` 契约）。
- **类型不符**：类型化解码遇 wire 类型与声明 `ProtoType` 不符，映射到既有 `InvalidWireType(offset, tag)`（不扩容 `DecodeError` 枚举）。
- **.proto 解析错误（既有）**：`parse_proto_full` 复用既有 `ParseError`（`line`/`col`/`offset`/`message`），任何语法错误经 `ParseError::at(pos, msg)` 返回，**不构造 `ProtoSchema`**（R3.7）。
- **JSON 错误**：`decode_json` 复用 `ParseError` 报告结构非法/类型不符的行列定位，**不产生部分构造消息**（R5.4）。
- **模式校验错误**：`validate_schema` 返回 `Array[SchemaError]`（全新类型，自由携带 message/field/号/名定位），可一次性报告多条诊断（R4.2–4.5）。
- **base64 解码失败**：`base64_decode` 返回 `Bytes?`（`None` 表示非法 base64），由 `decode_json` 转为带定位的 `ParseError`。

---

## 算法说明与 paper-to-code 可追溯（R8）

| 算法 / 规范 | 来源 | 本库落点 |
|---|---|---|
| wire format + varint base-128 | Protocol Buffers 官方《Encoding》规范 | 既有 `write_varint`/`read_varint`、`encode`/`decode`；类型化层 `typed.mbt` |
| zigzag（sint） | Protocol Buffers 编码规范（sint32/sint64） | 新 `zigzag.mbt`（`(n<<1)^(n>>k)`） |
| 定长 I32/I64（IEEE-754） | IEEE-754 + protobuf fixed/float/double | 新 `double_to_bits`/`float_to_bits` + 既有 `write_fixed`/`read_fixed` |
| packed repeated | protobuf 规范（proto3 数值标量默认 packed） | `typed.mbt` 打包 + `canonical.mbt` 确定性 packed |
| 确定性/规范化编码 | protobuf deterministic serialization | 新 `canonical.mbt`（升序 + packed + 每字段一次） |
| proto3 JSON 映射 | Protocol Buffers《ProtoJSON》规范 | 新 `json.mbt`（camelCase / 64 位整数为字符串 / base64） |
| proto3 文法 | protobuf 语言规范（proto3） | 新 `proto_grammar.mbt`（构建于 `@parser_combinator`） |
| base64 | RFC 4648 | 新 `json.mbt` 的 `base64_encode`/`decode` |

各新增文件头部以注释标注其对应规范与本设计章节（沿用既有 `wire.mbt`/`types.mbt` 的注释风格），实现 paper-to-code 可追溯（R8.1–8.3）。

---

## 三后端一致性与可移植性（R11.1/R11.5）

- **位级浮点而非数值浮点**：float/double 一律经 `*_to_bits`/`bits_to_*` 做**位级** reinterpret 编解码。这是 js 后端（数字底层为 double）下 `Float` 精度一致性的关键——编解码只搬运 IEEE-754 比特，不做数值运算，故 `wasm-gc`/`js`/`native` 三后端位级一致。属性测试对 float/double 字段断言位级相等。
- **UInt64 跨后端一致**：varint 与 fixed64 全程以 `UInt64` 位运算实现（既有 `write_varint`/`read_fixed` 已如此），不依赖平台整型宽度；zigzag 用算术右移，三后端一致。
- **base64 确定性**：标准字母表 + 固定填充，纯字节运算，无平台依赖。
- **确定性随机源**：全部属性测试复用 `@infra_pbt` 种子驱动 `Rng`，保证三后端逐位一致、可重放，任一后端输出分歧即判构建失败（R11.1）。
- **native 前置**：文档与脚本要求 native 后端运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R7.4/R11.5）。
- **门禁聚合**：三后端测试、属性测试、可执行文档任一未过，`release_info_with_gates` 经 `@release_meta` 聚合阻止本方向进入 release-ready（R11.7）。

---

## 设计权衡与开源对标（R8.4/R8.5）

| 维度 | 本库 | Protocol Buffers | Cap'n Proto | FlatBuffers | MessagePack |
|---|---|---|---|---|---|
| 模式依赖 | 是（schema 驱动类型化） | 是 | 是 | 是 | 否（自描述） |
| 自描述性 | 否（wire 不含类型，需 schema） | 否 | 部分 | 部分 | 是 |
| 零拷贝读取 | 否（解码构造内存对象） | 否 | 是 | 是 | 否 |
| 编码紧凑度 | 高（varint + packed + 默认省略） | 高 | 中（按字对齐） | 中（含偏移表） | 高 |
| 确定性编码 | 是（规范化 + 幂等） | 可选（deterministic） | N/A | N/A | 否（实现相关） |
| 文本互转 | 是（proto3 JSON） | 是（ProtoJSON） | 是（capnp 文本） | 是（JSON） | 部分 |
| 未知字段保留 | 是 | 是 | 否 | 否 | N/A |

**核心取舍**：与 Protocol Buffers 同侧——**以"需要 schema、非零拷贝"换取最紧凑的 varint/packed 编码、确定性序列化与稳健的模式演进（未知字段保留）**。零拷贝读取（Cap'n Proto/FlatBuffers 的核心卖点）不在本库目标内：本库优先编码紧凑度与编解码语义正确性，而非读取期免反序列化。

**实现边界声明（R8.5，显式而非隐式留白）**：
- **不支持 proto2 group（wire 3/4）**：已废弃，与既有 `WireType` 一致只支持 0/1/2/5。
- **不支持 extensions 与自定义 well-known types**（如 `Any`/`Timestamp` 的特殊 JSON 形态）：超出 proto3 核心范围；如需可在上层封装。
- **不支持 import 跨文件解析**：`parse_proto_full` 跳过 `import` 语句（单文件模式），跨文件符号解析留待上层。
- 以上边界在 `README.mbt.md` 与本文档显式声明。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 |
|---|---|
| R1 类型化编解码 | 4.3 zigzag/位级；4.4 `TypedValue`/`encode_typed`/`decode_typed` |
| R2 wire 完整性与确定性 | 4.4 未知字段/packed；4.5 `encode_canonical`/`canonicalize_wire` |
| R3 完整 proto3 文法 | 4.1 `ProtoSchema`；4.2 `parse_proto_full`/`print_proto` |
| R4 模式校验 | 4.6 `SchemaError`/`validate_schema` |
| R5 proto3 JSON | 4.7 `encode_json`/`decode_json`/base64 |
| R6 完整代码生成 | 4.8 `gen_moonbit_full` |
| R7 性能基准 | 4.10 `benches/serialization_bench` |
| R8 可解释性/对标 | 「算法说明」「设计权衡与开源对标」 |
| R9 端到端 demo | 4.9 `demo.mbt` + README |
| R10 向后兼容 | 「设计原则与兼容契约」「模块划分」冻结列；4.1 `to_legacy` 桥 |
| R11 质量门禁 | 「三后端一致性」+ 测试策略 + 正确性属性 |

---

## 测试策略（Testing Strategy）

**双轨测试**：单元测试锁定具体见证与边界/错误条件；属性测试以 `@infra_pbt` 覆盖通用不变量（每条 ≥100 迭代，R11.2）。

- **单元测试（示例/边界/错误）**：
  - 文法解析具体样例（oneof/map/嵌套/reserved/选项，R3.2–3.6）与语法错误位置（R3.7）；
  - 模式校验各错误场景（重复号/reserved/未解析引用/枚举首值非 0/字段号越界，R4.1–4.5）与正向通过（R4.6）；
  - JSON 格式细节（camelCase、64 位整数为字符串、bytes base64，R5.1）与非法 JSON 错误（R5.4）；
  - 代码生成文本含结构体/字段/Array/方法（R6.1–6.3），固定 demo 生成模块编译冒烟（R6.4）；
  - 默认值不写入字节（R1.7 示例）；端到端 demo 流程（R9.1–9.2）；
  - 既有 API 回归（R10.1/10.2）、`release_info` 稳定与门禁真值表（R10.5/R11.6/R11.7）。
- **属性测试**：见下「正确性属性」P1–P11，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`；生成器涵盖随机模式（含 sint/float/double/fixed/repeated/packed/嵌套/map/oneof）与匹配的类型化消息、随机字节序列（含非法）、随机合法模式。
- **基准与冒烟**：`benches/serialization_bench` 四类负载（R7.1）、工件产出（R7.2）、guard 回归（R7.3）；`README.mbt.md` 经 `moon test *.mbt.md`（R9.4/R11.4）。
- **三后端**：同一套件在 `wasm-gc`/`js`/`native` 运行，分歧判失败（R11.1）；native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R11.5）。
- **属性测试标注**：统一 `Feature: serialization, Property {n}: {text}`，并以 `**Validates: Requirements X.Y**` 链接验收标准。

---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有合法执行下应恒成立行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。下列属性均以全称量化表述，并复用 `@infra_pbt` 的 `holds_for_all`/`round_trip`（每条 ≥100 迭代）。*

### Property 1：既有 wire 往返（legacy wire round-trip）

*对任意*由生成器产出的字段记录序列消息 `m`，先用既有 `encode` 编码再用既有 `decode`（以 `Schema::empty()`）解码，应得到与 `m` 相等的消息，即 `decode(encode(m), Schema::empty()) == Ok(m)`。

**Validates: Requirements 10.2, 10.6**

### Property 2：类型化往返（typed round-trip）

*对任意*由生成器产出的（富模式, 类型化消息）对，先 `encode_typed` 再 `decode_typed` 得到与原消息内容相等的结果。该属性统摄字段号→命名字段映射、sint 的 zigzag、bool/enum、定长 float/double/fixed 的位级解释、string/bytes 与嵌套消息的递归、repeated 聚合、proto3 标量默认值省略与未设置字段的默认值语义。

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9**

### Property 3：zigzag 双射（zigzag bijection）

*对任意* 32 位或 64 位有符号整数 `n`，zigzag 编码再解码为恒等：`zigzag_decode_32(zigzag_encode_32(n)) == n` 且 `zigzag_decode_64(zigzag_encode_64(n)) == n`。

**Validates: Requirements 1.2**

### Property 4：规范编码幂等（canonical-encoding idempotence）

*对任意*由生成器产出的（富模式, 类型化消息）对，对消息先确定性编码、再解码、再确定性编码所得字节，与首次确定性编码逐字节相等：`encode_canonical(decode_typed(encode_canonical(m))) == encode_canonical(m)`（升序字段号 + packed 数值标量）。

**Validates: Requirements 2.3, 2.4, 2.6**

### Property 5：未知字段保留（unknown-field preservation）

*对任意*由生成器产出的含未知字段消息，类型化解码再编码后，未知字段的字段号与原始取值集合保持不变（解码保留、重编码写回）。

**Validates: Requirements 2.1, 2.2, 2.7**

### Property 6：packed 与非 packed 等价（packed equivalence）

*对任意*由生成器产出的数值标量序列，将其编码为 packed 形式与编码为同字段号多次出现的非 packed 形式，两者经解码得到相同的元素序列。

**Validates: Requirements 2.5, 2.8**

### Property 7：合法模式校验通过（valid-schema acceptance）

*对任意*由生成器产出的合法富模式（字段号在合法范围且唯一、不触保留、类型引用可解析、proto3 枚举首值为 0），`validate_schema` 返回成功且不报告任何诊断。

**Validates: Requirements 4.1, 4.6, 4.7**

### Property 8：JSON↔二进制等价（JSON/binary equivalence）

*对任意*由生成器产出的（富模式, 类型化消息）对，经二进制往返（`decode_typed ∘ encode_typed`）所得消息与经 JSON 往返（`decode_json ∘ encode_json`）所得消息内容彼此相等。

**Validates: Requirements 5.1, 5.2, 5.3, 5.5**

### Property 9：生成代码往返（generated-code round-trip）

*对任意*由生成器产出的合法富模式与该模式下的类型化消息，`gen_moonbit_full` 所生成结构体配套的编码方法与解码方法互逆（其行为由所委托的共享类型化编解码模型定义，故对该模型断言 `decode ∘ encode == 恒等`）。

**Validates: Requirements 6.3, 6.5**

### Property 10：解码错误位置与无部分产物（decode-error offset）

*对任意*由生成器产出的非法字节序列，`decode`/`decode_typed` 返回携带出错字节偏移的 `DecodeError`（偏移落在 `[0, 输入长度]` 合法范围内），且不产生部分构造的消息（返回 `Err` 而非 `Ok(部分消息)`）。

**Validates: Requirements 11.3**

### Property 11：proto 模式解析 round-trip（schema parse round-trip）

*对任意*由生成器产出的合法富模式 `s`，先规范打印再解析应得到等价模式：`parse_proto_full(print_proto(s)) == Ok(s)`。该属性验证完整 proto3 文法解析（含 oneof/map/嵌套/reserved/字段选项/全部标量类型）的结构保真性。

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**
