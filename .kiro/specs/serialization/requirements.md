# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Serialization_Framework（方向九）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开类型与 API（wire 运行时模型 `WireType`/`FieldValue`/`FieldEntry`/`Message`、模式模型 `FieldType`/`FieldDef`/`MessageDef`/`EnumDef`/`Schema`、含位置的错误模型 `DecodeError`/`ParseError`，以及函数 `encode`/`decode`/`parse_proto`/`gen_moonbit`），并在既有 `message → wire → bytes → message` 与 `.proto → Schema → 代码` 两条流水线之上，扩展为一套对标 Protocol Buffers、Cap'n Proto、FlatBuffers 与 MessagePack 的旗舰级 protobuf 序列化库。

旗舰目标聚焦八条主线：

- **模式驱动的类型化编解码**：在既有 wire 粒度通用扫描之上，按 `Schema` 把字段号映射为命名字段，正确解释 sint 的 zigzag、bool、enum、定长 float/double、string/bytes、嵌套消息，并支持 repeated 与 packed repeated、proto3 标量默认值省略与未设置字段语义。
- **完整 proto3 文法解析**：把 `parse_proto` 由「顶层 message/enum + 简单字段」升级为覆盖 oneof、map<K,V>、嵌套消息/枚举、保留字段、全部标量类型与字段选项的完整 proto3 文法。
- **wire format 完整性与确定性**：未知字段的保留与重新编码，以及确定性/规范化编码（字段号升序 + packed），保证规范编码幂等。
- **proto3 JSON 映射**：消息与 proto3 JSON 文本之间的编解码，并与二进制 wire 表示语义等价（同一消息两种表示可互转）。
- **完整代码生成**：把 `gen_moonbit` 由结构体骨架升级为生成带字段的结构体 + 配套 `encode`/`decode` 方法，且生成代码可编译、往返自洽。
- **模式校验**：字段号范围与唯一性、保留号冲突、类型引用解析、proto3 枚举首值为 0 等校验，返回含位置诊断。
- **可解释性**：paper-to-code 可追溯（protobuf 编码规范、varint base-128、zigzag、proto3 JSON 规范），并与 Protocol Buffers、Cap'n Proto、FlatBuffers、MessagePack 的编码模型与权衡对比、显式声明本库实现边界。
- **质量门禁**：完整属性测试（wire 往返、类型化往返、规范编码幂等、未知字段保留、JSON↔二进制等价、zigzag 双射、packed 与非 packed 等价解码、解码错误位置、模式校验正确性等），三后端（`wasm-gc`/`js`/`native`）一致性，`README.mbt.md` 可执行文档扩充，性能基准与回归基线 guard，以及独立 SemVer 版本推进。

