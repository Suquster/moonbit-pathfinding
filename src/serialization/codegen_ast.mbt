// codegen_ast.mbt —— 结构化代码生成 AST（旗舰深化，旁路新增，R4.3）。
//
// 设计依据（production-hardening/design.md §4.2「结构化代码生成 AST」）：
// 既有 `gen_moonbit_full`（codegen_full.mbt，冻结）以「循环内字符串 `+`」直接
// 拼接产出目标源码，难以保证缩进结构清晰且存在 O(n²) 拼接风险。本文件新增
// **结构化代码生成路径**：先以 `CodeNode` 表达目标代码的层次结构（行 / 块 /
// 缩进 / 序列），再由 `render_code` 借助共享高效缓冲 `@infra_text.TextBuilder`
// 一次性物化为源码字符串，**全程禁止循环内字符串 `+`**（R1.5 / R4.3）。
//
// 严格旁路扩展：不修改 `gen_moonbit_full` 等既有签名；`gen_moonbit_structured`
// 为新增 bypass 入口，语义与 `gen_moonbit_full` 相近（生成带字段的 `pub struct`
// 与配套委托编解码函数），但走结构化节点路径，缩进由 `render_code` 统一控制。

// ─────────────────────────────── 缩进默认值 ────────────────────────────────

///|
/// `render_code` 的默认缩进单元（两个空格）。
///
/// 命名常量，避免散落的 magic number；与既有 `gen_moonbit` / `gen_moonbit_full`
/// 生成代码所用的两空格缩进风格一致。调用方可经 `indent_unit?` 覆盖。
let default_indent_unit : String = "  "

// ──────────────────────────────── 代码节点 AST ─────────────────────────────

///|
/// 结构化代码节点：以层次结构表达待生成的目标源码。
///
///   * `CRaw(s)`    —— 原样片段，不加缩进、不追加换行（用于空行 / 内联拼接）；
///   * `CLine(s)`   —— 一行：当前缩进前缀 + 内容 + 换行；
///   * `CBlock`     —— 一个块：`header` 行、缩进一级的 `body`、再回到本级的
///                     `close` 行（如 `pub struct X {` … `} derive(...)`）；
///   * `CSeq(ns)`   —— 顺序拼接子节点（同一缩进层级）；
///   * `CIndent(n)` —— 将子节点整体再缩进一级。
pub enum CodeNode {
  CRaw(String)
  CLine(String)
  CBlock(header~ : String, body~ : Array[CodeNode], close~ : String)
  CSeq(Array[CodeNode])
  CIndent(CodeNode)
} derive(Eq, Debug)

// ──────────────────────────────── 渲染（物化） ─────────────────────────────

///|
/// 向缓冲追加 `level` 级缩进前缀（每级一个 `unit`）。
///
/// 仅向 `@infra_text.TextBuilder` 顺序 `push_str`，不在循环内做字符串 `+`，
/// 总代价对输出长度线性（R1.5）。`level <= 0` 时不追加任何内容。
fn push_indent(
  tb : @infra_text.TextBuilder,
  unit : String,
  level : Int,
) -> Unit {
  let mut i = 0
  while i < level {
    tb.push_str(unit)
    i += 1
  }
}

///|
/// 将单个节点渲染到缓冲（递归）。`level` 为当前缩进层级，`unit` 为缩进单元。
///
/// 缩进算法（R4.3）：
///   * `CRaw`    —— 原样输出，不加缩进、不换行；
///   * `CLine`   —— 输出「缩进前缀 + 内容 + 换行」；
///   * `CBlock`  —— 输出本级 `header` 行；`body` 各子节点在 `level + 1` 渲染；
///                  最后输出本级 `close` 行；
///   * `CSeq`    —— 在同一 `level` 顺序渲染各子节点；
///   * `CIndent` —— 子节点整体在 `level + 1` 渲染。
fn render_node(
  node : CodeNode,
  level : Int,
  unit : String,
  tb : @infra_text.TextBuilder,
) -> Unit {
  match node {
    CRaw(s) => tb.push_str(s)
    CLine(s) => {
      push_indent(tb, unit, level)
      tb.push_str(s)
      tb.push_char('\n')
    }
    CBlock(header~, body~, close~) => {
      push_indent(tb, unit, level)
      tb.push_str(header)
      tb.push_char('\n')
      for child in body {
        render_node(child, level + 1, unit, tb)
      }
      push_indent(tb, unit, level)
      tb.push_str(close)
      tb.push_char('\n')
    }
    CSeq(nodes) =>
      for child in nodes {
        render_node(child, level, unit, tb)
      }
    CIndent(inner) => render_node(inner, level + 1, unit, tb)
  }
}

///|
/// 将 `CodeNode` 物化为目标源码字符串（R4.3）。
///
/// 内部以共享高效缓冲 `@infra_text.TextBuilder` 顺序追加片段、最终一次性
/// `build`，**禁止循环内字符串 `+`**，对总输出长度线性。`indent_unit?` 缺省为
/// `default_indent_unit`（两个空格）。从缩进层级 0 起渲染根节点。
pub fn render_code(
  node : CodeNode,
  indent_unit? : String = default_indent_unit,
) -> String {
  let tb = @infra_text.TextBuilder::new()
  render_node(node, 0, indent_unit, tb)
  tb.build()
}

// ──────────────────────────── 由富模式构造代码节点 ──────────────────────────

