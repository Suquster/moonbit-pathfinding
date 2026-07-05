// exhaustive.mbt —— T1.3 类型推断深化：match 穷尽性 / 冗余 arm 检查
// （paper-to-code：Maranget 2007 "Warnings for pattern matching" 的
// usefulness 算法 𝒰/ℐ，特化到 match_ext.mbt 的 Pattern 语言）。
//
// 旁路新增（freeze + bypass）：不修改任何既有签名，消费既有 `Pattern` / `TyX`。
//
// 核心概念：模式矩阵 P（每行为一个 arm 的模式向量）对模式向量 q 的
// **有用性（usefulness）**——存在值向量被 q 匹配而不被 P 任何行匹配。
//   * 穷尽性：P 穷尽 ⇔ 通配向量对 P **无用**；有用时算法同时构造
//     **缺失值的模式见证**（ℐ 算法），用于诊断报错。
//   * 冗余性：第 i 行冗余 ⇔ 它对前 i-1 行构成的矩阵无用。
//
// 构造子签名（signature）完整性按列类型判定：
//   * `TXBool` —— {true, false}；
//   * `TXTuple(ts)` —— 单构造子（n 元组）；
//   * `TXList(t)` —— {Nil, Cons}；
//   * `TXInt` / `TXFun` —— 字面量/不可解构，签名视为**永不完整**
//     （Int 字面量有无穷多个；函数值无模式可解构）。

///|
/// 列构造子的抽象标识（specialization 的分派键）。
priv enum PatCtor {
  CInt(Int)
  CBool(Bool)
  CTuple(Int) // 元数
  CCons
  CNil
} derive(Eq)

///|
/// 取模式的根构造子；通配 / 变量模式返回 `None`。
fn root_ctor(p : Pattern) -> PatCtor? {
  match p {
    PWild | PVar(_) => None
    PInt(v) => Some(CInt(v))
    PBool(b) => Some(CBool(b))
    PTuple(ps) => Some(CTuple(ps.length()))
    PCons(_, _) => Some(CCons)
    PNil => Some(CNil)
  }
}

///|
/// 构造子的子模式元数与子列类型（依列类型展开）。
fn ctor_arg_tys(c : PatCtor, ty : TyX) -> Array[TyX] {
  match (c, ty) {
    (CTuple(_), TXTuple(ts)) => ts
    (CCons, TXList(t)) => [t, TXList(t)]
    _ => []
  }
}

///|
/// 把一行模式向量对构造子 `c` 特化（Maranget 𝒮）：首模式匹配 `c` 则展开其
/// 子模式并接上剩余列；通配/变量以等量通配展开；不匹配则该行被剔除。
fn specialize_row(
  c : PatCtor,
  arity : Int,
  row : Array[Pattern],
) -> Array[Pattern]? {
  let head = row[0]
  let expand : Array[Pattern]? = match (root_ctor(head), head) {
    (None, _) => {
      let ws : Array[Pattern] = []
      for _i in 0..<arity {
        ws.push(PWild)
      }
      Some(ws)
    }
    (Some(hc), PTuple(ps)) => if hc == c { Some(ps) } else { None }
    (Some(hc), PCons(h, t)) => if hc == c { Some([h, t]) } else { None }
    (Some(hc), _) => if hc == c { Some([]) } else { None }
  }
  match expand {
    None => None
    Some(args) => {
      let out : Array[Pattern] = []
      for a in args {
        out.push(a)
      }
      for i in 1..<row.length() {
        out.push(row[i])
      }
      Some(out)
    }
  }
}

///|
/// 默认矩阵行（Maranget 𝒟）：仅保留首模式为通配/变量的行，去掉首列。
fn default_row(row : Array[Pattern]) -> Array[Pattern]? {
  match root_ctor(row[0]) {
    None => {
      let out : Array[Pattern] = []
      for i in 1..<row.length() {
        out.push(row[i])
      }
      Some(out)
    }
    Some(_) => None
  }
}

///|
/// 列类型的完整构造子签名；`None` 表示签名不可完整枚举（Int / Fun）。
fn full_signature(ty : TyX) -> Array[PatCtor]? {
  match ty {
    TXBool => Some([CBool(true), CBool(false)])
    TXTuple(ts) => Some([CTuple(ts.length())])
    TXList(_) => Some([CNil, CCons])
    TXInt | TXFun(_, _) => None
  }
}

