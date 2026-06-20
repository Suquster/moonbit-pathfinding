// regex_ext_prop_test.mbt —— Property 5：正则引擎增强一致性属性测试（任务 5.4）。
//
// 对应 design.md「Correctness Properties / Property 5: R5 正则一致性」：
//   * `is_match` 与 `find` 是否产出匹配一致（AC2）；
//   * `CharSet::contains_binary` 与线性 `CharSet::contains` 一致（AC6）；
//   * `HybridMatcher::find` 与 `Nfa::find` 一致（AC3 / AC4）；
//   * `Pattern::find_at(s, k)` 仅返回 start >= k 的匹配，且等于「自起点 k
//     之后首个匹配」（AC5 / AC7）。
//
// 本文件为**纯新增测试**：不改动任何既有源码签名与既有测试。四条属性各自
// 复用 @infra_pbt 的种子驱动随机源 `Rng` 与不变量模板 `holds_for_all`，每条
// 迭代 ≥100 次（此处统一取 128），并在三后端（wasm-gc / js / native）一致。
//
// 复用既有共享生成器（定义于同包 `_test.mbt`，黑盒测试期可见）：
//   * `gen_pat_input()`            —— `(合法模式串, 随机输入)`，模式不含锚点
//     与命名组（见 prop_match_kind_test.mbt），故可对子串做位移对照；
//   * `gen_regex_at(rng, depth)`   —— 受支持子集随机正则语法树；
//   * `gen_input_str(rng, maxlen)` —— 小字母表随机输入串。
//
// 反模式禁令：构造子串以 `Array[Char]` + `String::from_array` 物化，**禁止
// 循环内字符串 `+`**；全程中文注释。

// ---------------------------------------------------------------------------
// 本文件统一迭代次数（满足质量门禁 ≥100 迭代基线，留出余量）。
// ---------------------------------------------------------------------------

///|
/// 各属性的迭代次数（>= 100）。
let ext_iters : Int = 128

///|
/// 字符数组 `[a, b)` 切片为字符串（以 `String::from_array` 一次性物化，
/// 不在循环内做字符串 `+`）。越界端点钳制到合法范围。
fn rep_slice(chars : Array[Char], a : Int, b : Int) -> String {
  let lo = if a < 0 { 0 } else { a }
  let hi = if b > chars.length() { chars.length() } else { b }
  let sub : Array[Char] = []
  for k in lo..<hi {
    sub.push(chars[k])
  }
  String::from_array(sub)
}

// ===========================================================================
// Property 5.1：is_match 与 find 一致（AC2）
// ===========================================================================

///|
/// Feature: production-hardening, Property 5: is_match 与 find 是否产出匹配一致
///
/// 对任意合法模式 `pat` 与任意随机输入 `s`：编译后 `Pattern::is_match(s)` 的
/// 布尔判定，必与 `Pattern::find(s).is_some()`（find 是否产出匹配）完全一致。
/// 即「存在匹配」这一事实由两条独立代码路径（快速判定路径与最左搜索路径）
/// 给出相同结论。
///
/// 复用共享生成器 `gen_pat_input()`（模式恒被 `parse_pattern` 接受），迭代
/// 128 次（≥100）。
///
/// **Validates: Requirements 5.2**
test "Feature: production-hardening, Property 5: is_match agrees with find presence" {
  let ok = @infra_pbt.holds_for_all(
    gen_pat_input(),
    fn(pair) {
      let (pat, s) = pair
      match Pattern::compile(pat) {
        Err(_) => false // 共享生成器恒产合法模式；编译失败即测试失效
        Ok(p) => p.is_match(s) == (p.find(s) is Some(_))
      }
    },
    iters=ext_iters,
  )
  assert_true(ok)
}

// ===========================================================================
// Property 5.2：contains_binary 与线性 contains 一致（AC6）
// ===========================================================================

///|
/// 取某 Unicode 通用类别对应的 `CharSet`。
///
/// 黑盒测试期 `GeneralCategory` 的构造子不可见（其类型为 `pub` 而非
/// `pub(all)`），故经公开记法解析入口 `parse_unicode_class("\p{NAME}")`
/// 取得对应类别集合；不可识别名（理论上不会发生）兜底为数字类 `\d`。
fn ext_class(name : String) -> CharSet {
  match parse_unicode_class("\\p{\{name}}") {
    Some(cs) => cs
    None => predef_digit()
  }
}

