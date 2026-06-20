// infer.mbt —— Hindley-Milner 类型推断 Algorithm W（design.md §「组件与接口 →
// 6. Algorithm W 类型推断」，覆盖 R4.1 ~ R4.9 与 R8.3 / R8.4）。
//
// 设计要点（对标 Damas-Milner Algorithm W 与《Write You a Haskell》）：
//   * `FreshGen` 为新鲜类型变量发生器（封装一个可变计数器），保证推断期引入的
//     类型变量 id 全局唯一。源 `Expr` 不含任何类型变量，故计数从 0 起即可。
//   * `infer_w` 自底向上同时产出**替换**与**带类型标注节点** `TExpr`，并严格
//     线程化（threading）累积替换：每次进入子表达式前，对运行中的 `TyEnv` 施加
//     已积累替换；每次合一前，对待合一类型施加已积累替换；合一所得替换复合进
//     累积替换。
//   * `let` 处做泛化（generalize），使用处做实例化（instantiate），实现 let 多态
//     （R4.2 / R4.3）。
//   * `let rec` 先以新鲜类型变量把 `f` 引入环境，使 `f` 在其自身绑定体内可见，
//     推断绑定体后再把该新鲜变量与绑定体类型合一（R4.6）。
//   * `if` 把条件合一为 `TyBool`、两分支互相合一（R4.4）。
//   * 应用引入新鲜结果变量 `r`，把函数类型合一为 `(typeof arg) -> r`（R4.5）。
//   * 合一失败时，把 `unify` 返回的（行列为哨兵 (0,0) 的）`TypeError` 诊断改写
//     为携带**出错节点 span** 的诊断（R8.3）；未绑定变量返回携带**变量 span**
//     与变量名的诊断（R8.4）。
//   * 入口 `infer` 在 `infer_w` 成功后，把最终累积替换施加到整棵 `TExpr` 的每个
//     类型标注上（`apply_subst_texpr`），使返回的类型在最终替换下封闭——这是
//     推断幂等（Property 7 / R4.9）与编译—执行链路所依赖的不变式。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增（R12.4）。

///|
/// 新鲜类型变量发生器：封装一个单调递增计数器。MoonBit 结构体为引用语义，
/// 故同一 `FreshGen` 对象在整条推断调用链上共享，`fresh` 的自增对所有持有者
/// 可见，保证类型变量 id 全局唯一（R4.3 / R4.6）。
pub struct FreshGen {
  mut counter : Int
}

///|
/// 构造一个从 0 起计数的新鲜类型变量发生器。
pub fn FreshGen::new() -> FreshGen {
  FreshGen::{ counter: 0 }
}

///|
/// 分配一个新鲜类型变量（`TyVar(id)`，id 唯一且自增）。
pub fn FreshGen::fresh(self : FreshGen) -> Ty {
  let v = self.counter
  self.counter = self.counter + 1
  TyVar(v)
}

///|
/// 取 `TExpr` 根节点的类型标注（主类型 / 子树类型）。
pub fn type_of(te : TExpr) -> Ty {
  match te {
    TEInt(_, t, _) => t
    TEBool(_, t, _) => t
    TEVar(_, t, _) => t
    TEArith(_, _, _, t, _) => t
    TECmp(_, _, _, t, _) => t
    TELogic(_, _, _, t, _) => t
    TEIf(_, _, _, t, _) => t
    TELam(_, _, t, _) => t
    TEApp(_, _, t, _) => t
    TELet(_, _, _, t, _) => t
    TELetRec(_, _, _, t, _) => t
    TETuple(_, t, _) => t
  }
}

///|
/// 把 `unify` 产出的（哨兵行列）类型错误诊断改写为携带出错节点 span 的诊断
/// （R8.3）：保留 kind 与冲突类型消息，仅填入精确行列。
fn with_span(d : Diagnostic, sp : Span) -> Diagnostic {
  Diagnostic::new(d.kind, sp.line, sp.col, d.msg)
}

///|
/// 在类型环境中查找变量名对应的类型方案（最近绑定优先，遮蔽语义）。
fn tyenv_lookup(env : TyEnv, name : String) -> Scheme? {
  env.schemes.lookup(name)
}

