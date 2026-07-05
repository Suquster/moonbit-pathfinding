// benches/infra_text_bench — E6 Rope / Myers diff vs 朴素参照的吞吐基准。
//
// 参照实现（对标 E6 KPI）：
//   * Rope 随机编辑：参照为朴素字符串整篇重建（每次 insert/delete 拷贝全文
//     O(n)），Rope 为 split/concat O(log n + 片段量)；
//   * Myers diff：参照为 O(N·M) 全量 DP（LCS），Myers 为 O((N+M)·D)，
//     相似文本（D ≪ N+M）下差距为数量级。
//
// 工作负载确定性（xorshift64 固定种子），保证跨机器/后端可复现。

///|
fn xorshift(x : UInt64) -> UInt64 {
  let mut v = x
  v = v ^ (v << 13)
  v = v ^ (v >> 7)
  v = v ^ (v << 17)
  v
}

///|
/// 确定性基底文档（重复小写字母）。
fn make_doc(n : Int) -> String {
  let sb = StringBuilder::new()
  for i in 0..<n {
    sb.write_char((97 + i % 26).unsafe_to_char())
  }
  sb.to_string()
}

///|
/// 确定性编辑序列：(is_insert, pos_seed, len_seed)。
fn make_edits(k : Int, seed : UInt64) -> Array[(Bool, UInt64, Int)] {
  let out : Array[(Bool, UInt64, Int)] = []
  let mut s = seed
  for _ in 0..<k {
    s = xorshift(s)
    let ins = (s & 1UL) == 1UL
    s = xorshift(s)
    let pos_seed = s
    s = xorshift(s)
    let len = 1 + (s % 8UL).to_int()
    out.push((ins, pos_seed, len))
  }
  out
}

///|
/// 朴素参照：整篇重建 insert。
fn naive_insert(s : String, pos : Int, t : String) -> String {
  s[:pos].to_owned() + t + s[pos:].to_owned()
}

///|
/// 朴素参照：整篇重建 delete。
fn naive_delete(s : String, lo : Int, hi : Int) -> String {
  s[:lo].to_owned() + s[hi:].to_owned()
}

///|
test "bench: rope random edits vs naive string rebuild (doc=65536, edits=512)" (
  b : @bench.T,
) {
  let doc_n = 65536
  let base = make_doc(doc_n)
  let edits = make_edits(512, 20260705UL)
  b.bench(name="rope_edits_65536x512", fn() {
    let r = @text.Rope::from_string(base)
    for e in edits {
      let n = r.len()
      let pos = (e.1 % (n + 1).to_uint64()).to_int()
      if e.0 {
        r.insert(pos, "INSERT!!")
      } else {
        let hi = if pos + e.2 > n { n } else { pos + e.2 }
        r.delete(pos, hi)
      }
    }
    b.keep(r.len())
  })
  b.bench(name="naive_edits_65536x512", fn() {
    let mut s = base
    for e in edits {
      let n = s.length()
      let pos = (e.1 % (n + 1).to_uint64()).to_int()
      if e.0 {
        s = naive_insert(s, pos, "INSERT!!")
      } else {
        let hi = if pos + e.2 > n { n } else { pos + e.2 }
        s = naive_delete(s, pos, hi)
      }
    }
    b.keep(s.length())
  })
}

///|
test "bench: rope line/col index vs naive full scan (doc=1M, 256 queries)" (
  b : @bench.T,
) {
  // 百万码元、每 80 码元一个换行的文档。
  let sb = StringBuilder::new()
  for i in 0..<1_000_000 {
    if i % 80 == 79 {
      sb.write_char('\n')
    } else {
      sb.write_char((97 + i % 26).unsafe_to_char())
    }
  }
  let doc = sb.to_string()
  let r = @text.Rope::from_string(doc)
  // 确定性查询偏移。
  let offs : Array[Int] = []
  let mut seed = 7UL
  for _ in 0..<256 {
    seed = xorshift(seed)
    offs.push((seed % 1_000_000UL).to_int())
  }
  b.bench(name="rope_line_col_1m_x256", fn() {
    let mut acc = 0
    for off in offs {
      let (line, col) = r.line_col_at(off)
      acc = acc + line + col
    }
    b.keep(acc)
  })
  b.bench(name="naive_line_col_1m_x256", fn() {
    let mut acc = 0
    for off in offs {
      let mut line = 0
      let mut start = 0
      for j in 0..<off {
        if doc.at(j).to_int() == 10 {
          line = line + 1
          start = j + 1
        }
      }
      acc = acc + line + (off - start)
    }
    b.keep(acc)
  })
}

///|
test "bench: myers diff vs O(NM) DP on similar text (n=4096, k=8 edits)" (
  b : @bench.T,
) {
  let n = 4096
  let a = make_doc(n)
  // b 由 a 经 8 处单点替换得到（相似文本，D=16）。
  let mut bs = a
  let mut s = 99UL
  for _ in 0..<8 {
    s = xorshift(s)
    let p = (s % n.to_uint64()).to_int()
    bs = bs[:p].to_owned() + "Z" + bs[p + 1:].to_owned()
  }
  let target = bs
  b.bench(name="myers_diff_similar_4096", fn() {
    let ops = @text.myers_diff(a, target)
    b.keep(@text.diff_edit_cost(ops))
  })
  b.bench(name="dp_lcs_similar_4096", fn() {
    b.keep(@text.lcs_dp_cost(a, target))
  })
}
