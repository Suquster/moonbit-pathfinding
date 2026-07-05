// prop_ac_prefilter_test.mbt —— Aho-Corasick 多模字面量预过滤差分一致性（T2.2）。
//
// Feature: regex-engine, Property: AC literal prefilter correctness invariant
//
// T2.2 预过滤（必经字面量前缀集 + AC 多模扫描）与 T2.1 首字符集预过滤共享同一
// 安全契约：只允许跳过绝不可能成为匹配起点的位置，**不得改变任何匹配语义**。
// 本文件以差分属性 + 代表性见证守护该不变量，并对 `AcAutomaton` 本体做
// 与朴素多模扫描的逐位对拍。
//
// **Validates: Requirements 2.6, 7.4, 7.5, 8.1, 8.2**

///|
/// AC 自动机本体对拍：`next_candidate` 返回的候选起点 c 满足
///   （安全）[pos, c) 内不存在任何模式出现的起点；
///   （对拍）与朴素 O(n·m) 多模扫描得到的「首个出现起点」一致地保守——
///     c <= 首个出现起点（若存在），否则 c == n 当且仅当无出现终点。
test "AcAutomaton next_candidate agrees with naive multi-pattern scan" {
  let cases : Array[(Array[String], String)] = [
    (["error", "warn", "fatal"], "info info warn debug error trace"),
    (["ab", "abc", "bc"], "zzabczz"),
    (["aa", "aaa"], "aaaa"),
    (["he", "she", "his", "hers"], "ushers"),
    (["xyz"], "no hits at all here"),
    (["a"], ""),
    (["abab", "bab"], "abababab"),
  ]
  for c in cases {
    let (pats_s, input) = c
    let pats : Array[Array[Char]] = []
    for p in pats_s {
      pats.push(p.iter().to_array())
    }
    let ac = AcAutomaton::build(pats)
    let chars = input.iter().to_array()
    let n = chars.length()
    // 朴素扫描：首个模式出现的最小起点（无出现为 n）。
    let mut naive = n
    for s in 0..<n {
      let mut hit = false
      for p in pats {
        let m = p.length()
        if s + m <= n {
          let mut eq = true
          for k in 0..<m {
            if chars[s + k] != p[k] {
              eq = false
              break
            }
          }
          if eq {
            hit = true
          }
        }
      }
      if hit {
        naive = s
        break
      }
    }
    for pos in 0..<=n {
      let cand = ac.next_candidate(chars, n, pos)
      // 安全：候选不得越过任何真实出现起点。
      if naive >= pos {
        assert_true(cand <= naive)
      }
      // 无出现 => 必须返回 n（允许上层提前终止）。
      if naive == n || naive < pos {
        // naive < pos 时 [pos,n) 可能仍有出现，单独重算。
        let mut naive2 = n
        for s in pos..<n {
          let mut hit = false
          for p in pats {
            let m = p.length()
            if s + m <= n {
              let mut eq = true
              for k in 0..<m {
                if chars[s + k] != p[k] {
                  eq = false
                  break
                }
              }
              if eq {
                hit = true
              }
            }
          }
          if hit {
            naive2 = s
            break
          }
        }
        assert_true(cand <= naive2)
        if naive2 == n {
          assert_eq(cand, n)
        }
      }
      assert_true(cand >= pos)
    }
  }
}