///|
/// 以 (name, scheme) 前插扩展类型环境（最近绑定在表头）。
fn tyenv_extend(env : TyEnv, name : String, sc : Scheme) -> TyEnv {
  TyEnv::{ schemes: env.schemes.prepend((name, sc)) }
}

///|
/// 对类型环境整体施加替换：对每个方案施加 `apply_scheme`（保护被量化变量）。
fn tyenv_apply(s : Subst, env : TyEnv) -> TyEnv {
  TyEnv::{ schemes: env.schemes.map(fn(kv) { (kv.0, apply_scheme(s, kv.1)) }) }
}

///|
/// 类型环境的自由类型变量集合：各方案体的自由变量并集，逐方案排除其被量化
/// 变量（量化变量不被环境约束）。用于 `generalize` 决定哪些变量可被泛化。
fn env_ftv(env : TyEnv) -> @sorted_set.SortedSet[Int] {
  let mut acc : @sorted_set.SortedSet[Int] = @sorted_set.SortedSet::new()
  for kv in env.schemes.iter() {
    let (_, sc) = kv
    let mut f = ftv(sc.body)
    for qv in sc.vars {
      f = f.remove(qv)
    }
    acc = acc.union(f)
  }
  acc
}

///|
/// 实例化类型方案：以新鲜类型变量替换其被全称量化的变量，得到一个具体类型
/// （R4.3）。各量化变量互异且新鲜变量全新，故单次施加即可。
pub fn instantiate(sc : Scheme, fresh : FreshGen) -> Ty {
  let mut s = subst_empty()
  for v in sc.vars {
    let fv = fresh.fresh()
    s = Subst::{ map: s.map.add(v, fv) }
  }
  apply_subst(s, sc.body)
}

///|
/// 泛化：把类型 `t` 中**不被环境约束**的自由类型变量全称量化为类型方案
/// （R4.2）。量化变量集 = `ftv(t) \ ftv(env)`。
pub fn generalize(env : TyEnv, t : Ty) -> Scheme {
  let env_vars = env_ftv(env)
  let vars = ftv(t).to_array().filter(fn(v) { !env_vars.contains(v) })
  Scheme::{ vars, body: t }
}

///|
/// 二元节点推断助手：推断左右子表达式，把二者类型分别合一到 `operand_ty`，
/// 失败时以节点 span 报错；成功时用 `build` 构造带结果类型的 `TExpr` 节点。
/// 线程化累积替换：推断右子前对环境施加左子替换，合一前对待合一类型施加累积
/// 替换。
fn infer_binop(
  env : TyEnv,
  l : Expr,
  r : Expr,
  fresh : FreshGen,
  operand_ty : Ty,
  sp : Span,
  build : (TExpr, TExpr) -> TExpr,
) -> Result[(Subst, TExpr), Diagnostic] {
  match infer_w(env, l, fresh) {
    Err(d) => Err(d)
    Ok((s1, tl)) => {
      let env1 = tyenv_apply(s1, env)
      match infer_w(env1, r, fresh) {
        Err(d) => Err(d)
        Ok((s2, tr)) => {
          let s12 = compose(s2, s1)
          match unify(apply_subst(s12, type_of(tl)), operand_ty) {
            Err(d) => Err(with_span(d, sp))
            Ok(s3) => {
              let s123 = compose(s3, s12)
              match unify(apply_subst(s123, type_of(tr)), operand_ty) {
                Err(d) => Err(with_span(d, sp))
                Ok(s4) => Ok((compose(s4, s123), build(tl, tr)))
              }
            }
          }
        }
      }
    }
  }
}

