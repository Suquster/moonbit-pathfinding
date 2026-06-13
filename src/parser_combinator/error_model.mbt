// error_model.mbt —— L0 错误模型：label / `<?>` 与最远失败（farthest-failure）
// 合并。
//
// 对应 tasks.md 任务 4.1，落地 design.md §「组件与接口 → 4. 错误模型」中锁定
// 的签名级接口。本文件引入一个**内部**最远失败累加器 `FarthestError`，并把它
// 用于既有 `alt`（任务 4.2，在 combinators.mbt 中精化）、`label` 与运行入口的
// 诊断生成。
//
// 论文出处（design.md §「算法说明与论文对照」）：消费提交语义与「最远失败 +
// 期望合并」错误模型、`<?>` 标注源自 Leijen & Meijer 的 Parsec 设计。
//
// 向后兼容说明（R14.2 / R5.5）：`normalize_expected` 采用**去重并保留首次出现
// 顺序**的确定性归一，而非字典序重排——这样既满足「同一输入重复解析产生逐
// 元素一致的期望序列」（R5.5 / Property 18 的确定性要求），又**不改变**既有
// `alt` 在 0.1.0 下「按分支顺序汇总期望」的可观察顺序（保持 README.mbt.md 与
// combinators_test.mbt 的既有断言不回归）。

///|
/// 内部最远失败累加器（farthest-failure accumulator）。
///
/// 不出现在公开 `ParseResult` 中，仅用于在 `alt` / 引擎层的择一逻辑里在多个
/// 失败分支之间归约：
///   * `pos` —— 当前记录到的最远失败位置（`offset` 最大者）；
///   * `expected` —— 落在该最远位置上去重合并后的期望符号集合。
priv struct FarthestError {
  pos : Pos
  expected : Array[String]
}

///|
/// 期望集合的确定性归一（normalize）：**去重**并**保留首次出现顺序**。
///
/// 满足 R5.5「同一输入的重复解析产生逐元素一致的期望序列」（确定性顺序）；
/// 选择「保留首次出现顺序」而非字典序排序，是为了不破坏既有 `alt` 在 0.1.0
/// 下「按分支顺序汇总期望」的可观察行为（向后兼容，R14.2）。
fn normalize_expected(xs : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for x in xs {
    let mut found = false
    for y in out {
      if y == x {
        found = true
        break
      }
    }
    if !found {
      out.push(x)
    }
  }
  out
}

///|
/// 合并两个失败诊断（farthest-failure merge）。
///
/// 取 `offset` 更大者（推进得更远的失败更贴近用户意图，R6.1）；当两者落在
/// **同一** `offset` 时，把各自的期望符号并集去重为单一集合（R6.2），并舍弃
/// 较早位置分支的期望（R6.3，由「取更大 offset」隐式完成）。期望顺序经
/// `normalize_expected` 归一以保证确定性（R5.5）。
fn merge_farthest(a : FarthestError, b : FarthestError) -> FarthestError {
  if b.pos.offset > a.pos.offset {
    b
  } else if a.pos.offset > b.pos.offset {
    a
  } else {
    let merged : Array[String] = []
    for x in a.expected {
      merged.push(x)
    }
    for x in b.expected {
      merged.push(x)
    }
    { pos: a.pos, expected: normalize_expected(merged) }
  }
}

///|
/// `label` / `<?>`：为解析器附加人类可读名称，改写其失败诊断的期望符号。
///
/// 语义（Parsec 的 `<?>`，位置敏感）：
///   * 当 `p` 在其**起始位置**失败（未消费任何字符）时，以 `name` **替换**
///     `p` 的期望符号集合，产出更友好的失败诊断（R5.2 / Property 17）；
///   * 当 `p` **已消费至少一个字符**后再失败时，保留 `p` **原始**的失败位置
///     与期望符号，而**不**以 `name` 覆盖——因为此时失败发生在更深处，原始
///     诊断更精确（R5.3 / Property 17）。
///   * 成功路径原样透传，不受影响。
pub fn[T] label(p : Parser[T], name : String) -> Parser[T] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Ok(v, rest) => ParseResult::Ok(v, rest)
      Fail(pos, expected~) =>
        if pos.offset == input.pos.offset {
          // 在起始位置失败（未消费）→ 用 name 替换期望集合。
          ParseResult::Fail(pos, expected=[name])
        } else {
          // 已消费 ≥1 字符后失败 → 保留原始位置与期望。
          ParseResult::Fail(pos, expected~)
        }
    }
  })
}

///|
/// `<?>` 运算符别名：`p <?> name` 等价于 `label(p, name)`（Parsec 习惯写法）。
///
/// 以中缀形式提供 `label`，便于在文法定义中就地为子解析器命名。
pub fn[T] op_as_label(p : Parser[T], name : String) -> Parser[T] {
  label(p, name)
}