///|
/// 编译期策略见证：多分支字面量选择 / 长字面量前缀应选中 `PfLiterals`；
/// 单字符前缀 / 忽略大小写 / 无必经字面量应回退到既有策略。
test "compute_prefilter selects PfLiterals exactly when applicable" {
  let flags = Flags::default()
  // 顶层选择、每支非空字面量前缀 => PfLiterals。
  let alt : Ast = Alt([
    Concat([Lit('c'), Lit('a'), Lit('t')]),
    Concat([Lit('d'), Lit('o'), Lit('g')]),
  ])
  assert_true(compute_prefilter(alt, flags) is PfLiterals(_))
  // 长字面量前缀（如 `error[0-9]+`）=> PfLiterals。
  let prefixed : Ast = Concat([
    Lit('e'),
    Lit('r'),
    Lit('r'),
    Repeat(
      node=Set({ intervals: [('0'.to_int(), '9'.to_int())] }),
      min=1,
      max=None,
      greedy=true,
    ),
  ])
  assert_true(compute_prefilter(prefixed, flags) is PfLiterals(_))
  // 定量重复完整字面（`a{3}b`）：展开为 "aaab" 前缀 => PfLiterals。
  let quant : Ast = Concat([
    Repeat(node=Lit('a'), min=3, max=Some(3), greedy=true),
    Lit('b'),
  ])
  assert_true(compute_prefilter(quant, flags) is PfLiterals(_))
  // 单字符前缀 => 回退首字符集（AC 无增益）。
  let single : Ast = Concat([
    Lit('a'),
    Repeat(node=Lit('b'), min=0, max=None, greedy=true),
  ])
  assert_true(compute_prefilter(single, flags) is PfFirstSet(_))
  // 某分支无字面量前缀 => 回退首字符集。
  let mixed : Ast = Alt([
    Concat([Lit('a'), Lit('b')]),
    Set({ intervals: [('z'.to_int(), 'z'.to_int())] }),
  ])
  assert_true(compute_prefilter(mixed, flags) is PfFirstSet(_))
  // 忽略大小写 => 保守回退首字符集（其 case_fold 已被属性测试守护）。
  let ci = { ..Flags::default(), ignore_case: true }
  assert_true(compute_prefilter(alt, ci) is PfFirstSet(_))
  // 可空 => PfNone（不受 T2.2 影响）。
  let nullable : Ast = Repeat(node=Lit('a'), min=0, max=None, greedy=true)
  assert_true(compute_prefilter(nullable, flags) is PfNone)
}

///|
/// Pattern 级差分（PBT）：随机正则 × 随机输入下，开/关预过滤（现在可能选中
/// AC 路径）在 `find` / `find_all` / `is_match` 上完全一致。
///
/// **Validates: Requirements 8.1, 8.2**
test "Feature: regex-engine, Property: AC prefilter preserves search semantics" {
  let ok = @infra_pbt.holds_for_all(
    gen_prefilter_case(),
    fn(pair) {
      let (r, s) = pair
      match Pattern::compile(print_regex(r)) {
        Err(_) => true
        Ok(pat) => {
          let off = pat.without_prefilter()
          pat.find(s) == off.find(s) &&
          pat.find_all(s) == off.find_all(s) &&
          pat.is_match(s) == off.is_match(s)
        }
      }
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// 代表性见证：AC 预过滤主战场（多关键字稀疏命中长文本）与关键边界
/// （重叠模式、前后缀关系、量词展开、锚点、无命中提前终止）。
test "AC prefilter representative witnesses agree with no-prefilter" {
  let cases : Array[(String, String)] = [
    // 多关键字日志扫描（T2.2 主战场）。
    ("error|warn|fatal", "info info info warn debug error trace fatal"),
    ("cat|dog|bird", "the lazy dog jumped over the bird"),
    // 模式互为前后缀（AC 失配链 / 输出传播关键路径）。
    ("he|she|his|hers", "ushers say hers"),
    ("ab|abc|bc", "zzabczz"),
    ("aa|aaa", "aaaaaa"),
    // 长字面量前缀 + 变长尾部。
    ("error[0-9]+", "xx error7 yy error42"),
    ("foo(bar|baz)", "xxfoobazxx"),
    // 定量重复展开。
    ("a{3}b", "zzaaab aab aaab"),
    // 锚点前导（零宽）。
    ("^(foo|bar)", "barfly"),
    // 全程无命中：应快速返回无匹配。
    ("needle|pin", "haystack haystack haystack"),
    // 空输入。
    ("ab|cd", ""),
  ]
  for c in cases {
    let (pat_s, input) = c
    let pat = match Pattern::compile(pat_s) {
      Ok(p) => p
      Err(_) => abort("unexpected parse error: " + pat_s)
    }
    let off = pat.without_prefilter()
    assert_true(pat.find(input) == off.find(input))
    assert_true(pat.find_all(input) == off.find_all(input))
    assert_true(pat.is_match(input) == off.is_match(input))
  }
}