///|
/// 由构造子与子见证折叠出该列的模式见证。
fn rebuild_witness(
  c : PatCtor,
  arity : Int,
  sub : Array[Pattern],
) -> (Pattern, Array[Pattern]) {
  // sub 的前 arity 个为子模式，其余为剩余列见证。
  let args : Array[Pattern] = []
  for i in 0..<arity {
    args.push(sub[i])
  }
  let rest : Array[Pattern] = []
  for i in arity..<sub.length() {
    rest.push(sub[i])
  }
  let head : Pattern = match c {
    CInt(v) => PInt(v)
    CBool(b) => PBool(b)
    CTuple(_) => PTuple(args)
    CCons => PCons(args[0], args[1])
    CNil => PNil
  }
  (head, rest)
}

///|
/// 找一个不在给定字面量集合中的整数（Int 签名不完整时的缺失见证）。
fn fresh_int_not_in(matrix_heads : Array[Pattern]) -> Pattern {
  let seen : Map[Int, Bool] = Map([])
  for p in matrix_heads {
    match p {
      PInt(v) => seen[v] = true
      _ => ()
    }
  }
  let mut cand = 0
  while seen.contains(cand) {
    cand = cand + 1
  }
  PInt(cand)
}

///|
/// usefulness + 见证构造（Maranget ℐ）：通配向量对矩阵 `matrix`（列类型
/// `tys`）有用时返回缺失值的模式见证向量；无用（矩阵穷尽）返回 `None`。
fn missing_witness(
  matrix : Array[Array[Pattern]],
  tys : Array[TyX],
) -> Array[Pattern]? {
  if tys.length() == 0 {
    // 零列：矩阵非空 ⇒ 无用（穷尽）；空矩阵 ⇒ 有用，见证为空向量。
    return if matrix.length() == 0 { Some([]) } else { None }
  }
  let ty = tys[0]
  let rest_tys : Array[TyX] = []
  for i in 1..<tys.length() {
    rest_tys.push(tys[i])
  }
  // 收集首列出现的根构造子。
  let heads : Array[Pattern] = []
  let present : Array[PatCtor] = []
  for row in matrix {
    heads.push(row[0])
    match root_ctor(row[0]) {
      Some(c) => if !present.contains(c) { present.push(c) }
      None => ()
    }
  }
  fn try_ctor(c : PatCtor) -> Array[Pattern]? {
    let arg_tys = ctor_arg_tys(c, ty)
    let arity = arg_tys.length()
    let spec : Array[Array[Pattern]] = []
    for row in matrix {
      match specialize_row(c, arity, row) {
        Some(r) => spec.push(r)
        None => ()
      }
    }
    let sub_tys : Array[TyX] = []
    for t in arg_tys {
      sub_tys.push(t)
    }
    for t in rest_tys {
      sub_tys.push(t)
    }
    match missing_witness(spec, sub_tys) {
      None => None
      Some(sub) => {
        let (head, rest) = rebuild_witness(c, arity, sub)
        let out : Array[Pattern] = [head]
        for p in rest {
          out.push(p)
        }
        Some(out)
      }
    }
  }

  match full_signature(ty) {
    Some(sig) => {
      // 签名可完整枚举：全部构造子都在首列出现 ⇒ 逐构造子递归；
      // 否则任一缺失构造子即可作为见证头（子列全通配）。
      let mut all_present = true
      for c in sig {
        if !present.contains(c) {
          all_present = false
        }
      }
      if all_present {
        for c in sig {
          match try_ctor(c) {
            Some(w) => return Some(w)
            None => ()
          }
        }
        None
      } else {
        // 用默认矩阵检查剩余列，再补缺失构造子头。
        let dm : Array[Array[Pattern]] = []
        for row in matrix {
          match default_row(row) {
            Some(r) => dm.push(r)
            None => ()
          }
        }
        match missing_witness(dm, rest_tys) {
          None => None
          Some(rest) => {
            let mut missing_head : Pattern = PWild
            for c in sig {
              if !present.contains(c) {
                let arg_tys = ctor_arg_tys(c, ty)
                let ws : Array[Pattern] = []
                for _t in arg_tys {
                  ws.push(PWild)
                }
                let (head, _r) = rebuild_witness(c, arg_tys.length(), ws)
                missing_head = head
                break
              }
            }
            let out : Array[Pattern] = [missing_head]
            for p in rest {
              out.push(p)
            }
            Some(out)
          }
        }
      }
    }
    None => {
      // Int / Fun：签名永不完整 ⇒ 只需检查默认矩阵；见证头取未出现的字面量
      // （Int）或通配（Fun）。
      let dm : Array[Array[Pattern]] = []
      for row in matrix {
        match default_row(row) {
          Some(r) => dm.push(r)
          None => ()
        }
      }
      match missing_witness(dm, rest_tys) {
        None => None
        Some(rest) => {
          let head : Pattern = match ty {
            TXInt => fresh_int_not_in(heads)
            _ => PWild
          }
          let out : Array[Pattern] = [head]
          for p in rest {
            out.push(p)
          }
          Some(out)
        }
      }
    }
  }
}

