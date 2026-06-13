// combinators.mbt —— 解析器组合子（combinators）与回溯控制（backtracking）。
//
// 对应任务 5.2，构建于任务 5.1 的核心类型（`Parser[T]` / `ParseResult[T]` /
// `Input` / `Pos`）与基础原语（`pchar` / `satisfy` / `any_char` / `ptoken`）之上。
//
// design.md §「方向四：Parser_Combinator」组合子签名：
//   pub fn seq[A, B](a : Parser[A], b : Parser[B]) -> Parser[(A, B)]
//   pub fn alt[T](ps : Array[Parser[T]]) -> Parser[T]   // 择一，失败回溯到分支起点
//   pub fn many[T](p : Parser[T]) -> Parser[Array[T]]
//   pub fn many1[T](p : Parser[T]) -> Parser[Array[T]]
//   pub fn optional[T](p : Parser[T]) -> Parser[T?]
//
// 回溯（backtracking）契约（R4.4）：得益于 `Input` 的不可变游标设计，每个
// 择一分支都从**同一个**起始 `Input` 重新运行；某分支失败（即便其内部已部分
// 推进游标）只会丢弃该分支产生的新 `Input`，绝不影响后续分支或外层调用——
// 因此 `alt` / `optional` 天然"失败时回溯到分支起始位置且不消费输入"（R4.3）。

///|
/// 序列组合（sequence）：先运行 `a`，成功后在其剩余输入上运行 `b`。
///
/// 两者均成功时产出二元组 `(va, vb)` 并携带 `b` 之后的剩余输入（R4.2）；
/// 任一子解析器失败则原样传播其失败位置与期望符号（R4.3）。注意 `b` 在
/// `a` 之后的位置运行，故 `seq` 自身不做回溯——回溯语义由 `alt` 在分支层提供。
pub fn[A, B] seq(a : Parser[A], b : Parser[B]) -> Parser[(A, B)] {
  Parser::new(fn(input) {
    match a.parse(input) {
      Ok(va, rest1) =>
        match b.parse(rest1) {
          Ok(vb, rest2) => ParseResult::Ok((va, vb), rest2)
          Fail(pos, expected~) => ParseResult::Fail(pos, expected~)
        }
      Fail(pos, expected~) => ParseResult::Fail(pos, expected~)
    }
  })
}

///|
/// 择一组合（alternative）：按顺序尝试 `ps` 中的每个解析器，返回首个成功结果。
///
/// 回溯（R4.4）：每个分支都从**同一**起始 `Input` 运行，因此前一分支即便消费了
/// 部分输入也会被丢弃，下一分支从分支起点重新开始。
///
/// 失败诊断精化（farthest-failure，R6.1~R6.3）：全部分支失败时，不再朴素拼接
/// 所有分支的期望符号，而是用 `merge_farthest` 在分支间归约——报告 `offset`
/// **最远**的失败位置，仅合并落在该最远位置上的分支期望（去重并保留首次出现
/// 顺序），舍弃较早位置分支的期望。
///
/// 向后兼容（R14.2）：签名与成功路径行为零变更；当全部分支在**同一**位置
/// （如 0.1.0 既有用例中皆于分支起点）失败时，本精化退化为「按分支顺序去重
/// 汇总期望」，与既有可观察行为一致。唯一的可观察精化是：当各分支推进到不同
/// 位置时，失败位置由「分支起点」精化为「最远失败点」（严格信息增益）。
pub fn[T] alt(ps : Array[Parser[T]]) -> Parser[T] {
  Parser::new(fn(input) {
    let mut acc : FarthestError? = None
    for p in ps {
      match p.parse(input) {
        Ok(v, rest) => return ParseResult::Ok(v, rest)
        Fail(pos, expected~) => {
          let here : FarthestError = { pos, expected }
          acc = match acc {
            None => Some(here)
            Some(prev) => Some(merge_farthest(prev, here))
          }
        }
      }
    }
    match acc {
      Some(fe) => ParseResult::Fail(fe.pos, expected=normalize_expected(fe.expected))
      // 空分支列表：在起始位置失败且无期望符号（退化边界）。
      None => ParseResult::Fail(input.pos, expected=[])
    }
  })
}

///|
/// 重复零次或多次（many / Kleene star）：尽可能多地重复应用 `p`，收集全部产出。
///
/// 永不失败：`p` 首次失败时停止，返回已收集结果与最后一次失败前的剩余输入
/// （零次成功则返回空数组）。为避免"成功但不消费输入"的解析器导致死循环，
/// 当某次成功未推进游标时收下该次产出后立即停止。
pub fn[T] many(p : Parser[T]) -> Parser[Array[T]] {
  Parser::new(fn(input) {
    let acc : Array[T] = []
    let mut cur = input
    while true {
      match p.parse(cur) {
        Ok(v, rest) => {
          acc.push(v)
          // 防御：成功但未推进游标 → 收下一次后停止，避免无限循环。
          if rest.pos.offset == cur.pos.offset {
            break
          }
          cur = rest
        }
        Fail(_, ..) => break
      }
    }
    ParseResult::Ok(acc, cur)
  })
}

///|
/// 重复一次或多次（many1 / Kleene plus）：要求 `p` 至少成功一次。
///
/// 首次应用即失败时传播该失败（R4.3）；否则收集首个产出后继续以 `many` 的
/// 语义重复收集，返回非空结果数组。
pub fn[T] many1(p : Parser[T]) -> Parser[Array[T]] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Fail(pos, expected~) => ParseResult::Fail(pos, expected~)
      Ok(first, rest0) => {
        let acc : Array[T] = [first]
        let mut cur = rest0
        // 首次成功未推进游标 → 直接返回，避免无限循环。
        if rest0.pos.offset == input.pos.offset {
          return ParseResult::Ok(acc, cur)
        }
        while true {
          match p.parse(cur) {
            Ok(v, rest) => {
              acc.push(v)
              if rest.pos.offset == cur.pos.offset {
                break
              }
              cur = rest
            }
            Fail(_, ..) => break
          }
        }
        ParseResult::Ok(acc, cur)
      }
    }
  })
}

///|
/// 可选（optional）：尝试运行 `p`，成功则产出 `Some(v)` 并消费输入；
/// 失败则回溯到起始位置、产出 `None` 且不消费输入（R4.3 / R4.4）。永不失败。
pub fn[T] optional(p : Parser[T]) -> Parser[T?] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Ok(v, rest) => ParseResult::Ok(Some(v), rest)
      Fail(_, ..) => ParseResult::Ok(None, input)
    }
  })
}
