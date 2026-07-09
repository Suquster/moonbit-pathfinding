// family13_proof_test.mbt —— 加速/编译器/协议家族（advanced / codegen_infra /
// lsp_binding / mini_compiler）证明谓词的真实实现接地测试（INFRA 第十三批）。
// 此前这四个方向的谓词仅以手工正反例驱动，本批补齐真实实现接地：
//   * advanced：随机带权有向图上 CH / ALT 查询（含批量）与 @directed.dijkstra
//     参考实现逐对代价一致（cost_agrees_with_reference / batch_cost_agrees），
//     命中结果同时满足查询后置条件（ch_query_post / alt_query_post）；
//   * codegen_infra：随机基本块程序经 build_ssa 建立、全 pass 流水线优化后，
//     定义版本号（块内 name#ver 左值 + φ 目标）仍两两互异
//     （ssa_single_assignment 建立与保持）；干涉图着色分配结果在每条干涉边
//     两端互不冲突（interference_distinct 经 allocate_coloring 接地）；
//   * lsp_binding：随机 JSON-RPC 消息 encode_framed / decode_framed 往返恒等，
//     FrameReader 在任意切分点重组分块帧且按序切出；畸形帧返回结构化
//     parse_error 且进程存活（illegal_message_keeps_alive 接地）；
//   * mini_compiler：随机 let 链源串经真实 lex_ml / parse_ml / scope_check_ml
//     后，使用集合 ⊆ 绑定集合（scope_binding_consistent 接地）；解释路径与
//     编译—执行路径在优化开/关下产出相等结果（端到端两路一致）。

// ---------------------------------------------------------------------------
// advanced：CH / ALT 与 Dijkstra 参考实现的代价等价接地
// ---------------------------------------------------------------------------

///|
/// 随机带权有向图生成器：链式骨架 0→1→…→n-1 保证 0 到 n-1 可达，再叠加
/// 随机额外边；权重由端点确定函数派生（1..13，正权），保持纯性。
fn f13_wgraph_gen() -> @infra_pbt.Gen[(Int, Array[(Int, Int, Int)])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 9)
    let edges : Array[(Int, Int, Int)] = []
    for i in 1..<n {
      edges.push((i - 1, i, 1 + ((i - 1) * 7 + i * 3) % 13))
    }
    let extra = rng.next_range(0, n)
    for _k in 0..<extra {
      let u = rng.next_range(0, n - 1)
      let v = rng.next_range(0, n - 1)
      if u != v {
        edges.push((u, v, 1 + (u * 5 + v * 11) % 13))
      }
    }
    (n, edges)
  })
}

///|
fn f13_succ(edges : Array[(Int, Int, Int)]) -> (Int) -> Array[(Int, Int)] {
  fn(u : Int) -> Array[(Int, Int)] {
    let out : Array[(Int, Int)] = []
    for e in edges {
      if e.0 == u {
        out.push((e.1, e.2))
      }
    }
    out
  }
}

///|
fn f13_edge_weight(edges : Array[(Int, Int, Int)]) -> (Int, Int) -> Int? {
  fn(u : Int, v : Int) -> Int? {
    let mut best : Int? = None
    for e in edges {
      if e.0 == u && e.1 == v {
        match best {
          None => best = Some(e.2)
          Some(w) => if e.2 < w { best = Some(e.2) }
        }
      }
    }
    best
  }
}

///|
fn f13_nodes(n : Int) -> Array[Int] {
  let nodes : Array[Int] = []
  for i in 0..<n {
    nodes.push(i)
  }
  nodes
}