///|
/// 穷尽性检查（T1.3）：对 scrutinee 类型 `ty` 与各 arm 模式 `pats`，
/// 穷尽返回 `None`；否则返回一个**未被任何 arm 覆盖**的模式见证
/// （可直接用于「missing case: ...」诊断）。
pub fn check_exhaustive(pats : Array[Pattern], ty : TyX) -> Pattern? {
  let matrix : Array[Array[Pattern]] = []
  for p in pats {
    matrix.push([p])
  }
  match missing_witness(matrix, [ty]) {
    None => None
    Some(w) => Some(w[0])
  }
}

///|
/// 冗余 arm 检查（T1.3）：返回所有**不可达** arm 的下标（该 arm 能匹配的一切
/// 值均已被更早的 arm 覆盖），升序。
pub fn redundant_arms(pats : Array[Pattern], ty : TyX) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<pats.length() {
    // 第 i 行冗余 ⇔ 对前 i 行矩阵「无用」⇔ 把第 i 行模式当作唯一列向量 q，
    // 特化后的 missing_witness 检查：等价于 q 对前缀矩阵的 usefulness。
    if !useful_row(pats, i, ty) {
      out.push(i)
    }
  }
  out
}

///|
/// 第 `idx` 行对其前缀矩阵是否有用（Maranget 𝒰，经由把 q 也编码进矩阵：
/// q 有用 ⇔ 存在值被 q 匹配且不被前缀匹配 ⇔ missing_witness 在
/// 「前缀 + 以 q 约束的列」上非空。此处直接实现 𝒰 的递归形式）。
fn useful_row(pats : Array[Pattern], idx : Int, ty : TyX) -> Bool {
  let prefix : Array[Array[Pattern]] = []
  for i in 0..<idx {
    prefix.push([pats[i]])
  }
  useful(prefix, [pats[idx]], [ty])
}

///|
/// Maranget 𝒰：向量 q 对矩阵 P 是否有用。
fn useful(
  matrix : Array[Array[Pattern]],
  q : Array[Pattern],
  tys : Array[TyX],
) -> Bool {
  if tys.length() == 0 {
    return matrix.length() == 0
  }
  let ty = tys[0]
  let rest_tys : Array[TyX] = []
  for i in 1..<tys.length() {
    rest_tys.push(tys[i])
  }
  fn spec_all(c : PatCtor, arity : Int) -> Array[Array[Pattern]] {
    let out : Array[Array[Pattern]] = []
    for row in matrix {
      match specialize_row(c, arity, row) {
        Some(r) => out.push(r)
        None => ()
      }
    }
    out
  }

  fn sub_tys_of(c : PatCtor) -> Array[TyX] {
    let arg_tys = ctor_arg_tys(c, ty)
    let out : Array[TyX] = []
    for t in arg_tys {
      out.push(t)
    }
    for t in rest_tys {
      out.push(t)
    }
    out
  }

  match root_ctor(q[0]) {
    Some(c) => {
      let arity = ctor_arg_tys(c, ty).length()
      match specialize_row(c, arity, q) {
        Some(qs) => useful(spec_all(c, arity), qs, sub_tys_of(c))
        None => false
      }
    }
    None => {
      // q 首列为通配：按签名完整性分派。
      let present : Array[PatCtor] = []
      for row in matrix {
        match root_ctor(row[0]) {
          Some(c) => if !present.contains(c) { present.push(c) }
          None => ()
        }
      }
      let complete = match full_signature(ty) {
        Some(sig) => {
          let mut all = true
          for c in sig {
            if !present.contains(c) {
              all = false
            }
          }
          all
        }
        None => false
      }
      if complete {
        match full_signature(ty) {
          Some(sig) => {
            for c in sig {
              let arity = ctor_arg_tys(c, ty).length()
              let ws : Array[Pattern] = []
              for _i in 0..<arity {
                ws.push(PWild)
              }
              for i in 1..<q.length() {
                ws.push(q[i])
              }
              if useful(spec_all(c, arity), ws, sub_tys_of(c)) {
                return true
              }
            }
            false
          }
          None => false
        }
      } else {
        let dm : Array[Array[Pattern]] = []
        for row in matrix {
          match default_row(row) {
            Some(r) => dm.push(r)
            None => ()
          }
        }
        let qr : Array[Pattern] = []
        for i in 1..<q.length() {
          qr.push(q[i])
        }
        useful(dm, qr, rest_tys)
      }
    }
  }
}
