# serialization · 可执行文档

> **方向九（R9）序列化框架** — protobuf wire format 编解码 · 编码再解码往返 · 三后端一致 · 文档即测试。
>
> 本文件既是 `serialization` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/serialization/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 7.5**。

本文件作为 `serialization` 包的黑盒测试运行，因此可直接调用本包公开 API
（`encode` / `decode` / `Message` / `FieldEntry` / `FieldValue` / `Schema` 等）而无需限定包名。
下面 4 段示例覆盖**编码再解码往返、四类 wire 类型、解码错误的含偏移诊断**，以及
**`.proto` 解析到代码生成**的完整流水线，串起 `message → wire → bytes → message` 闭环。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。
>
> **关于构造手法**：黑盒文档中字段值统一经由 `FieldValue::varint` / `i64` / `i32` /
> `bytes` 四个构造函数得到（而非直接书写枚举构造子），与 `regex_engine` 文档经
> `parse_regex` 取值的规避手法一致；消息则由 `Message::from_fields` 装配。

---

## 数据模型速览

* `encode(msg : Message) -> Bytes` —— 把内存消息对象编码为 protobuf wire format 字节
  序列（**R9.1**）。每条字段先写 tag（`字段号<<3 | wire 类型`），再写取值。
* `decode(bytes : Bytes, schema : Schema) -> Result[Message, DecodeError]` —— 把字节序列
  解码回消息对象（**R9.2**）；任何非法字节返回**含出错字节偏移**的 `DecodeError`，
  且**不产生部分构造对象**（**R9.4**）。
* `Message::from_fields(fields)` / `FieldEntry::new(number, value)` —— 装配消息与字段记录。
* `FieldValue::{varint, i64, i32, bytes}` —— 分别对应四类 wire 类型（Varint / I64 / I32 / Len）。
* `parse_proto(src : String) -> Result[Schema, ParseError]` 与 `gen_moonbit(schema : Schema) -> String`
  —— `.proto` 解析与代码生成（**R9.5 / R9.7**）。

---

## 示例 1 · 编码再解码往返 —— encode → decode round-trip（核心）

`encode` 把消息写成 wire 字节，`decode` 再读回等价消息，二者互逆（往返自洽，
为 Property 20 奠基）。下例取 protobuf 经典示例——字段 1、Varint 值 150——其规范
编码恰为字节 `08 96 01`；解码回的消息与原消息逐字段相等（**R9.1 / R9.2 / R9.3**）。

```mbt check
///|
test "README · encode 再 decode 还原等价消息（Varint 经典示例）" {
  let msg = Message::from_fields([FieldEntry::new(1, FieldValue::varint(150UL))])
  // 字段 1、Varint 150 的 protobuf 规范编码为 08 96 01。
  let bytes = encode(msg)
  assert_true(bytes == b"\x08\x96\x01")
  // decode 是 encode 的逆：解码回与原消息等价的对象。
  match decode(bytes, Schema::empty()) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("往返不应失败：\{e}")
  }
  // 往返自洽：decode(encode(x)) == Ok(x)。
  assert_true(decode(encode(msg), Schema::empty()) == Ok(msg))
}
```

---

## 示例 2 · 四类 wire 类型 —— Varint / I64 / I32 / Len 混合往返

protobuf wire format 有四类受支持的 wire 类型，分别由 `FieldValue::varint`（变长整数）、
`i64`（定长 8 字节小端）、`i32`（定长 4 字节小端）与 `bytes`（长度前缀）承载。下例
把四类字段（且乱序）装入同一消息，编码再解码后**逐字段相等且保持原始字段顺序**。

```mbt check
///|
test "README · 四类 wire 类型混合编解码并保持顺序" {
  let msg = Message::from_fields([
    FieldEntry::new(5, FieldValue::i32(0x01020304U)), // I32：定长 4 字节
    FieldEntry::new(1, FieldValue::varint(150UL)), // Varint：变长整数
    FieldEntry::new(3, FieldValue::bytes(b"hi")), // Len：长度前缀
    FieldEntry::new(2, FieldValue::i64(0x0102030405060708UL)), // I64：定长 8 字节
  ])
  match decode(encode(msg), Schema::empty()) {
    Ok(out) => {
      // 整体等价
      assert_true(out == msg)
      // 字段顺序按构造保留（解码不重排）
      let nums = out.fields.map(fn(e) { e.number })
      assert_true(nums == [5, 1, 3, 2])
      // 各字段的 wire 类型可由取值还原
      assert_true(out.fields[0].value.wire_type() == WireType::I32)
      assert_true(out.fields[2].value.wire_type() == WireType::Len)
    }
    Err(e) => fail("混合 wire 类型往返不应失败：\{e}")
  }
}
```

---