///|
test "ch query cost agrees with dijkstra reference on random digraphs" {
  let ok = @infra_pbt.holds_for_all(
    f13_wgraph_gen(),
    fn(input : (Int, Array[(Int, Int, Int)])) -> Bool {
      let (n, edges) = input
      let nodes = f13_nodes(n)
      let succ = f13_succ(edges)
      let ch = @advanced.ch_preprocess(nodes, succ)
      let pairs : Array[(Int, Int)] = [(0, n - 1), (0, n / 2), (n - 1, 0)]
      let fast = @advanced.ch_query_batch(ch, pairs)
      let refs : Array[(Array[Int], Int)?] = []
      for p in pairs {
        refs.push(@directed.dijkstra(p.0, succ, fn(u) { u == p.1 }))
      }
      if !batch_cost_agrees(fast, refs) {
        return false
      }
      // 主查询 0 → n-1 必命中（链式骨架保证），且满足查询后置条件。
      ch_query_post(
        fast[0],
        0,
        fn(u) { u == n - 1 },
        succ,
        f13_edge_weight(edges),
        nodes,
      )
    },
    iters=64,
  )
  assert_true(ok)
}

///|
test "alt query cost agrees with dijkstra reference on random digraphs" {
  let ok = @infra_pbt.holds_for_all(
    f13_wgraph_gen(),
    fn(input : (Int, Array[(Int, Int, Int)])) -> Bool {
      let (n, edges) = input
      let nodes = f13_nodes(n)
      let succ = f13_succ(edges)
      let lm = @advanced.alt_preprocess(nodes, succ, 2)
      let single = @advanced.alt_query(lm, 0, n - 1, succ)
      let reference = @directed.dijkstra(0, succ, fn(u) { u == n - 1 })
      if !cost_agrees_with_reference(single, reference) {
        return false
      }
      if !alt_query_post(
          single,
          0,
          fn(u) { u == n - 1 },
          succ,
          f13_edge_weight(edges),
          nodes,
        ) {
        return false
      }
      let pairs : Array[(Int, Int)] = [(0, n - 1), (0, n / 2)]
      let fast = @advanced.alt_query_batch(lm, pairs, succ)
      let refs : Array[(Array[Int], Int)?] = []
      for p in pairs {
        refs.push(@directed.dijkstra(p.0, succ, fn(u) { u == p.1 }))
      }
      batch_cost_agrees(fast, refs)
    },
    iters=64,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// codegen_infra：SSA 单赋值建立/保持 + 干涉着色接地
// ---------------------------------------------------------------------------

///|
/// 以空白切分指令为记号序列（与 codegen_infra 的记号约定一致）。
fn f13_tokens(instr : String) -> Array[String] {
  let out : Array[String] = []
  let cs = instr.iter().to_array()
  let sb = StringBuilder::new()
  let mut i = 0
  while i < cs.length() {
    if cs[i] == ' ' {
      if sb.to_string().length() > 0 {
        out.push(sb.to_string())
      }
      sb.reset()
    } else {
      sb.write_char(cs[i])
    }
    i += 1
  }
  if sb.to_string().length() > 0 {
    out.push(sb.to_string())
  }
  out
}

///|
/// 从 `name#ver` 记号中解析版本号；无 `#` 或后缀非整数时返回 `None`。
fn f13_version_id(tok : String) -> Int? {
  let cs = tok.iter().to_array()
  let mut hash = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '#' {
      hash = i
    }
    i += 1
  }
  if hash < 0 || hash + 1 >= cs.length() {
    return None
  }
  let mut n = 0
  let mut j = hash + 1
  while j < cs.length() {
    let c = cs[j]
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    j += 1
  }
  Some(n)
}

///|
/// 收集 SSA 程序的全部定义版本号：块内定义左值 `name#ver` + φ 目标 id。
fn f13_def_ids(p : @codegen_infra.SsaProgram) -> Array[Int] {
  let ids : Array[Int] = []
  for b in p.blocks {
    for instr in b.instrs {
      let toks = f13_tokens(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        match f13_version_id(toks[0]) {
          Some(v) => ids.push(v)
          None => ()
        }
      }
    }
  }
  for phi in p.phis {
    ids.push(phi.dest.id)
  }
  ids
}

///|
/// 随机基本块程序生成器：直线代码或菱形汇合（汇合块触发 φ 插入）。
fn f13_blocks_gen() -> @infra_pbt.Gen[Array[@codegen_infra.BasicBlock]] {
  @infra_pbt.Gen::new(fn(rng) {
    let pool = ["a", "b", "c", "x"]
    let gen_def = fn() -> String {
      let lhs = pool[rng.next_below(pool.length())]
      if rng.next_bool() {
        lhs + " = " + rng.next_range(0, 9).to_string()
      } else {
        lhs +
        " = " +
        pool[rng.next_below(pool.length())] +
        " + " +
        pool[rng.next_below(pool.length())]
      }
    }
    let gen_defs = fn(count : Int) -> Array[String] {
      let out : Array[String] = []
      for _i in 0..<count {
        out.push(gen_def())
      }
      out
    }
    if rng.next_bool() {
      let instrs = gen_defs(rng.next_range(1, 5))
      instrs.push("ret " + pool[rng.next_below(pool.length())])
      [@codegen_infra.BasicBlock::{ label: "b0", instrs, succs: [] }]
    } else {
      let join_instrs = gen_defs(rng.next_range(0, 2))
      join_instrs.push("ret " + pool[rng.next_below(pool.length())])
      [
        @codegen_infra.BasicBlock::{
          label: "entry",
          instrs: gen_defs(rng.next_range(1, 3)),
          succs: ["then", "else"],
        },
        @codegen_infra.BasicBlock::{
          label: "then",
          instrs: gen_defs(rng.next_range(1, 3)),
          succs: ["join"],
        },
        @codegen_infra.BasicBlock::{
          label: "else",
          instrs: gen_defs(rng.next_range(1, 3)),
          succs: ["join"],
        },
        @codegen_infra.BasicBlock::{
          label: "join",
          instrs: join_instrs,
          succs: [],
        },
      ]
    }
  })
}

///|
test "ssa single assignment established and preserved through full pipeline" {
  let ok = @infra_pbt.holds_for_all(
    f13_blocks_gen(),
    fn(blocks : Array[@codegen_infra.BasicBlock]) -> Bool {
      let ssa = @codegen_infra.build_ssa(blocks)
      if !ssa_single_assignment(f13_def_ids(ssa)) {
        return false
      }
      let optimized = @codegen_infra.run_pipeline(ssa, [
        ConstFold,
        DeadCodeElim,
        CopyProp,
        Sccp,
        Gvn,
      ])
      ssa_single_assignment(f13_def_ids(optimized))
    },
    iters=128,
  )
  assert_true(ok)
}

///|
/// 把寄存器/溢出槽位编码进互不相交的整数编号空间（Reg(r)↦2r，Spill(s)↦2s+1）。
fn f13_loc_code(loc : @codegen_infra.Location) -> Int {
  match loc {
    Reg(r) => 2 * r
    Spill(s) => 2 * s + 1
  }
}

///|
test "graph coloring allocation keeps interference edge endpoints distinct" {
  let ok = @infra_pbt.holds_for_all(
    f13_blocks_gen(),
    fn(blocks : Array[@codegen_infra.BasicBlock]) -> Bool {
      let live = @codegen_infra.analyze_liveness(blocks)
      let g = @codegen_infra.build_interference_from_liveness(blocks, live)
      let alloc = @codegen_infra.allocate_coloring(g, 3)
      let colored : Array[(Int, Int)] = []
      for e in g.edges {
        match (alloc.get(e.0), alloc.get(e.1)) {
          (Some(la), Some(lb)) =>
            colored.push((f13_loc_code(la), f13_loc_code(lb)))
          _ => return false
        }
      }
      interference_distinct(colored)
    },
    iters=128,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// lsp_binding：帧编解码往返 + 分块重组 + 畸形帧鲁棒性接地
// ---------------------------------------------------------------------------

///|
fn f13_concat(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<a.length() {
    arr.push(a[i])
  }
  for i in 0..<b.length() {
    arr.push(b[i])
  }
  Bytes::from_array(arr)
}

///|
fn f13_slice(b : Bytes, start : Int, end : Int) -> Bytes {
  let arr : Array[Byte] = []
  for i in start..<end {
    arr.push(b[i])
  }
  Bytes::from_array(arr)
}

///|
/// 随机 JSON-RPC 消息生成器：请求 / 通知 / 响应三形态。
fn f13_msg_gen() -> @infra_pbt.Gen[@lsp_binding.JsonRpcMessage] {
  @infra_pbt.Gen::new(fn(rng) {
    let methods = [
      "initialize", "textDocument/didOpen", "shutdown", "$/progress",
    ]
    let m = methods[rng.next_below(methods.length())]
    match rng.next_below(3) {
      0 =>
        @lsp_binding.JsonRpcMessage::Request(
          id=IdNum(rng.next_range(0, 999)),
          method_name=m,
          params=JObj([("key", JStr("v" + rng.next_range(0, 99).to_string()))]),
        )
      1 =>
        @lsp_binding.JsonRpcMessage::Notification(method_name=m, params=JNull)
      _ =>
        @lsp_binding.JsonRpcMessage::Response(
          id=IdNum(rng.next_range(0, 999)),
          result=Some(JNum(rng.next_range(0, 999).to_string())),
          error=None,
        )
    }
  })
}

///|
test "lsp framed codec round trips and reassembles chunked frames" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) {
      let gen = f13_msg_gen()
      (gen.generate(rng), gen.generate(rng), rng.next_range(1, 40))
    }),
    fn(
      input : (@lsp_binding.JsonRpcMessage, @lsp_binding.JsonRpcMessage, Int),
    ) -> Bool {
      let (m1, m2, cut_seed) = input
      // 单帧往返恒等。
      let f1 = @lsp_binding.encode_framed(m1)
      match @lsp_binding.decode_framed(f1) {
        Ok(d) => if d != m1 { return false }
        Err(_) => return false
      }
      // 两帧拼接后在任意切分点分块推入，按序切出。
      let joined = f13_concat(f1, @lsp_binding.encode_framed(m2))
      let cut = 1 + cut_seed % (joined.length() - 1)
      let reader = @lsp_binding.FrameReader::new()
        .push(f13_slice(joined, 0, cut))
        .push(f13_slice(joined, cut, joined.length()))
      match reader.next() {
        Ok(Some((d1, rest))) => {
          if d1 != m1 {
            return false
          }
          match rest.next() {
            Ok(Some((d2, _))) => d2 == m2
            _ => false
          }
        }
        _ => false
      }
    },
    iters=128,
  )
  assert_true(ok)
}

