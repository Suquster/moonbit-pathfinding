// api_ext.mbt —— CharSet 二分查询与 Pattern 实用搜索 API（旗舰深化）。
//
// 对应 design.md「Regex 引擎增强设计 §5.2 / §5.4」（Requirement 5.2 / 5.5 /
// 5.6 / 5.7）。本文件为**纯新增（bypass）**：不改动任何既有公开签名，仅在
// 既有 `CharSet`（nfa.mbt，字段 `intervals` 为归一化、不相交、升序的闭区间
// 序列）与 `Pattern`（search.mbt，封装 Pike VM 程序与匹配策略）之上**只增**
// 方法。
//
// 新增 API 一览：
//   * `CharSet::contains_binary` —— 在已排序区间上二分查找判定码点成员关系，
//     结果与既有线性 `CharSet::contains` 完全一致（R5.6）；
//   * `Pattern::find_at`         —— 自指定起点 `k` 查找，仅返回 start ≥ k 的
//     首个匹配（R5.5 / R5.7）；
//   * `Pattern::split_n`         —— 限定份数切分（R5.5）；
//   * `Pattern::replace_fn`      —— 以回调计算替换文本，内部用 `TextBuilder`
//     物化，禁止循环内字符串 `+`（R5.5 / R1.5）。
//
// 反模式禁令：无 `abort()` / `todo!()` / `panic` 占位；无 magic number；
// 字符切片复用 search.mbt 的包内私有 `slice_chars`（同包可见）。