///|
/// 随机 `CharSet` 生成器：先取一个基底字符集合（预定义类 \d / \w / \s 或
/// Unicode 通用类别），再随机叠加并集 / 取补集，以构造**多区间**集合，
/// 充分覆盖二分查找的各分支。所有产物经既有归一化原语保证「升序、不相交」
/// 不变量（二分查找的前置条件）。
fn ext_gen_charset(rng : @infra_pbt.Rng) -> CharSet {
  // 候选 Unicode 类别名（多区间，端点跨 BMP 多个区段）。
  let cats : Array[String] = ["Lu", "Ll", "Nd", "No", "Po", "Lo", "Zs", "Pd"]
  let base = match rng.next_below(8) {
    0 => predef_digit()
    1 => predef_word()
    2 => predef_space()
    3 => predef_non_digit()
    4 => predef_non_word()
    5 => ext_class(cats[rng.next_below(cats.length())])
    6 => ext_class("Lu").union(ext_class("Ll"))
    _ => ext_class("Nd").union(ext_class("Po"))
  }
  // 随机后处理：保持原样 / 并入另一类别 / 取补集（补集产生大量区间）。
  match rng.next_below(3) {
    0 => base
    1 => base.union(ext_class(cats[rng.next_below(cats.length())]))
    _ => base.complement()
  }
}

///|
/// 联合生成器：`(随机 CharSet, 随机码点)`。码点范围 [0, 0xA000) 覆盖
/// ASCII、拉丁补充、希腊 / 西里尔、标点、CJK 等多区段，使命中 / 未命中
/// 两种情形与各区间边界都被充分采样。
fn ext_gen_charset_code() -> @infra_pbt.Gen[(CharSet, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let cs = ext_gen_charset(rng)
    let code = rng.next_range(0, 0xA000)
    (cs, code)
  })
}

///|
/// Feature: production-hardening, Property 5: contains_binary 与线性 contains 一致
///
/// 对任意随机构造的 `CharSet`（含预定义类、Unicode 类别、并集与补集所得的
/// 多区间集合）与任意码点 `c`：二分查找成员判定 `contains_binary(c)` 必与
/// 线性扫描判定 `contains(c)` 完全相等。即性能优化的二分实现与朴素实现在
/// 全码点空间上语义等价。
///
/// 迭代 128 次（≥100）。
///
/// **Validates: Requirements 5.6**
test "Feature: production-hardening, Property 5: contains_binary equals linear contains" {
  let ok = @infra_pbt.holds_for_all(
    ext_gen_charset_code(),
    fn(pair) {
      let (cs, code) = pair
      cs.contains_binary(code) == cs.contains(code)
    },
    iters=ext_iters,
  )
  assert_true(ok)
}

// ===========================================================================
// Property 5.3：HybridMatcher 与 NFA 一致（AC3 / AC4）
// ===========================================================================

///|
/// 联合生成器：`(随机正则语法树, 随机输入, 随机缓存容量)`。
///
/// 缓存容量取自 [0, 8)，刻意偏小（含 0 = 纯 NFA 路径、1 / 2 = 极小容量），
/// 以高频触发「惰性 DFA 缓存耗尽 → NFA 回退」的切换路径；正则深度上限 3、
/// 输入长度上限 6，保证规模有界且匹配 / 不匹配情形覆盖充分。
fn ext_gen_regex_input_cap() -> @infra_pbt.Gen[(Regex, String, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let r = gen_regex_at(rng, 3)
    let s = gen_input_str(rng, 6)
    let cap = rng.next_below(8)
    (r, s, cap)
  })
}

///|
/// Feature: production-hardening, Property 5: HybridMatcher find equals NFA find
///
/// 对任意受支持子集正则、任意随机输入与任意缓存容量 `cap`（含极小容量触发
/// NFA 回退）：混合匹配器 `HybridMatcher::find` 必与 `Nfa::find` 给出逐字段
/// 相等的 `Match?`（是否匹配与匹配区间均相同）。即无论走惰性 DFA 缓存路径
/// 还是容量耗尽后的 NFA 回退路径，最左最长匹配语义恒定不变。
///
/// 迭代 128 次（≥100）。
///
/// **Validates: Requirements 5.3, 5.4**
test "Feature: production-hardening, Property 5: HybridMatcher agrees with NFA under any cap" {
  let ok = @infra_pbt.holds_for_all(
    ext_gen_regex_input_cap(),
    fn(triple) {
      let (r, s, cap) = triple
      let nfa = build_nfa(r)
      let hybrid = HybridMatcher::new(nfa, cap~)
      hybrid.find(s) == nfa.find(s)
    },
    iters=ext_iters,
  )
  assert_true(ok)
}

// ===========================================================================
// Property 5.4：find_at(k) 起点约束（AC5 / AC7）
// ===========================================================================

///|
/// 联合生成器：`(合法模式, 随机输入, 随机起点 k)`。
///
/// 起点 `k` 取 [-2, len+2]，覆盖负起点（钳制到串首）、串内各位置、串尾与
/// 越界三类边界。模式来自 `gen_pat_input` 的共享生成器：**不含锚点与命名
/// 组**，故 `find_at(s, k)` 与「在子串 s[k:] 上 find 再整体右移 k」等价，
/// 可作为独立对照（锚点会破坏该子串位移等价性，故生成器刻意排除）。
fn ext_gen_pat_input_k() -> @infra_pbt.Gen[(String, String, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let (pat, s) = gen_pat_input().generate(rng)
    let n = s.iter().to_array().length()
    let k = rng.next_range(-2, n + 2)
    (pat, s, k)
  })
}