///|
test "lsp illegal frames yield structured parse errors and keep process alive" {
  // 缺 Content-Length 头的畸形帧：decode 必须返回结构化错误而非崩溃。
  let garbage : Array[Byte] = []
  for c in "not a frame".iter() {
    garbage.push(c.to_int().to_byte())
  }
  match @lsp_binding.decode_framed(Bytes::from_array(garbage)) {
    Ok(_) => fail("expected a parse error for a headerless frame")
    Err(e) => {
      // 真实错误响应见证「非法消息不终止进程」谓词：进程存活 + 已返回
      // 符合规范的结构化错误。
      let error_responded = e.code == @lsp_binding.parse_error_code
      assert_true(error_responded)
      assert_true(illegal_message_keeps_alive(false, error_responded, true))
    }
  }
}

// ---------------------------------------------------------------------------
// mini_compiler：作用域绑定一致性 + 端到端两路一致接地
// ---------------------------------------------------------------------------

///|
/// 收集 Expr 的绑定名（ELam/ELet/ELetRec 引入）与使用名（EVar）。
fn f13_collect_names(
  e : @mini_compiler.Expr,
  bound : Array[String],
  used : Array[String],
) -> Unit {
  match e {
    EInt(_, _) | EBool(_, _) => ()
    EVar(name, _) => used.push(name)
    EArith(_, a, b, _) | ECmp(_, a, b, _) | ELogic(_, a, b, _) => {
      f13_collect_names(a, bound, used)
      f13_collect_names(b, bound, used)
    }
    EIf(c, t, f, _) => {
      f13_collect_names(c, bound, used)
      f13_collect_names(t, bound, used)
      f13_collect_names(f, bound, used)
    }
    ELam(name, body, _) => {
      bound.push(name)
      f13_collect_names(body, bound, used)
    }
    EApp(f, a, _) => {
      f13_collect_names(f, bound, used)
      f13_collect_names(a, bound, used)
    }
    ELet(name, rhs, body, _) => {
      bound.push(name)
      f13_collect_names(rhs, bound, used)
      f13_collect_names(body, bound, used)
    }
    ELetRec(name, rhs, body, _) => {
      bound.push(name)
      f13_collect_names(rhs, bound, used)
      f13_collect_names(body, bound, used)
    }
    ETuple(items, _) =>
      for item in items {
        f13_collect_names(item, bound, used)
      }
  }
}