///|
/// 在 `CharSet` 的已排序区间数组上**二分查找**判定码点 `code` 的成员关系。
///
/// 前置不变量（由 nfa.mbt 的 `normalize_intervals` 保证）：`intervals` 为
/// 升序、互不相交的闭区间序列。故可对中点区间 `(a, b)` 三向比较：
///   * `code < a` —— 目标在左半区，收缩上界；
///   * `code > b` —— 目标在右半区，收缩下界；
///   * 否则 `a ≤ code ≤ b` —— 命中，返回 `true`。
///
/// 复杂度 O(log m)（m 为区间数），相对线性 `contains` 的 O(m) 在大字符集合
/// （如 Unicode 类别）上更优；二者判定结果对任意码点完全一致（R5.6）。
pub fn CharSet::contains_binary(self : CharSet, code : Int) -> Bool {
  let ivs = self.intervals
  let mut lo = 0
  let mut hi = ivs.length() - 1
  while lo <= hi {
    // 取中点（防溢出写法）。
    let mid = lo + (hi - lo) / 2
    let (a, b) = ivs[mid]
    if code < a {
      hi = mid - 1
    } else if code > b {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// 自起点 `k` 查找：仅返回整体起点 `start ≥ k` 的**首个**匹配；无此类匹配
/// 返回 `None`（R5.5 / R5.7）。
///
/// 复用既有 Pike VM 执行入口 `Program::exec` 的 `start` 锚定能力：自位置
/// `k` 起做最左扫描，返回的整体区间起点必不小于 `k`。边界处理：
///   * `k < 0`        —— 规约为自串首（位置 0）查找；
///   * `k > 输入长度` —— 不可能存在 start ≥ k 的匹配，直接返回 `None`。
pub fn Pattern::find_at(self : Pattern, input : String, k : Int) -> Match? {
  let n = input.iter().to_array().length()
  // 起点钳制到 [0, n]：负起点自串首，越界起点无匹配。
  let start = if k < 0 { 0 } else { k }
  if start > n {
    return None
  }
  match self.prog.exec(input, start~, kind=self.kind) {
    Some(caps) => caps.group(0)
    None => None
  }
}

///|
/// 以全部不重叠匹配为分隔符切分输入，**最多切成 `n` 份**（R5.5）。
///
/// 语义：自左向右累计分隔；当已产生 `n - 1` 个分隔（即将达到第 `n` 份）时
/// 停止继续切分，输入余下部分整体作为最后一份。
///
/// 边界约定：`n <= 0` 视为**不限份数**，等价于既有 `Pattern::split`（切分
/// 全部分隔）。`n == 1` 时不做任何切分，返回仅含原输入整串的单元素数组。
pub fn Pattern::split_n(
  self : Pattern,
  input : String,
  n : Int,
) -> Array[String] {
  let chars = input.iter().to_array()
  let total = chars.length()
  let matches = self.find_all(input)
  let out : Array[String] = []
  let mut last = 0
  let mut count = 0
  for m in matches {
    // n > 0 且已累计 n-1 个分隔：停止切分，余下作为最后一份。
    if n > 0 && count >= n - 1 {
      break
    }
    out.push(slice_chars(chars, last, m.start))
    last = m.end
    count = count + 1
  }
  out.push(slice_chars(chars, last, total))
  out
}

///|
/// 以回调 `f` 计算每个不重叠匹配的替换文本，非匹配区间原样保留（R5.5）。
///
/// 与既有 `replace_all`（用替换模板字符串）不同，本 API 把替换文本的计算
/// 完全交给调用方：对每个匹配 `m` 调用 `f(m)` 取得其替换串。物化以
/// `@infra_text.TextBuilder` 顺序追加片段、最终一次性 `build`，**禁止循环内
/// 字符串 `+`**，保证对总输出长度线性（R1.5 / R5.5）。
///
/// 扫描语义与 `replace_all` 一致：自左向右取不重叠匹配；空匹配（`start ==
/// end`）至少前进一字符以保证终止。
pub fn Pattern::replace_fn(
  self : Pattern,
  input : String,
  f : (Match) -> String,
) -> String {
  let chars = input.iter().to_array()
  let n = chars.length()
  let tb = @infra_text.TextBuilder::new()
  let mut pos = 0
  let mut last = 0
  while pos <= n {
    match self.prog.exec(input, start=pos, kind=self.kind) {
      None => break
      Some(caps) =>
        match caps.group(0) {
          None => break
          Some(m) => {
            // 非匹配前缀片段 + 回调计算的替换文本，均经 TextBuilder 物化。
            tb.push_str(slice_chars(chars, last, m.start))
            tb.push_str(f(m))
            last = m.end
            pos = if m.end > m.start { m.end } else { m.end + 1 }
          }
        }
    }
  }
  // 末尾残余的非匹配片段。
  tb.push_str(slice_chars(chars, last, n))
  tb.build()
}

///|
/// 内联烟雾测试：覆盖四个新增 API 的核心行为（属性测试见任务 5.4）。
test "api_ext smoke" {
  // ── contains_binary 与线性 contains 一致 ──
  let digits = predef_digit()
  for code in 0..<128 {
    assert_eq(digits.contains_binary(code), digits.contains(code))
  }
  // 多区间字符集合（Unicode 类别）上一致。
  let letters = category_charset(Lu).union(category_charset(Ll))
  assert_true(letters.contains_binary('A'.to_int()))
  assert_true(letters.contains_binary('z'.to_int()))
  assert_false(letters.contains_binary('5'.to_int()))
  assert_eq(
    letters.contains_binary('Z'.to_int()),
    letters.contains('Z'.to_int()),
  )

  // ── find_at：仅返回 start >= k 的首个匹配 ──
  let p = match Pattern::compile("a") {
    Ok(pat) => pat
    Err(_) => {
      assert_true(false)
      return
    }
  }
  // "abaca"：'a' 出现在 0,2,4。
  let s = "abaca"
  assert_true(p.find_at(s, 0) is Some({ start: 0, end: 1 }))
  assert_true(p.find_at(s, 1) is Some({ start: 2, end: 3 }))
  assert_true(p.find_at(s, 3) is Some({ start: 4, end: 5 }))
  // 起点越过最后一个匹配 → None。
  assert_true(p.find_at(s, 5) is None)
  // 起点越界 → None；负起点自串首。
  assert_true(p.find_at(s, 99) is None)
  assert_true(p.find_at(s, -3) is Some({ start: 0, end: 1 }))

  // ── split_n：限定份数 ──
  let comma = match Pattern::compile(",") {
    Ok(pat) => pat
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let csv = "a,b,c,d"
  // n=2：最多 2 份，第一刀后余下整体作为第二份。
  assert_true(comma.split_n(csv, 2) == ["a", "b,c,d"])
  // n=3：3 份。
  assert_true(comma.split_n(csv, 3) == ["a", "b", "c,d"])
  // n=1：不切分。
  assert_true(comma.split_n(csv, 1) == ["a,b,c,d"])
  // n<=0：不限份数，等价于 split（全部切分）。
  assert_true(comma.split_n(csv, 0) == ["a", "b", "c", "d"])
  assert_true(comma.split_n(csv, -1) == comma.split(csv))

  // ── replace_fn：回调计算替换文本 ──
  // 把每个 'a' 替换为其匹配长度的字符串 "1"，非匹配原样保留。
  let out = p.replace_fn(s, fn(m) { (m.end - m.start).to_string() })
  assert_eq(out, "1b1c1")
}