///|
/// Feature: production-hardening, Property 5: find_at honors start bound and locates first match
///
/// 对任意（无锚点）合法模式、任意随机输入与任意起点 `k`：
///   1. 若 `find_at(s, k)` 返回 `Some(m)`，则 `m.start >= k`（起点约束）；
///   2. `find_at(s, k)` 等于「自起点 k 之后的首个匹配」——以独立对照刻画：
///      在子串 `s[max(0,k):]` 上调用既有 `Pattern::find`，将其匹配区间整体
///      右移 `max(0,k)`，二者必逐字段相等；
///   3. 起点越过串尾（`k > len`）时 `find_at` 必返回 `None`。
///
/// 子串位移对照是与 `find_at` 内部 `start` 锚定相互独立的语义刻画：`find`
/// 始终自子串首做最左搜索，对无锚点（位置无关）模式即等价于「在全串上限定
/// 起点不早于 k 的最左匹配」。
///
/// 迭代 128 次（≥100）。
///
/// **Validates: Requirements 5.5, 5.7**
test "Feature: production-hardening, Property 5: find_at start bound and first-match equivalence" {
  let ok = @infra_pbt.holds_for_all(
    ext_gen_pat_input_k(),
    fn(triple) {
      let (pat, s, k) = triple
      match Pattern::compile(pat) {
        Err(_) => false // 共享生成器恒产合法模式
        Ok(p) => {
          let chars = s.iter().to_array()
          let n = chars.length()
          let fa = p.find_at(s, k)
          // (1) 起点约束：返回匹配的 start 不早于 k。
          let bound_ok = match fa {
            Some(m) => m.start >= k
            None => true
          }
          // (3) 越界起点（k > n）必无匹配。
          if k > n {
            return bound_ok && fa is None
          }
          // (2) 子串位移对照：keff = max(0, k)。
          let keff = if k < 0 { 0 } else { k }
          let suffix = rep_slice(chars, keff, n)
          let expected : Match? = match p.find(suffix) {
            Some(m) => Some({ start: m.start + keff, end: m.end + keff })
            None => None
          }
          bound_ok && fa == expected
        }
      }
    },
    iters=ext_iters,
  )
  assert_true(ok)
}

// ===========================================================================
// 代表性见证（单元测试）—— 锁定四条属性在具体样例上的成立
// ===========================================================================

///|
/// 四条属性的代表性见证：在固定样例上复核增强 API 与基线实现一致。
test "regex ext properties representative witnesses" {
  // 5.1 is_match 与 find 一致。
  match Pattern::compile("a(b|c)*d") {
    Ok(p) => {
      assert_eq(p.is_match("abcbcd"), p.find("abcbcd") is Some(_))
      assert_eq(p.is_match("xyz"), p.find("xyz") is Some(_))
    }
    Err(_) => fail("compile failed for a(b|c)*d")
  }

  // 5.2 contains_binary 与 contains 一致（多区间集合，含补集）。
  let cs = ext_class("Lu").union(ext_class("Nd")).complement()
  for code in [0, 0x41, 0x5A, 0x30, 0x39, 0x61, 0x4E00, 0x3000] {
    assert_eq(cs.contains_binary(code), cs.contains(code))
  }

  // 5.3 Hybrid 与 NFA 一致（极小容量触发回退）。
  match parse_regex("a(b|c)*d") {
    Ok(r) => {
      let nfa = build_nfa(r)
      for cap in [0, 1, 2, 64] {
        let h = HybridMatcher::new(nfa, cap~)
        assert_true(h.find("abcbcd") == nfa.find("abcbcd"))
        assert_true(h.find("ad") == nfa.find("ad"))
        assert_true(h.find("xyz") == nfa.find("xyz"))
      }
    }
    Err(_) => fail("parse failed for a(b|c)*d")
  }

  // 5.4 find_at 起点约束与子串位移对照。
  match Pattern::compile("a") {
    Ok(p) => {
      let s = "abaca"
      // 'a' 出现在 0,2,4。
      assert_true(p.find_at(s, 1) is Some({ start: 2, end: 3 }))
      // 子串位移对照：从 k=1 起，s[1:]="baca" 上 find 'a' 在子串位 1 → 全串位 2。
      let chars = s.iter().to_array()
      let suffix = rep_slice(chars, 1, chars.length())
      let expected : Match? = match p.find(suffix) {
        Some(m) => Some({ start: m.start + 1, end: m.end + 1 })
        None => None
      }
      assert_true(p.find_at(s, 1) == expected)
      // 越界起点无匹配。
      assert_true(p.find_at(s, 99) is None)
    }
    Err(_) => fail("compile failed for a")
  }
}
