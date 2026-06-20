// unify.mbt —— 合一（unification）、类型替换与 occurs-check（design.md §「组件
// 与接口 → 5. 合一与替换」，覆盖 R3.1 / R3.2 / R3.3 / R3.4 / R8.3）。
//
// 设计要点（对标《Write You a Haskell》经典 Algorithm W 表述）：
//   * 基于**不可变替换映射 + 复合（compose）**，而非 union-find，以教学清晰与
//     可测性优先。`Subst` 采用 `@sorted_map.SortedMap[Int, Ty]`（不可变有序
//     映射，三后端一致、可比较、无副作用）。
//   * 合一函数类型 `a1->b1 ~ a2->b2`：先合一参数，再在所得替换下合一结果，
//     最后返回二者复合后的替换（R3.3）。
//   * 合一类型变量与类型项前做 occurs-check：变量出现于该项且二者不等则拒绝
//     绑定（避免构造无限类型，R3.2）。
//   * 失败统一返回 `kind=TypeError` 的 `Diagnostic`，消息标注冲突的两类型
//     （Ty 派生 Show）。本层无源码 span，行列以哨兵 (0,0) 填充——精确 span 由
//     上层 infer.mbt 在节点处附加（design.md §「错误处理」）。
//   * **幂等性（R3.7）**：`compose` 与 `unify` 产出的替换经 `normalize` 规范化
//     至不动点（对值域反复施加自身直至稳定），使值域不再含定义域变量，从而
//     `apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)`。

///|
/// 空替换（恒等替换）。
pub fn subst_empty() -> Subst {
  Subst::{ map: @sorted_map.SortedMap::new() }
}

///|
/// 单点替换 `{v ↦ t}`。
pub fn subst_single(v : Int, t : Ty) -> Subst {
  let m : @sorted_map.SortedMap[Int, Ty] = @sorted_map.SortedMap::new()
  Subst::{ map: m.add(v, t) }
}

///|
/// 对类型项施加替换：递归地把其中出现的每个被映射类型变量替换为其映射目标
/// （R3.4）。`TyInt` / `TyBool` 不变，`TyFun` / `TyTuple` 递归下降。
///
/// 由于 `compose` / `unify` 产出的替换均已规范化（值域不含定义域变量），此处
/// 对被映射变量做单次查表替换即足以保证幂等。
pub fn apply_subst(s : Subst, t : Ty) -> Ty {
  match t {
    TyInt => TyInt
    TyBool => TyBool
    TyVar(v) =>
      match s.map.get(v) {
        Some(t2) => t2
        None => TyVar(v)
      }
    TyFun(a, b) => TyFun(apply_subst(s, a), apply_subst(s, b))
    TyTuple(xs) => TyTuple(xs.map(fn(x) { apply_subst(s, x) }))
  }
}

///|
/// 对类型方案施加替换：仅替换其自由变量，**保护**被全称量化的变量
/// （`sc.vars`）——先从替换的定义域中移除这些量化变量，再施于方案体。
pub fn apply_scheme(s : Subst, sc : Scheme) -> Scheme {
  let mut m = s.map
  for qv in sc.vars {
    m = m.remove(qv)
  }
  let restricted = Subst::{ map: m }
  Scheme::{ vars: sc.vars, body: apply_subst(restricted, sc.body) }
}

///|
/// 把替换 `base` 施加到映射 `m` 的每个值域条目上，得到新映射。
fn subst_apply_to_range(
  base : Subst,
  m : @sorted_map.SortedMap[Int, Ty],
) -> @sorted_map.SortedMap[Int, Ty] {
  let mut out : @sorted_map.SortedMap[Int, Ty] = @sorted_map.SortedMap::new()
  for kv in m.iter() {
    let (k, v) = kv
    out = out.add(k, apply_subst(base, v))
  }
  out
}

///|
/// 规范化替换：对值域反复施加自身直至不动点，使值域不再含定义域变量，从而替换
/// 幂等（R3.7）。最长替换链长度受定义域大小约束，故迭代 `|dom|` 次即达不动点。
fn normalize(s : Subst) -> Subst {
  let mut cur = s.map
  let bound = cur.to_array().length()
  for _ in 0..<bound {
    cur = subst_apply_to_range(Subst::{ map: cur }, cur)
  }
  Subst::{ map: cur }
}

///|
/// 替换复合：`compose(s1, s2)` 等价于「先施 s2 再施 s1」。即把 s1 施于 s2 的
/// 全部值域条目，再并入 s1 中不被 s2 定义域覆盖的条目，最后规范化以保证幂等。
pub fn compose(s1 : Subst, s2 : Subst) -> Subst {
  let mut out = subst_apply_to_range(s1, s2.map)
  for kv in s1.map.iter() {
    let (k, v) = kv
    if !s2.map.contains(k) {
      out = out.add(k, v)
    }
  }
  normalize(Subst::{ map: out })
}