本规格承袭仓库统一质量基线（见 Requirement 11），并复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@parser_combinator`（`.proto` 文法解析）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **Serialization_Framework**：本方向的 protobuf 序列化库系统（子包 `src/serialization`），是本文档所有验收标准的主体系统。
- **wire format（线格式）**：Protocol Buffers 的二进制编码格式，每条字段以 tag（`字段号 << 3 | wire 类型`）开头，后接取值。
- **WireType（wire 类型）**：tag 低 3 位编码的线格式类别，本库支持 `Varint`(0)、`I64`(1)、`Len`(2)、`I32`(5) 四类；废弃的 group（3/4）不在支持范围内。
- **Varint（变长整数）**：base-128 变长整数编码，每字节低 7 位载荷、高位为续位标志，承载 int32/int64/uint32/uint64/bool/enum/sint*。
- **zigzag 编码**：把有符号整数映射为无符号整数以高效编码小幅负值的变换（`(n << 1) ^ (n >> 63)`），用于 sint32/sint64。
- **定长字段（Fixed-Width Field）**：`I64`（8 字节小端，承载 fixed64/sfixed64/double）与 `I32`（4 字节小端，承载 fixed32/sfixed32/float）。
- **长度前缀字段（Length-Prefixed Field）**：`Len` 类别，以 varint 长度前缀 + 原始字节承载 string/bytes/嵌套消息/packed repeated。
- **Message（消息）**：内存中的消息对象，骨架以字段记录序列 `fields : Array[FieldEntry]` 表示，保留 wire 顺序。
- **FieldEntry（字段记录）**：一条已编解码字段，含字段号 `number` 与 wire 取值 `value : FieldValue`。
- **FieldValue（字段值）**：wire 层面未经模式类型化的原始取值，含 `VVarint`/`VI64`/`VI32`/`VBytes` 四个变体。
- **TypedValue（类型化取值）**：经 `Schema` 解释后的字段值（如把 `VVarint` 解读为 sint 的有符号整数、bool、enum 值，或把 `VI64` 解读为 double），为模式驱动编解码的目标表示。
- **Schema（模式）**：`.proto` 解析产物，含 `messages : Array[MessageDef]` 与 `enums : Array[EnumDef]`，驱动类型化编解码与代码生成。
- **FieldType（字段类型）**：模式层字段类型，含 `TInt32`/`TInt64`/`TUInt32`/`TUInt64`/`TBool`/`TString`/`TBytes`/`TMessage(name)`/`TEnum(name)`。
- **FieldDef / MessageDef / EnumDef**：分别为字段定义（名称/字段号/类型/是否 repeated）、消息定义（名称 + 字段序列）、枚举定义（名称 + `(标识符, 取值)` 序列）。
- **repeated 字段**：可出现零次或多次的字段，类型化解码后映射为元素序列。
- **packed repeated（紧凑重复）**：proto3 中数值标量 repeated 字段的默认编码，将全部元素打包进单个 `Len` 字段的载荷内，而非每元素一条记录。
- **proto3 默认值省略（Default-Value Omission）**：proto3 中标量字段取其类型默认值（如 0、false、空串）时不写入 wire 字节的编码规则。
- **未设置字段（Unset Field）**：解码所得消息中未出现的标量字段，类型化视图下取其类型默认值。
- **未知字段（Unknown Field）**：解码时在 `Schema` 中找不到对应定义的字段；本库予以保留以便重新编码时不丢失。
- **确定性编码 / 规范化编码（Deterministic / Canonical Encoding）**：对同一消息内容产出唯一字节序列的编码，规则为字段号升序、数值标量 repeated 采用 packed、每字段至多一次。
- **幂等（Idempotent）**：对已是规范形态的字节再次规范编码得到逐字节相同的结果。
- **proto3 JSON（proto3 JSON 映射）**：Protocol Buffers 规范定义的消息与 JSON 文本之间的标准映射（字段名采用 camelCase、64 位整数表示为字符串、bytes 采用 base64 等）。
- **JSON↔二进制等价（JSON/Binary Equivalence）**：同一消息的 proto3 JSON 表示与二进制 wire 表示承载相同内容，且二者在给定 `Schema` 下可无损互转。
- **DecodeError（解码错误）**：含出错字节偏移的解码错误枚举（`UnexpectedEof`/`MalformedVarint`/`InvalidWireType`/`InvalidFieldNumber`），均可经 `DecodeError::offset` 提取偏移。
- **ParseError（解析错误）**：含行列与偏移位置的 `.proto` 解析错误（`line`/`col`/`offset`/`message`）。
- **SchemaError（模式校验错误）**：模式校验所报告的、携带定位信息（行列或字段标识）的诊断，如字段号越界、字段号重复、保留号冲突、类型引用未解析、枚举首值非 0。
- **oneof**：proto3 中一组互斥字段，任一时刻至多一个成员被设置。
- **map<K,V>**：proto3 键值映射字段，wire 上等价于 `repeated` 的键值对条目消息。
- **保留字段（Reserved Field）**：以 `reserved` 声明保留的字段号或字段名，禁止被后续字段定义重用。
- **代码生成（Code Generation）**：`gen_moonbit` 由 `Schema` 产出 MoonBit 源码（结构体定义 + 配套编解码方法）的过程。
- **往返（Round-Trip）**：编码与解码互逆（`decode(encode(x)) == Ok(x)`），或 `.proto` 文法与打印互逆，或 JSON 与二进制互转后内容不变。
- **解码错误位置（Decode-Error Offset）**：`DecodeError` 报告的出错字节偏移，定位首个非法字节。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@parser_combinator**：仓库共享解析器组合子包，提供 `Input`/`Pos`/`ParseResult`/`satisfy`/`many1` 等原语，`parse_proto` 构建于其上。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：模式驱动的类型化编解码

**用户故事（User Story）：** 作为使用 `.proto` 模式的开发者，我想要按 `Schema` 把字段号映射为命名字段并按其声明类型解释取值，以便我能以类型化视图编码与解码消息，而不必手工处理 wire 层细节。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用方提供 `Schema` 与某消息定义对一条消息做类型化解码，THE Serialization_Framework SHALL 按字段号将每个 wire 字段映射为该消息定义中对应的命名字段。
2. WHEN 类型化解码字段类型为 `sint32` 或 `sint64` 的 Varint 字段，THE Serialization_Framework SHALL 以 zigzag 解码将其还原为有符号整数取值。
3. WHEN 类型化解码字段类型为 `bool` 或 `enum` 的 Varint 字段，THE Serialization_Framework SHALL 将取值分别解释为布尔值或对应枚举常量。
4. WHEN 类型化解码字段类型为 `double`/`fixed64`/`sfixed64` 的 `I64` 字段或 `float`/`fixed32`/`sfixed32` 的 `I32` 字段，THE Serialization_Framework SHALL 按定长小端位将其解释为对应的浮点或定长整数取值。
5. WHEN 类型化解码字段类型为 `string`、`bytes` 或嵌套消息的 `Len` 字段，THE Serialization_Framework SHALL 将载荷分别解释为字符串、原始字节或递归解码后的嵌套消息。
6. WHEN 类型化解码 repeated 字段，THE Serialization_Framework SHALL 将该字段号的全部出现按 wire 顺序聚合为元素序列。
7. WHEN 类型化编码取其类型默认值的 proto3 标量字段，THE Serialization_Framework SHALL 省略该字段而不写入 wire 字节。
8. WHILE 类型化解码所得消息缺失某标量字段，THE Serialization_Framework SHALL 在类型化视图中将该字段呈现为其类型的默认值。
9. FOR ALL 由生成器产生的（模式, 类型化消息）对，THE Serialization_Framework SHALL 满足类型化往返性质：先类型化编码再类型化解码得到与原消息内容相等的结果（typed round-trip，以 PBT 验证）。

---

### Requirement 2：wire format 完整性与确定性编码

**用户故事（User Story）：** 作为在模式演进与跨服务转发中传递消息的开发者，我想要未知字段被保留且能产出规范化的确定性编码，以便我能在不丢失数据的前提下获得可复现、可比对的字节输出。

#### 验收标准（Acceptance Criteria）

1. WHEN 类型化解码遇到 `Schema` 中无对应定义的字段，THE Serialization_Framework SHALL 将该未知字段的字段号、wire 类型与原始取值保留于消息中。
2. WHEN 重新编码含已保留未知字段的消息，THE Serialization_Framework SHALL 将这些未知字段一并写回输出字节。
3. WHEN 调用方请求确定性编码，THE Serialization_Framework SHALL 按字段号升序输出各字段。
4. WHEN 确定性编码数值标量 repeated 字段，THE Serialization_Framework SHALL 采用 packed 形式将全部元素打包进单个 `Len` 字段。
5. WHEN 解码 packed repeated 字段或同字段号多次出现的非 packed repeated 字段，THE Serialization_Framework SHALL 产出相同的元素序列。
6. FOR ALL 由生成器产生的消息，THE Serialization_Framework SHALL 满足规范编码幂等性质：对一条消息先确定性编码、再解码、再确定性编码所得字节与首次确定性编码逐字节相等（canonical-encoding idempotence，以 PBT 验证）。
7. FOR ALL 由生成器产生的含未知字段消息，THE Serialization_Framework SHALL 满足未知字段保留性质：解码再编码后未知字段的字段号与原始取值集合保持不变（unknown-field preservation，以 PBT 验证）。
8. FOR ALL 由生成器产生的数值标量序列，THE Serialization_Framework SHALL 满足 packed 与非 packed 等价性质：两种编码经解码得到相同的元素序列（packed equivalence，以 PBT 验证）。

---

### Requirement 3：完整 proto3 文法解析

**用户故事（User Story）：** 作为以 `.proto` 描述模式的开发者，我想要 `parse_proto` 支持完整 proto3 文法，以便我能直接解析真实工程中的模式而无需手工拆解 oneof、map 与嵌套类型。

#### 验收标准（Acceptance Criteria）

1. WHEN 解析含 `message`、`enum` 与全部 proto3 标量类型字段的 `.proto` 源码，THE Serialization_Framework SHALL 构造含对应消息、枚举与字段定义的 `Schema`。
2. WHEN 解析 `oneof` 块，THE Serialization_Framework SHALL 将其成员字段识别为同一互斥组并保留各成员的字段号与类型。
3. WHEN 解析 `map<K, V>` 字段，THE Serialization_Framework SHALL 将其建模为键类型 `K`、值类型 `V` 的映射字段。
4. WHEN 解析嵌套的 `message` 或 `enum` 定义，THE Serialization_Framework SHALL 以可按限定名引用的方式登记该嵌套类型。
5. WHEN 解析 `reserved` 声明，THE Serialization_Framework SHALL 记录被保留的字段号区间与字段名。
6. WHERE 字段带有字段选项（如 `[packed = true]` 或 `[deprecated = true]`），THE Serialization_Framework SHALL 解析该选项而不将其误判为语法错误。
7. IF `.proto` 源码存在语法错误，THEN THE Serialization_Framework SHALL 返回携带行列位置的 `ParseError` 且不构造 `Schema`。
8. THE Serialization_Framework SHALL 在 `@parser_combinator` 的 `Input`/`Pos`/`ParseResult` 模型之上实现 `.proto` 文法解析。

---

### Requirement 4：模式校验

**用户故事（User Story）：** 作为维护 `.proto` 模式的开发者，我想要在编解码前对模式做一致性校验，以便我能尽早发现字段号冲突、保留号违例与悬空类型引用等错误并定位它们。

#### 验收标准（Acceptance Criteria）

1. WHEN 校验某消息定义，THE Serialization_Framework SHALL 验证每个字段号落在 proto3 合法字段号范围内（`1` 至 `536870911`，且不含保留区间 `19000`–`19999`）。
2. IF 同一消息内出现重复字段号，THEN THE Serialization_Framework SHALL 返回携带冲突定位的 `SchemaError`。
3. IF 某字段使用了被 `reserved` 声明保留的字段号或字段名，THEN THE Serialization_Framework SHALL 返回携带冲突定位的 `SchemaError`。
4. IF 某字段引用的消息或枚举类型在 `Schema` 中无定义，THEN THE Serialization_Framework SHALL 返回携带该引用位置的 `SchemaError`。
5. IF 某 proto3 枚举的首个枚举值取值不为 `0`，THEN THE Serialization_Framework SHALL 返回携带该枚举定位的 `SchemaError`。
6. WHEN 模式通过全部校验项，THE Serialization_Framework SHALL 返回表示校验成功且无诊断的结果。
7. FOR ALL 由生成器产生的合法模式，THE Serialization_Framework SHALL 满足校验通过性质：校验返回成功且不报告任何诊断（valid-schema acceptance，以 PBT 验证）。

---

### Requirement 5：proto3 JSON 映射

**用户故事（User Story）：** 作为需要在二进制与文本表示间转换的开发者，我想要消息与 proto3 JSON 文本之间的编解码，以便我能在调试、配置与跨语言互操作场景下使用人类可读的等价表示。

#### 验收标准（Acceptance Criteria）

1. WHEN 给定 `Schema` 将一条消息编码为 proto3 JSON，THE Serialization_Framework SHALL 按 proto3 JSON 映射规则输出字段（字段名采用 camelCase、64 位整数表示为字符串、`bytes` 采用 base64 文本）。
2. WHEN 从 proto3 JSON 文本解码一条消息，THE Serialization_Framework SHALL 依据 `Schema` 将各 JSON 字段还原为对应的类型化字段取值。
3. WHILE 将取其类型默认值的 proto3 标量字段编码为 JSON，THE Serialization_Framework SHALL 默认省略该字段。
4. IF JSON 文本结构非法或含与 `Schema` 不符的字段类型，THEN THE Serialization_Framework SHALL 返回携带定位信息的错误且不产生部分构造的消息。
5. FOR ALL 由生成器产生的（模式, 类型化消息）对，THE Serialization_Framework SHALL 满足 JSON↔二进制等价性质：经二进制往返与经 JSON 往返所得消息内容彼此相等（JSON/binary equivalence，以 PBT 验证）。

---

### Requirement 6：完整代码生成

**用户故事（User Story）：** 作为希望由模式直接得到可用类型的开发者，我想要 `gen_moonbit` 生成带字段的结构体及配套编解码方法，以便我能在 MoonBit 中以原生类型读写消息而无需手写编解码逻辑。

#### 验收标准（Acceptance Criteria）

1. WHEN 由 `Schema` 生成代码，THE Serialization_Framework SHALL 为每个消息定义产出一个带全部字段及其映射后 MoonBit 类型的 `pub struct` 声明。
2. WHEN 生成 repeated 字段，THE Serialization_Framework SHALL 将其字段类型映射为 `Array[元素类型]`。
3. WHEN 由 `Schema` 生成代码，THE Serialization_Framework SHALL 为每个消息结构体产出配套的编码方法与解码方法。
4. THE Serialization_Framework SHALL 使生成的代码可被 MoonBit 工具链编译且不产生编译错误。
5. FOR ALL 由生成器产生的合法模式与该模式下的消息，THE Serialization_Framework SHALL 满足生成代码往返自洽性质：生成的编码方法与解码方法互逆（generated-code round-trip，以 PBT 验证）。

---

### Requirement 7：性能基准（benches/）

**用户故事（User Story）：** 作为关心编解码吞吐的开发者，我想要可复现的基准证据，以便我能度量 varint 密集、大 repeated、嵌套深度与字符串密集等负载下的表现并防止性能回归。

#### 验收标准（Acceptance Criteria）

1. THE Serialization_Framework SHALL 在 `benches/` 下提供编解码基准包，覆盖 varint 密集、大 repeated、嵌套深度与字符串密集四类工作负载。
2. WHEN 运行基准，THE Serialization_Framework SHALL 输出包含机器标识、后端目标、输入规模与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE Serialization_Framework SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告。
4. THE Serialization_Framework SHALL 在基准文档中记录运行命令，且在 native 后端要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

### Requirement 8：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键编码规则可追溯到规范并与主流序列化方案对比，以便我能理解设计依据与取舍。

#### 验收标准（Acceptance Criteria）

1. THE Serialization_Framework SHALL 在文档中将 wire format 与 varint base-128 编码追溯到 Protocol Buffers 官方编码规范。
2. THE Serialization_Framework SHALL 在文档中将 sint 的 zigzag 编码追溯到其定义并说明其对小幅负值的编码优势。
3. THE Serialization_Framework SHALL 在文档中将 JSON 映射追溯到 Protocol Buffers 的 proto3 JSON 规范。
4. THE Serialization_Framework SHALL 在文档中提供与 Protocol Buffers、Cap'n Proto、FlatBuffers 及 MessagePack 的编码模型与权衡对比，覆盖模式依赖、零拷贝、自描述性与编码紧凑度的差异。
5. WHERE 本库不支持某类构造（如 proto2 group、扩展 extensions 或自定义 well-known types），THE Serialization_Framework SHALL 在文档中显式声明该实现边界及其理由，而非隐式留白。

---

### Requirement 9：端到端实战 demo

**用户故事（User Story）：** 作为评估该库可用性的开发者，我想要一份贯穿文档与基准的实战 `.proto`，以便我能看到从模式解析到编解码与 JSON 互转的端到端用法。

#### 验收标准（Acceptance Criteria）

1. THE Serialization_Framework SHALL 提供一份贯穿文档与基准的实战 `.proto`，至少覆盖标量、`repeated`、嵌套消息、`enum`、`oneof` 与 `map` 六类构造。
2. WHEN 对该实战 `.proto` 运行端到端流程，THE Serialization_Framework SHALL 依次完成 `parse_proto` → `gen_moonbit` → 编码 → 解码 → JSON 往返并产出一致结果。
3. WHEN 对该实战消息分别经二进制与 JSON 往返，THE Serialization_Framework SHALL 产出彼此内容相等的消息。
4. THE Serialization_Framework SHALL 在 `README.mbt.md` 可执行文档中以该实战 `.proto` 演示上述端到端流程，且全部示例通过 `moon test *.mbt.md` 验证。

---

### Requirement 10：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有代码在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Serialization_Framework SHALL 保留既有公开类型 `WireType`、`FieldValue`、`FieldEntry`、`Message`、`FieldType`、`FieldDef`、`MessageDef`、`EnumDef`、`Schema`、`DecodeError`、`ParseError` 及其现有公开方法的签名与语义。
2. THE Serialization_Framework SHALL 保留既有函数 `encode`、`decode`、`parse_proto`、`gen_moonbit` 的现有公开签名与行为，使既有 wire 粒度通用编解码与既有 `.proto` 解析结果不变。
3. WHERE 新增能力需要扩展行为，THE Serialization_Framework SHALL 以新增 API（如类型化编解码、确定性编码、JSON 映射、模式校验）的方式提供，而不破坏既有 API 的调用方。
4. THE Serialization_Framework SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板。
5. THE Serialization_Framework SHALL 复用 `@release_meta` 的 `DirectionRelease`/`QualityGates`/SemVer 模型登记本方向发布元数据，并保持 `release_info`/`release_info_with_gates` 的现有语义。
6. FOR ALL 由生成器产生的字段记录序列消息，THE Serialization_Framework SHALL 满足既有 wire 往返性质：`decode(encode(m), Schema::empty())` 得到与 `m` 相等的消息（legacy wire round-trip，以 PBT 验证）。

---

### Requirement 11：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Serialization_Framework SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Serialization_Framework SHALL 为本规格的核心正确性属性（类型化往返、规范编码幂等、未知字段保留、JSON↔二进制等价、zigzag 双射、packed 与非 packed 等价解码、解码错误位置、模式校验正确性、生成代码往返）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. WHEN 对非法字节解码，THE Serialization_Framework SHALL 返回携带出错字节偏移的 `DecodeError` 且不产生部分构造的消息。
4. THE Serialization_Framework SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖类型化编解码、确定性编码、JSON 映射、模式校验、代码生成与端到端 demo，且全部示例通过 `moon test *.mbt.md` 验证。
5. WHEN 运行三后端测试中的 native 后端，THE Serialization_Framework SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
6. THE Serialization_Framework SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
7. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE Serialization_Framework SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