## 示例 3 · 解码错误的含偏移诊断 —— 非法字节不产生部分对象

非法字节序列不会产出半成品消息，而是返回携带**出错字节偏移**的 `DecodeError`
（**R9.4**）。下例演示两类错误：续位标志置位却无后续字节的**截断 varint**
（`UnexpectedEof`，偏移 0），以及 tag 低三位为 3（废弃 group）的**非法 wire 类型**
（`InvalidWireType`，偏移 0）。`DecodeError::offset` 提供统一的偏移读取入口。

```mbt check
///|
test "README · 非法字节返回含偏移的解码错误" {
  // 截断 varint：单字节 0x80 续位置位却无后继 → UnexpectedEof(offset=0)
  match decode(b"\x80", Schema::empty()) {
    Ok(_) => fail("截断 varint 不应解码成功")
    Err(e) => {
      @test.assert_eq(e.offset(), 0)
      match e {
        UnexpectedEof(..) => assert_true(true)
        _ => fail("期望 UnexpectedEof，实际：\{e}")
      }
    }
  }
  // 非法 wire 类型：tag 0x0b = 字段号 1、wire 3（废弃 group）→ InvalidWireType(offset=0)
  match decode(b"\x0b", Schema::empty()) {
    Ok(_) => fail("非法 wire 类型不应解码成功")
    Err(e) => {
      @test.assert_eq(e.offset(), 0)
      match e {
        InvalidWireType(..) => assert_true(true)
        _ => fail("期望 InvalidWireType，实际：\{e}")
      }
    }
  }
}
```

---

## 示例 4 · 从 .proto 到代码生成 —— parse_proto + gen_moonbit

除 wire 编解码外，本包还能把 `.proto` 模式解析为 `Schema`（**R9.5**），并据此生成
MoonBit 类型骨架（**R9.7**）。下例解析一个含标量与 `repeated` 字段的消息，校验解析
出的字段模式，再由 `gen_moonbit` 产出对应的结构体定义。

```mbt check
///|
test "README · parse_proto 解析模式并 gen_moonbit 生成类型" {
  let src =
    #|message Pt {
    #|  int32 x = 1;
    #|  repeated string tags = 2;
    #|}
  let schema = match parse_proto(src) {
    Ok(s) => s
    Err(e) => {
      fail("合法 .proto 不应解析失败：\{e}")
      Schema::empty()
    }
  }
  // 解析出单个消息 Pt，含两个字段：标量 int32 与 repeated string。
  @test.assert_eq(schema.messages.length(), 1)
  let pt = schema.messages[0]
  @test.assert_eq(pt.name, "Pt")
  assert_true(pt.fields[0].ftype == FieldType::TInt32)
  assert_false(pt.fields[0].repeated)
  assert_true(pt.fields[1].ftype == FieldType::TString)
  assert_true(pt.fields[1].repeated) // repeated → Array[String]
  // 代码生成：repeated 字段映射为 Array[String]。
  let code = gen_moonbit(schema)
  let expected = "// 由 gen_moonbit 生成（骨架）—— 请勿手工编辑\n" +
    "\npub struct Pt {\n  x : Int\n  tags : Array[String]\n} derive(Eq, Debug)\n"
  assert_true(code == expected)
}
```

---

## 示例 5 · 模式驱动的类型化编解码 —— encode_typed / decode_typed（旗舰 R1）

在 wire 粒度通用编解码之上，按 `ProtoSchema` 把字段号映射为命名字段并按声明类型
解释取值：sint 用 zigzag、定长 float/double 用位级 reinterpret、repeated 聚合、proto3
标量默认值省略。下例解析一个含 `sint32` 与 `repeated string` 的模式，构造类型化消息
并往返自洽。

```mbt check
///|
test "README · 模式驱动的类型化编解码往返" {
  let src =
    #|syntax = "proto3";
    #|message Point {
    #|  sint32 x = 1;
    #|  sint32 y = 2;
    #|  repeated string tags = 3;
    #|}
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("解析失败：\{e}")
      ProtoSchema::empty()
    }
  }
  let msg = TypedMessage::new()
    .set(1, TInt(-7L)) // sint32 负值经 zigzag 紧凑编码
    .set(2, TInt(42L))
    .set(3, TList([TStringV("a"), TStringV("b")]))
  let bytes = match encode_typed(schema, "Point", msg) {
    Ok(b) => b
    Err(e) => {
      fail("编码失败：\{e}")
      b""
    }
  }
  match decode_typed(schema, "Point", bytes) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("解码失败：\{e}")
  }
}
```

---

## 示例 6 · 确定性/规范化编码 —— encode_canonical（旗舰 R2）

确定性编码按字段号升序输出、数值标量 repeated 一律 packed、每字段至多一次，对同一
消息内容产出唯一字节序列，从而**幂等**。下例乱序设置字段，校验规范编码的幂等性。