///|
/// 类型项的自由类型变量集合（以不可变有序集合表示，供 `generalize` /
/// `apply_scheme` 等消费者使用）。
pub fn ftv(t : Ty) -> @sorted_set.SortedSet[Int] {
  match t {
    TyInt | TyBool => @sorted_set.SortedSet::new()
    TyVar(v) => @sorted_set.SortedSet::singleton(v)
    TyFun(a, b) => ftv(a).union(ftv(b))
    TyTuple(xs) => {
      let mut acc : @sorted_set.SortedSet[Int] = @sorted_set.SortedSet::new()
      for x in xs {
        acc = acc.union(ftv(x))
      }
      acc
    }
  }
}

///|
/// occurs-check：类型变量 `v` 是否出现于类型项 `t` 中（R3.2 / R3.6）。
pub fn occurs(v : Int, t : Ty) -> Bool {
  ftv(t).contains(v)
}

///|
/// 构造「不可合一」类型错误诊断，消息标注冲突的两类型（R8.3）。
fn type_mismatch(t1 : Ty, t2 : Ty) -> Diagnostic {
  Diagnostic::new(TypeError, 0, 0, "cannot unify \{t1} with \{t2}")
}

///|
/// 合一一个类型变量 `v` 与类型项 `t`：相等则返回空替换；否则做 occurs-check，
/// 通过则返回单点绑定 `{v ↦ t}`，失败则返回 occurs-check 类型错误。
fn unify_var(v : Int, t : Ty) -> Result[Subst, Diagnostic] {
  match t {
    TyVar(w) => if v == w { Ok(subst_empty()) } else { Ok(subst_single(v, t)) }
    _ =>
      if occurs(v, t) {
        Err(
          Diagnostic::new(
            TypeError,
            0,
            0,
            "occurs check: cannot construct infinite type \{TyVar(v)} ~ \{t}",
          ),
        )
      } else {
        Ok(subst_single(v, t))
      }
  }
}

///|
/// 逐元素合一两个等长类型项序列，线程化累积替换：对每个分量先施加已积累替换，
/// 再合一，并把结果复合进累积替换。
fn unify_list(
  xs : Array[Ty],
  ys : Array[Ty],
  i : Int,
  acc : Subst,
) -> Result[Subst, Diagnostic] {
  if i >= xs.length() {
    Ok(acc)
  } else {
    match unify(apply_subst(acc, xs[i]), apply_subst(acc, ys[i])) {
      Err(d) => Err(d)
      Ok(s) => unify_list(xs, ys, i + 1, compose(s, acc))
    }
  }
}

///|
/// 合一两个类型项，产出使二者相等的最一般合一子（mgu）替换，或在不可合一时
/// 返回携带冲突两类型的 `TypeError` 诊断（R3.1）。
///
/// - `TyInt ~ TyInt` / `TyBool ~ TyBool` → 空替换。
/// - 类型变量与任意类型项：先 occurs-check（R3.2）。
/// - `TyFun(a1,b1) ~ TyFun(a2,b2)`：先合一参数，再在所得替换下合一结果，
///   返回二者复合（R3.3）。
/// - `TyTuple ~ TyTuple`：长度相同则逐元素线程化合一，否则报类型错误。
/// - 其余组合（如 `TyInt ~ TyBool`、`TyInt ~ TyFun`）→ 类型错误。
pub fn unify(t1 : Ty, t2 : Ty) -> Result[Subst, Diagnostic] {
  match (t1, t2) {
    (TyInt, TyInt) => Ok(subst_empty())
    (TyBool, TyBool) => Ok(subst_empty())
    (TyVar(v), _) => unify_var(v, t2)
    (_, TyVar(v)) => unify_var(v, t1)
    (TyFun(a1, b1), TyFun(a2, b2)) =>
      match unify(a1, a2) {
        Err(d) => Err(d)
        Ok(s1) =>
          match unify(apply_subst(s1, b1), apply_subst(s1, b2)) {
            Err(d) => Err(d)
            Ok(s2) => Ok(compose(s2, s1))
          }
      }
    (TyTuple(xs), TyTuple(ys)) =>
      if xs.length() != ys.length() {
        Err(type_mismatch(t1, t2))
      } else {
        unify_list(xs, ys, 0, subst_empty())
      }
    _ => Err(type_mismatch(t1, t2))
  }
}
