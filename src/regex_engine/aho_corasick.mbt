// aho_corasick.mbt —— Aho-Corasick 多模式字符串自动机（T2.2 预过滤基座）。
//
// 对标 Rust `regex` 生态的 `aho-corasick` crate：当正则的每个候选分支都存在
// **必经字面量前缀**（如 `error|warn|fatal`）时，可用一台 AC 自动机对输入做
// **单遍**多模式扫描，直接跳到「下一个可能的匹配起点」附近，替代逐字符的
// 首字符集试探。本文件为**新增**，不改任何既有公开 API。
//
// paper-to-code：Aho & Corasick, "Efficient String Matching: An Aid to
// Bibliographic Search", CACM 1975。构造 = 模式 trie（goto 函数）+ BFS 失配
// 链接（failure 函数）+ 输出集经失配链传播；扫描对每个输入字符沿失配链回退
// 至多 O(深度) 次，整体摊还 O(n + Σ|pattern|)。
//
// 预过滤安全性（与 `prefilter.mbt` 的超集不变量衔接）：
//   * 每个模式都是「任何匹配必以其中之一开头」的**必经前缀**；
//   * `next_candidate` 返回的保守候选 `first_end - max_len + 1` 满足：任何
//     实际匹配起点 q ≥ pos 对应的前缀出现终点 e = q + len - 1 ≥ first_end，
//     故 q = e - len + 1 ≥ first_end - max_len + 1 —— 绝不跳过合法起点。

///|
/// Aho-Corasick 自动机（不可变，构造后仅用于扫描）。
///
///   * `children` —— 每个节点的 goto 边表：`(码点, 子节点 id)` 线性表
///     （模式集通常很小，线性查找常数优于哈希）；
///   * `fail`     —— BFS 失配链接（根为 0）；
///   * `out`      —— 节点是否终结某个模式（含经失配链传播的输出）；
///   * `max_len`  —— 最长模式长度（用于保守候选回推）。
pub struct AcAutomaton {
  children : Array[Array[(Int, Int)]]
  fail : Array[Int]
  out : Array[Bool]
  max_len : Int
} derive(Eq)

///|
/// 在节点边表中查找码点 `code` 的 goto 边；无边返回 -1。
fn ac_child(edges : Array[(Int, Int)], code : Int) -> Int {
  for e in edges {
    let (c, v) = e
    if c == code {
      return v
    }
  }
  -1
}

///|
/// 由非空模式集构造自动机：先建 trie，再 BFS 计算失配链接并沿链传播输出集。
/// 调用方保证 `patterns` 非空且每个模式非空（`prefilter.mbt` 的提取器负责）。
pub fn AcAutomaton::build(patterns : Array[Array[Char]]) -> AcAutomaton {
  let children : Array[Array[(Int, Int)]] = [[]]
  let fail : Array[Int] = [0]
  let out : Array[Bool] = [false]
  let mut max_len = 0
  for p in patterns {
    if p.length() > max_len {
      max_len = p.length()
    }
    let mut cur = 0
    for ch in p {
      let code = ch.to_int()
      let nxt = ac_child(children[cur], code)
      if nxt >= 0 {
        cur = nxt
      } else {
        let id = children.length()
        children[cur].push((code, id))
        children.push([])
        fail.push(0)
        out.push(false)
        cur = id
      }
    }
    out[cur] = true
  }
  // BFS 失配链接：深度 1 节点失配到根；更深节点沿父失配链找最长真后缀。
  let queue : Array[Int] = []
  for e in children[0] {
    let (_, v) = e
    queue.push(v)
  }
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head = head + 1
    for e in children[u] {
      let (code, v) = e
      let mut f = fail[u]
      while f != 0 && ac_child(children[f], code) < 0 {
        f = fail[f]
      }
      let cand = ac_child(children[f], code)
      fail[v] = if cand >= 0 && cand != v { cand } else { 0 }
      // 输出集传播：v 的最长真后缀若终结某模式，则 v 处也「看见」该模式。
      if out[fail[v]] {
        out[v] = true
      }
      queue.push(v)
    }
  }
  { children, fail, out, max_len }
}

///|
/// 自 `pos` 起单遍扫描，返回首个「可能的匹配起点」（保守候选，≥ pos）；
/// 无任何模式出现时返回 `n`（其后不可能再有匹配起点）。
///
/// 保守回推：AC 在终点处报告出现；首个出现终点为 `i` 时，任何起点 ≥ pos 的
/// 出现其终点必 ≥ i，故起点必 ≥ `i - max_len + 1`——取其与 `pos` 的较大者。
pub fn AcAutomaton::next_candidate(
  self : AcAutomaton,
  chars : Array[Char],
  n : Int,
  pos : Int,
) -> Int {
  let mut state = 0
  let mut i = pos
  while i < n {
    let code = chars[i].to_int()
    let mut s = state
    while s != 0 && ac_child(self.children[s], code) < 0 {
      s = self.fail[s]
    }
    let nxt = ac_child(self.children[s], code)
    state = if nxt >= 0 { nxt } else { 0 }
    if self.out[state] {
      let cand = i - self.max_len + 1
      return if cand < pos { pos } else { cand }
    }
    i = i + 1
  }
  n
}