///|
/// Algorithm W 核心：自底向上同时产出累积替换与带类型标注的 `TExpr`（R4.1）。
fn infer_w(
  env : TyEnv,
  e : Expr,
  fresh : FreshGen,
) -> Result[(Subst, TExpr), Diagnostic] {
  match e {
    EInt(n, sp) => Ok((subst_empty(), TEInt(n, TyInt, sp)))
    EBool(b, sp) => Ok((subst_empty(), TEBool(b, TyBool, sp)))
    EVar(x, sp) =>
      match tyenv_lookup(env, x) {
        None =>
          Err(
            Diagnostic::new(
              TypeError,
              sp.line,
              sp.col,
              "未绑定变量 '\{x}'",
            ),
          )
        Some(sc) => {
          let t = instantiate(sc, fresh)
          Ok((subst_empty(), TEVar(x, t, sp)))
        }
      }
    EArith(op, l, r, sp) =>
      infer_binop(env, l, r, fresh, TyInt, sp, fn(tl, tr) {
        TEArith(op, tl, tr, TyInt, sp)
      })
    ECmp(op, l, r, sp) =>
      infer_binop(env, l, r, fresh, TyInt, sp, fn(tl, tr) {
        TECmp(op, tl, tr, TyBool, sp)
      })
    ELogic(op, l, r, sp) =>
      infer_binop(env, l, r, fresh, TyBool, sp, fn(tl, tr) {
        TELogic(op, tl, tr, TyBool, sp)
      })
    EIf(c, a, b, sp) =>
      match infer_w(env, c, fresh) {
        Err(d) => Err(d)
        Ok((s1, tc)) =>
          match unify(apply_subst(s1, type_of(tc)), TyBool) {
            Err(d) => Err(with_span(d, sp))
            Ok(s1b) => {
              let sa = compose(s1b, s1)
              match infer_w(tyenv_apply(sa, env), a, fresh) {
                Err(d) => Err(d)
                Ok((s2, ta)) => {
                  let sb = compose(s2, sa)
                  match infer_w(tyenv_apply(sb, env), b, fresh) {
                    Err(d) => Err(d)
                    Ok((s3, tb)) => {
                      let sc2 = compose(s3, sb)
                      match
                        unify(
                          apply_subst(sc2, type_of(ta)),
                          apply_subst(sc2, type_of(tb)),
                        ) {
                        Err(d) => Err(with_span(d, sp))
                        Ok(s4) => {
                          let s = compose(s4, sc2)
                          let rt = apply_subst(s, type_of(ta))
                          Ok((s, TEIf(tc, ta, tb, rt, sp)))
                        }
                      }
                    }
                  }
                }
              }
            }
          }
      }
    ELam(x, body, sp) => {
      let tv = fresh.fresh()
      let env1 = tyenv_extend(env, x, Scheme::{ vars: [], body: tv })
      match infer_w(env1, body, fresh) {
        Err(d) => Err(d)
        Ok((s1, tbody)) => {
          let fn_ty = TyFun(
            apply_subst(s1, tv),
            apply_subst(s1, type_of(tbody)),
          )
          Ok((s1, TELam(x, tbody, fn_ty, sp)))
        }
      }
    }
    EApp(f, a, sp) =>
      match infer_w(env, f, fresh) {
        Err(d) => Err(d)
        Ok((s1, tf)) =>
          match infer_w(tyenv_apply(s1, env), a, fresh) {
            Err(d) => Err(d)
            Ok((s2, ta)) => {
              let s12 = compose(s2, s1)
              let r = fresh.fresh()
              match
                unify(
                  apply_subst(s12, type_of(tf)),
                  TyFun(apply_subst(s12, type_of(ta)), r),
                ) {
                Err(d) => Err(with_span(d, sp))
                Ok(s3) => {
                  let s = compose(s3, s12)
                  let rt = apply_subst(s, r)
                  Ok((s, TEApp(tf, ta, rt, sp)))
                }
              }
            }
          }
      }
    ELet(x, e1, e2, sp) =>
      match infer_w(env, e1, fresh) {
        Err(d) => Err(d)
        Ok((s1, t1)) => {
          let env1 = tyenv_apply(s1, env)
          let sc = generalize(env1, apply_subst(s1, type_of(t1)))
          match infer_w(tyenv_extend(env1, x, sc), e2, fresh) {
            Err(d) => Err(d)
            Ok((s2, t2)) => {
              let s = compose(s2, s1)
              let rt = apply_subst(s, type_of(t2))
              Ok((s, TELet(x, t1, t2, rt, sp)))
            }
          }
        }
      }
    ELetRec(f, e1, e2, sp) => {
      let tv = fresh.fresh()
      let env_f = tyenv_extend(env, f, Scheme::{ vars: [], body: tv })
      match infer_w(env_f, e1, fresh) {
        Err(d) => Err(d)
        Ok((s1, t1)) =>
          match unify(apply_subst(s1, tv), apply_subst(s1, type_of(t1))) {
            Err(d) => Err(with_span(d, sp))
            Ok(s1b) => {
              let s = compose(s1b, s1)
              let env1 = tyenv_apply(s, env)
              let sc = generalize(env1, apply_subst(s, type_of(t1)))
              match infer_w(tyenv_extend(env1, f, sc), e2, fresh) {
                Err(d) => Err(d)
                Ok((s2, t2)) => {
                  let sfinal = compose(s2, s)
                  let rt = apply_subst(sfinal, type_of(t2))
                  Ok((sfinal, TELetRec(f, t1, t2, rt, sp)))
                }
              }
            }
          }
      }
    }
    ETuple(items, sp) => {
      let mut s = subst_empty()
      let typed : Array[TExpr] = []
      for it in items {
        match infer_w(tyenv_apply(s, env), it, fresh) {
          Err(d) => return Err(d)
          Ok((si, ti)) => {
            s = compose(si, s)
            typed.push(ti)
          }
        }
      }
      let tys = typed.map(fn(te) { apply_subst(s, type_of(te)) })
      Ok((s, TETuple(typed, TyTuple(tys), sp)))
    }
  }
}