///|
/// 由富模式构造结构化代码节点（R4.3）。
///
/// 语义与 `gen_moonbit_full` 相近：每个消息产出一个带字段的 `pub struct`
/// （`repeated` → `Array[元素类型]`、map → `Array[(K, V)]`，类型映射复用
/// `moonbit_full_type`），并附带 `<Name>_encode` / `<Name>_decode` 两个委托
/// `encode_typed` / `decode_typed` 的函数。差异在于：本路径通过 `CodeNode`
/// 表达层次结构，由 `render_code` 统一控制缩进与换行，而非直接字符串拼接。
pub fn gen_moonbit_ast(schema : ProtoSchema) -> CodeNode {
  let nodes : Array[CodeNode] = []
  // 文件头注释（两行）。
  nodes.push(
    CLine(
      "// 由 gen_moonbit_ast 生成（结构化路径）—— 请勿手工编辑",
    ),
  )
  nodes.push(
    CLine(
      "// 结构体提供类型化视图；编解码委托共享 encode_typed / decode_typed。",
    ),
  )
  for m in schema.messages {
    let sname = pg_simple_name(m.name)
    // 结构体定义块：字段行与 map 行作为缩进一级的 body。
    let struct_body : Array[CodeNode] = []
    for f in m.fields {
      let base = moonbit_full_type(f.ptype)
      let ty = match f.label {
        LRepeated(..) => "Array[\{base}]"
        _ => base
      }
      struct_body.push(CLine("\{f.name} : \{ty}"))
    }
    for mp in m.maps {
      let kty = moonbit_full_type(mp.key)
      let vty = moonbit_full_type(mp.value)
      struct_body.push(CLine("\{mp.name} : Array[(\{kty}, \{vty})]"))
    }
    // 结构体之间留一个空行，便于阅读（原样换行，不缩进）。
    nodes.push(CRaw("\n"))
    nodes.push(
      CBlock(
        header="pub struct \{sname} {",
        body=struct_body,
        close="} derive(Eq, Debug)",
      ),
    )
    // 配套编解码函数，委托共享类型化模型（与 gen_moonbit_full 一致语义）。
    nodes.push(CRaw("\n"))
    nodes.push(
      CBlock(
        header="pub fn \{sname}_encode(schema : ProtoSchema, msg : TypedMessage) -> Result[Bytes, DecodeError] {",
        body=[CLine("encode_typed(schema, \"\{m.name}\", msg)")],
        close="}",
      ),
    )
    nodes.push(CRaw("\n"))
    nodes.push(
      CBlock(
        header="pub fn \{sname}_decode(schema : ProtoSchema, bytes : Bytes) -> Result[TypedMessage, DecodeError] {",
        body=[CLine("decode_typed(schema, \"\{m.name}\", bytes)")],
        close="}",
      ),
    )
  }
  CSeq(nodes)
}

///|
/// 结构化代码生成入口（bypass）：`render_code(gen_moonbit_ast(schema))`。
///
/// 等价于 `gen_moonbit_full` 的「结构化路径」版本：产出可解释、缩进规整的
/// MoonBit 源码，全程经 `@infra_text.TextBuilder` 物化，无循环内字符串 `+`。
pub fn gen_moonbit_structured(schema : ProtoSchema) -> String {
  render_code(gen_moonbit_ast(schema))
}

// ──────────────────────────────── 内联烟雾测试 ─────────────────────────────
// 完整属性测试见任务 7.4；此处仅做最小冒烟，验证缩进算法与生成内容关键字。

///|
/// 烟雾：`render_code` 对 `CBlock` 正确缩进 body 一级，并处理 `CLine` / `CRaw`。
test "render_code 缩进算法冒烟" {
  let node = CBlock(
    header="pub struct P {",
    body=[CLine("x : Int"), CIndent(CLine("y : Int"))],
    close="} derive(Eq, Debug)",
  )
  // header 不缩进；body 第一行缩进一级；CIndent 再加一级（共两级）；close 回到本级。
  let expected =
    #|pub struct P {
    #|  x : Int
    #|    y : Int
    #|} derive(Eq, Debug)
    #|
  @test.assert_eq(render_code(node), expected)
}

///|
/// 烟雾：自定义缩进单元（四空格）按级生效。
test "render_code 自定义缩进单元冒烟" {
  let node = CBlock(header="a {", body=[CLine("b")], close="}")
  let expected =
    #|a {
    #|    b
    #|}
    #|
  @test.assert_eq(render_code(node, indent_unit="    "), expected)
}

///|
/// 烟雾：`gen_moonbit_structured` 非空且含预期关键字。
test "gen_moonbit_structured 生成关键字冒烟" {
  let schema : ProtoSchema = {
    messages: [
      {
        name: "Pt",
        fields: [
          { name: "x", number: 1, ptype: PInt32, label: LSingular, options: [] },
          {
            name: "tags",
            number: 2,
            ptype: PString,
            label: LRepeated(packed=false),
            options: [],
          },
        ],
        maps: [],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
  let code = gen_moonbit_structured(schema)
  assert_true(code.length() > 0)
  assert_true(code.contains("pub struct Pt {"))
  assert_true(code.contains("x : Int"))
  assert_true(code.contains("tags : Array[String]"))
  assert_true(code.contains("} derive(Eq, Debug)"))
  assert_true(code.contains("Pt_encode"))
  assert_true(code.contains("Pt_decode"))
}