```mbt check
///|
test "README · 确定性编码幂等" {
  let src =
    #|syntax = "proto3";
    #|message Rec { int32 a = 1; int32 b = 2; int32 c = 3; }
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("解析失败：\{e}")
      ProtoSchema::empty()
    }
  }
  // 乱序设置；规范编码按字段号升序输出。
  let msg = TypedMessage::new()
    .set(3, TInt(30L))
    .set(1, TInt(10L))
    .set(2, TInt(20L))
  let b1 = match encode_canonical(schema, "Rec", msg) {
    Ok(b) => b
    Err(e) => {
      fail("规范编码失败：\{e}")
      b""
    }
  }
  // 幂等：解码再规范编码逐字节相等。
  let b2 = match decode_typed(schema, "Rec", b1) {
    Ok(m2) =>
      match encode_canonical(schema, "Rec", m2) {
        Ok(b) => b
        Err(e) => {
          fail("规范编码失败：\{e}")
          b""
        }
      }
    Err(e) => {
      fail("解码失败：\{e}")
      b""
    }
  }
  assert_true(b1 == b2)
}
```

---

## 示例 7 · proto3 JSON 映射 —— encode_json / decode_json（旗舰 R5）

消息与 proto3 JSON 文本互转，与二进制 wire 表示语义等价：字段名采用 camelCase、
64 位整数表示为**字符串**（规避 IEEE-754 53 位精度损失）、`bytes` 采用 base64。

```mbt check
///|
test "README · proto3 JSON 映射与二进制等价" {
  let src =
    #|syntax = "proto3";
    #|message User { int64 user_id = 1; string name = 2; bytes avatar = 3; }
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("解析失败：\{e}")
      ProtoSchema::empty()
    }
  }
  // 2^53 + 1：超出 Double 精度，故 64 位整数必须以字符串承载。
  let msg = TypedMessage::new()
    .set(1, TInt(9007199254740993L))
    .set(2, TStringV("Ada"))
    .set(3, TBytesV(b"\x01\x02\x03"))
  let json = match encode_json(schema, "User", msg) {
    Ok(s) => s
    Err(e) => {
      fail("JSON 编码失败：\{e}")
      ""
    }
  }
  assert_true(json.contains("userId")) // camelCase
  assert_true(json.contains("\"9007199254740993\"")) // 64 位为字符串
  match decode_json(schema, "User", json) {
    Ok(out) => assert_true(out == msg) // 与二进制往返语义等价
    Err(e) => fail("JSON 解码失败：\{e}")
  }
}
```

---

## 示例 8 · 模式校验与完整代码生成 —— validate_schema / gen_moonbit_full（旗舰 R4/R6）

`validate_schema` 校验字段号范围/唯一性、保留冲突、类型引用解析、proto3 枚举首值；
`gen_moonbit_full` 由模式产出带字段的 `pub struct` 与委托共享类型化模型的编解码函数。

```mbt check
///|
test "README · 模式校验与代码生成" {
  let src =
    #|syntax = "proto3";
    #|message Pt { int32 x = 1; repeated string tags = 2; }
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("解析失败：\{e}")
      ProtoSchema::empty()
    }
  }
  match validate_schema(schema) {
    Ok(_) => assert_true(true)
    Err(errs) => fail("合法模式不应报错：\{@debug.to_string(errs)}")
  }
  let code = gen_moonbit_full(schema)
  assert_true(code.contains("pub struct Pt"))
  assert_true(code.contains("tags : Array[String]")) // repeated → Array
  assert_true(code.contains("Pt_encode")) // 委托编解码函数
}
```

---

## 示例 9 · 端到端实战 demo —— 六类构造 + 二进制/JSON 一致（旗舰 R9）

贯穿文档与基准的实战 `.proto`（UserProfile）覆盖标量 / repeated / 嵌套消息 / enum /
oneof / map 六类构造。下例串起 `parse_proto_full` → `validate_schema` →
`encode_typed`/`decode_typed` → JSON 往返，并断言二进制往返与 JSON 往返结果一致。