///|
/// 把最终累积替换施加到整棵 `TExpr` 的每个类型标注上，使返回类型在最终替换下
/// 封闭（R4.9 所依赖的不变式）。递归进入全部子表达式与元组分量。
fn apply_subst_texpr(s : Subst, te : TExpr) -> TExpr {
  match te {
    TEInt(n, t, sp) => TEInt(n, apply_subst(s, t), sp)
    TEBool(b, t, sp) => TEBool(b, apply_subst(s, t), sp)
    TEVar(x, t, sp) => TEVar(x, apply_subst(s, t), sp)
    TEArith(op, l, r, t, sp) =>
      TEArith(
        op,
        apply_subst_texpr(s, l),
        apply_subst_texpr(s, r),
        apply_subst(s, t),
        sp,
      )
    TECmp(op, l, r, t, sp) =>
      TECmp(
        op,
        apply_subst_texpr(s, l),
        apply_subst_texpr(s, r),
        apply_subst(s, t),
        sp,
      )
    TELogic(op, l, r, t, sp) =>
      TELogic(
        op,
        apply_subst_texpr(s, l),
        apply_subst_texpr(s, r),
        apply_subst(s, t),
        sp,
      )
    TEIf(c, a, b, t, sp) =>
      TEIf(
        apply_subst_texpr(s, c),
        apply_subst_texpr(s, a),
        apply_subst_texpr(s, b),
        apply_subst(s, t),
        sp,
      )
    TELam(x, body, t, sp) =>
      TELam(x, apply_subst_texpr(s, body), apply_subst(s, t), sp)
    TEApp(f, a, t, sp) =>
      TEApp(
        apply_subst_texpr(s, f),
        apply_subst_texpr(s, a),
        apply_subst(s, t),
        sp,
      )
    TELet(x, e1, e2, t, sp) =>
      TELet(
        x,
        apply_subst_texpr(s, e1),
        apply_subst_texpr(s, e2),
        apply_subst(s, t),
        sp,
      )
    TELetRec(f, e1, e2, t, sp) =>
      TELetRec(
        f,
        apply_subst_texpr(s, e1),
        apply_subst_texpr(s, e2),
        apply_subst(s, t),
        sp,
      )
    TETuple(items, t, sp) =>
      TETuple(
        items.map(fn(x) { apply_subst_texpr(s, x) }),
        apply_subst(s, t),
        sp,
      )
  }
}

///|
/// 推断入口（R4.1 / R4.7 / R4.8 / R4.9）：以空类型环境跑 Algorithm W。成功时把
/// 最终替换施加到整棵带类型标注语法树后，返回 `(TExpr, 主类型)`；失败时返回携带
/// span 与冲突类型 / 变量名的诊断。
pub fn infer(e : Expr) -> Result[(TExpr, Ty), Diagnostic] {
  let fresh = FreshGen::new()
  let env = TyEnv::{ schemes: @list.List::new() }
  match infer_w(env, e, fresh) {
    Err(d) => Err(d)
    Ok((s, te)) => {
      let te2 = apply_subst_texpr(s, te)
      Ok((te2, type_of(te2)))
    }
  }
}
