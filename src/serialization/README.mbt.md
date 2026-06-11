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
      assert_eq(e.offset(), 0)
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
      assert_eq(e.offset(), 0)
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
  assert_eq(schema.messages.length(), 1)
  let pt = schema.messages[0]
  assert_eq(pt.name, "Pt")
  assert_true(pt.fields[0].ftype == FieldType::TInt32)
  assert_false(pt.fields[0].repeated)
  assert_true(pt.fields[1].ftype == FieldType::TString)
  assert_true(pt.fields[1].repeated) // repeated → Array[String]
  // 代码生成：repeated 字段映射为 Array[String]。
  let code = gen_moonbit(schema)
  let expected = "// 由 gen_moonbit 生成（骨架）—— 请勿手工编辑\n" +
    "\npub struct Pt {\n  x : Int\n  tags : Array[String]\n} derive(Eq, Show)\n"
  assert_true(code == expected)
}
```

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
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改编解码实现使其输出与本文档的
`assert_*` 断言或字节快照不符，`moon test` 会立即报错并提示同步更新文档——这正是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