```mbt check
///|
test "README · 端到端实战 demo" {
  let schema = match parse_proto_full(demo_proto()) {
    Ok(s) => s
    Err(e) => {
      fail("demo 解析失败：\{e}")
      ProtoSchema::empty()
    }
  }
  match validate_schema(schema) {
    Ok(_) => assert_true(true)
    Err(errs) => fail("demo 校验失败：\{@debug.to_string(errs)}")
  }
  let msg = demo_message()
  let bin = match encode_typed(schema, demo_message_name, msg) {
    Ok(b) =>
      match decode_typed(schema, demo_message_name, b) {
        Ok(o) => o
        Err(e) => {
          fail("二进制解码失败：\{e}")
          TypedMessage::new()
        }
      }
    Err(e) => {
      fail("二进制编码失败：\{e}")
      TypedMessage::new()
    }
  }
  let jsn = match encode_json(schema, demo_message_name, msg) {
    Ok(s) =>
      match decode_json(schema, demo_message_name, s) {
        Ok(o) => o
        Err(e) => {
          fail("JSON 解码失败：\{e}")
          TypedMessage::new()
        }
      }
    Err(e) => {
      fail("JSON 编码失败：\{e}")
      TypedMessage::new()
    }
  }
  assert_true(bin == msg)
  assert_true(bin == jsn) // 二进制与 JSON 两条路径所得消息一致
}
```

---

## paper-to-code 可追溯（旗舰 R8）

| 算法 / 规范 | 来源 | 本库落点 |
|---|---|---|
| wire format + varint base-128 | Protocol Buffers《Encoding》规范 | `wire.mbt`（`encode`/`decode`），`typed.mbt` |
| zigzag（sint32/sint64） | Protocol Buffers 编码规范 | `zigzag.mbt`（`(n<<1)^(n>>k)`，算术右移扩散符号位） |
| 定长 I32/I64（IEEE-754） | IEEE-754 + protobuf fixed/float/double | `zigzag.mbt`（位级 reinterpret）+ `wire.mbt` 定长读写 |
| packed repeated | protobuf（proto3 数值标量默认 packed） | `typed.mbt` 打包 + `canonical.mbt` 确定性 packed |
| 确定性序列化 | protobuf deterministic serialization | `canonical.mbt`（升序 + packed + 每字段一次） |
| proto3 JSON 映射 | Protocol Buffers《ProtoJSON》规范 | `json.mbt`（camelCase / 64 位为字符串 / base64） |
| proto3 文法 | protobuf 语言规范（proto3） | `proto_grammar.mbt`（构建于 `@parser_combinator`） |
| base64 | RFC 4648 | `json.mbt`（`base64_encode`/`base64_decode`） |

**zigzag 紧凑性**：小幅负值 `-1 → 1`、`1 → 2`，避免负数恒占 10 字节 varint。
**位级浮点**：float/double 一律经 `*_to_bits`/`bits_to_*` 做位级搬运（不做数值运算），
保证 `wasm-gc`/`js`/`native` 三后端逐位一致，规避 js 后端「数字底层皆 double」的精度漂移。

## 与主流序列化方案对标（旗舰 R8.4）

| 维度 | 本库 | Protocol Buffers | Cap'n Proto | FlatBuffers | MessagePack |
|---|---|---|---|---|---|
| 模式依赖 | 是 | 是 | 是 | 是 | 否（自描述） |
| 零拷贝读取 | 否 | 否 | 是 | 是 | 否 |
| 编码紧凑度 | 高（varint+packed+默认省略） | 高 | 中 | 中 | 高 |
| 确定性编码 | 是（规范化 + 幂等） | 可选 | N/A | N/A | 否 |
| 文本互转 | 是（proto3 JSON） | 是 | 是 | 是 | 部分 |
| 未知字段保留 | 是 | 是 | 否 | 否 | N/A |

**核心取舍**：与 Protocol Buffers 同侧——以「需要 schema、非零拷贝」换取最紧凑的
varint/packed 编码、确定性序列化与稳健的模式演进（未知字段保留）。零拷贝读取
（Cap'n Proto / FlatBuffers 的核心卖点）不在本库目标内。

## 实现边界声明（旗舰 R8.5，显式而非隐式留白）

- **不支持 proto2 group（wire 3/4）**：已废弃，与既有 `WireType` 一致只支持 0/1/2/5。
- **不支持 extensions 与自定义 well-known types**（如 `Any`/`Timestamp` 的特殊 JSON 形态）：超出 proto3 核心范围。
- **不支持 import 跨文件解析**：`parse_proto_full` 跳过 `import` 语句（单文件模式），跨文件符号解析留待上层。
- **枚举 JSON 采用数值表示**：满足语义等价且无歧义（R5.1 列举的核心规则为 camelCase / 64 位为字符串 / bytes base64）。

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/serialization/README.mbt.md

# 三后端一致性（R11.1 / R9.9）：同一文档套件在三后端均须通过
moon test src/serialization/README.mbt.md --target wasm-gc
moon test src/serialization/README.mbt.md --target js
moon test src/serialization/README.mbt.md --target native
```

预期看到：

```
Total tests: 9, passed: 9, failed: 0.
```

（示例 1~9 的 9 段可执行测试全部通过。）一旦修改编解码实现使其输出与本文档的
`assert_*` 断言或字节快照不符，`moon test` 会立即报错并提示同步更新文档——这正是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
