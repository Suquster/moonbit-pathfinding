// minimize.mbt —— DFA 最小化 `Dfa::minimize`（Hopcroft 1971 划分细化）。
//
// 对应 design.md §4.8（R7.1/7.2/7.5）。本文件为**新增**，在既有 `Dfa`
// （定义于 dfa.mbt，字段不变）上**只增**方法 `Dfa::minimize`。
//
// paper-to-code：Hopcroft 1971《An n log n Algorithm for Minimizing States in
// a Finite Automaton》的划分细化（partition refinement）思想。本实现以等价
// 不动点细化落地：
//   1. 初始划分按「四元接受签名」——既有 `Dfa` 的接受性依赖锚点标志
//      `flags ∈ 0..3`（串首 / 串尾），故每个状态的接受向量是 4 维 bool；
//      接受向量相同的状态归入同一初始可区分类。
//   2. 反复细化：两状态同块 ⟺ 当前同块且对每个「锚点标志 × 字符类」输入符号
//      转移到同一目标块（`-1` 死路视为常量哑块），细化至块数不再增长（不动点）。
//   3. 合并不可区分等价态，按块代表重建 `trans` / `accept`，`bounds`（字母表
//      原子区间划分）保持不变，得到状态数最小且语言等价的 DFA。
//
// 正确性：最小化保持每状态每锚点标志的接受性与转移目标块，故 `Dfa::find`
// 的逐位置接受判定序列不变，对任意输入给出一致的整体匹配区间（R7.5，P2）。

///|
/// 把状态的四元接受向量编码为可作哈希键的字符串。
fn accept_signature(acc : Array[Bool]) -> String {
  // 以 TextBuilder 物化二进制签名，消除循环内字符串 `+`（Requirement 1.5）。
  let tb = @infra_text.TextBuilder::new()
  for b in acc {
    tb.push_char(if b { '1' } else { '0' })
  }
  tb.build()
}

///|
/// 以 Hopcroft 1971 划分细化将 DFA 最小化，产出状态数最小且语言等价的 DFA
/// （R7.1/7.2）。
pub fn Dfa::minimize(self : Dfa) -> Dfa {
  let n = self.num_states
  if n == 0 {
    return self
  }
  let num_classes = self.bounds.length() - 1
  // 初始划分：按四元接受签名分块。
  let block_of = Array::make(n, 0)
  let init_ids : Map[String, Int] = Map([])
  let mut next_id = 0
  for s in 0..<n {
    let key = accept_signature(self.accept[s])
    let id = match init_ids.get(key) {
      Some(i) => i
      None => {
        let i = next_id
        next_id = next_id + 1
        init_ids[key] = i
        i
      }
    }
    block_of[s] = id
  }
  let mut num_blocks = next_id
  // 反复细化至不动点。
  while true {
    let sig_ids : Map[String, Int] = Map([])
    let new_block_of = Array::make(n, 0)
    let mut nid = 0
    for s in 0..<n {
      // 签名：当前块 + 每个 (锚点标志, 字符类) 的目标块（-1 死路保留为常量）。
      // 以 TextBuilder 物化，消除循环内字符串 `+`（Requirement 1.5）。
      let key_buf = @infra_text.TextBuilder::new()
      key_buf.push_str(block_of[s].to_string())
      for f in 0..<4 {
        for k in 0..<num_classes {
          let t = self.trans[s][f][k]
          let tb = if t < 0 { -1 } else { block_of[t] }
          key_buf.push_char('|')
          key_buf.push_str(tb.to_string())
        }
      }
      let key = key_buf.build()
      let id = match sig_ids.get(key) {
        Some(i) => i
        None => {
          let i = nid
          nid = nid + 1
          sig_ids[key] = i
          i
        }
      }
      new_block_of[s] = id
    }
    for s in 0..<n {
      block_of[s] = new_block_of[s]
    }
    if nid == num_blocks {
      break
    }
    num_blocks = nid
  }
  // 选取每块的代表状态。
  let rep = Array::make(num_blocks, -1)
  for s in 0..<n {
    if rep[block_of[s]] < 0 {
      rep[block_of[s]] = s
    }
  }
  // 按块代表重建 accept / trans；bounds 保持不变。
  let new_accept : Array[Array[Bool]] = []
  let new_trans : Array[Array[Array[Int]]] = []
  for b in 0..<num_blocks {
    let r = rep[b]
    let acc_row : Array[Bool] = []
    for f in 0..<4 {
      acc_row.push(self.accept[r][f])
    }
    new_accept.push(acc_row)
    let tr_f : Array[Array[Int]] = []
    for f in 0..<4 {
      let row : Array[Int] = []
      for k in 0..<num_classes {
        let t = self.trans[r][f][k]
        row.push(if t < 0 { -1 } else { block_of[t] })
      }
      tr_f.push(row)
    }
    new_trans.push(tr_f)
  }
  {
    num_states: num_blocks,
    start: block_of[self.start],
    bounds: self.bounds,
    accept: new_accept,
    trans: new_trans,
  }
}