///|
/// 随机良作用域 let 链源串：`let a = 1 in let b = a + 2 in … in <use>`，
/// 每个右值只引用此前已绑定的名字，保证 scope_check_ml 通过。
fn f13_let_chain_gen() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    let pool = ["a", "b", "c", "d"]
    let depth = rng.next_range(1, pool.length())
    let sb = StringBuilder::new()
    for i in 0..<depth {
      sb.write_string("let " + pool[i] + " = ")
      if i > 0 && rng.next_bool() {
        sb.write_string(
          pool[rng.next_below(i)] + " + " + rng.next_range(0, 9).to_string(),
        )
      } else {
        sb.write_string(rng.next_range(0, 9).to_string())
      }
      sb.write_string(" in ")
    }
    sb.write_string(pool[rng.next_below(depth)] + " + 1")
    sb.to_string()
  })
}

///|
test "mini compiler scope invariant grounded via real front end" {
  let ok = @infra_pbt.holds_for_all(
    f13_let_chain_gen(),
    fn(src : String) -> Bool {
      match @mini_compiler.lex_ml(src) {
        Ok(toks) =>
          match @mini_compiler.parse_ml(toks) {
            Ok(expr) =>
              match @mini_compiler.scope_check_ml(expr) {
                Ok(_) => {
                  let bound : Array[String] = []
                  let used : Array[String] = []
                  f13_collect_names(expr, bound, used)
                  scope_binding_consistent(bound, used)
                }
                Err(_) => false
              }
            Err(_) => false
          }
        Err(_) => false
      }
    },
    iters=128,
  )
  assert_true(ok)
  // 反例：自由变量必须被真实 scope_check_ml 拒绝，且谓词判假。
  match @mini_compiler.lex_ml("zz + 1") {
    Ok(toks) =>
      match @mini_compiler.parse_ml(toks) {
        Ok(expr) => {
          assert_true(@mini_compiler.scope_check_ml(expr) is Err(_))
          let bound : Array[String] = []
          let used : Array[String] = []
          f13_collect_names(expr, bound, used)
          assert_false(scope_binding_consistent(bound, used))
        }
        Err(_) => fail("expected the negative program to parse")
      }
    Err(_) => fail("expected the negative program to lex")
  }
}

///|
test "mini compiler interp and compiled paths agree on random let chains" {
  let ok = @infra_pbt.holds_for_all(
    f13_let_chain_gen(),
    fn(src : String) -> Bool {
      let plain_agree = @mini_compiler.run_interp(src) ==
        @mini_compiler.run_compiled(src)
      let opt_agree = @mini_compiler.run_interp(src, optimize=true) ==
        @mini_compiler.run_compiled(src, optimize=true)
      let produced = @mini_compiler.run_interp(src)
        is @mini_compiler.PipelineResult::Produced(_)
      plain_agree && opt_agree && produced
    },
    iters=128,
  )
  assert_true(ok)
}
