// ml_eval.mbt —— MiniML 树遍历解释器与作用域检查（design.md §「组件与接口 →
// 7. 树遍历解释器」，覆盖 R5.1 ~ R5.8 与 R8.4 / R8.6）。
//
// 设计要点（对标 Pierce《TAPL》求值规则与 Nystrom《Crafting Interpreters》
// jlox 的树遍历解释器）：
//   * 以**不可变求值环境** `Env`（`@list.List[(String, Val)]`，最近绑定在表头）
//     承载绑定；遮蔽（shadowing）由「表头优先」的查找自然实现（R5.5）。
//   * 函数抽象（`lambda` / `fun`）求值为捕获**当前**环境的 `VClosure`，使函数
//     成为一等值并遵循**词法作用域**（R5.2）。应用在闭包**捕获环境**上扩展
//     形参→实参绑定后求值函数体（R5.3）。
//   * 二元算术沿用 MiniLet 既有语义（见 semantics.mbt）：`Add`/`Sub`/`Mul` 为
//     32 位环绕算术，`Div` 截断除法且**除零定义为 `0`**——使 `eval_ml` 为全
//     函数、求值确定、三后端一致（R5.4）。
//   * 比较 / 逻辑产出 `VBool`；逻辑 `&&` / `||` 求值两侧后取与 / 或（不短路，
//     与是否短路无可观察差异，因 MiniML 无副作用且为全函数——保持确定性）。
//
// 关于 `let rec`（R5.6，**自指递归而不构造物理回边**）：
//   不可变环境无法在持有闭包的同时令闭包捕获「包含自身的环境」（会形成物理
//   循环引用，且 MoonBit 不可变结构亦无法构造）。本实现采用**延迟按名查找**：
//   对 `let rec f = λx. body in e2`，在环境中以**哨兵键** `rec_key(f)`（即
//   `"#rec#" ++ f`，因 MiniML 标识符不含 `#` 故不可能与用户名字冲突）存入一条
//   「递归记录」`VClosure(x, body, env_outer)`。变量查找 `ml_env_lookup` 自表头
//   向表尾扫描（尊重遮蔽）：
//     - 命中普通绑定 `name` → 直接返回（包含内层普通绑定遮蔽递归函数的情形）；
//     - 命中 `rec_key(name)` 记录 → **就地重建**一个闭包，其捕获环境为
//       `env_outer` 再加上同一条 `rec_key(name)` 记录。
//   于是闭包每次被应用、其体内对 `f` 的引用都会再次命中该记录并再次重建闭包，
//   从而支持任意深度递归；而递归记录的捕获环境恒为有限的 `env_outer`，**不含
//   任何物理回边**，三后端行为一致。逃逸的递归闭包（作为返回值 / 实参传出）亦
//   因其捕获环境携带该记录而仍可正确递归。
//
// 作用域检查 `scope_check_ml`（R8.6 / R8.4）：在**类型推断前**独立验证闭合性。
// 以不可变名字集合遍历 `Expr`，`ELam` 在体内引入形参、`ELet` 在 body 引入绑定
// 名（不在 e1）、`ELetRec` 在 e1 与 e2 **均**引入递归名；遇到不在作用域内的
// `EVar` 即返回携带该变量 span 行列与变量名的 `TypeError` 诊断（R8.4）。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增（R12.4）。

// ---------------------------------------------------------------------------
// 求值环境（不可变，最近绑定在表头）
// ---------------------------------------------------------------------------

///|
/// 空求值环境。
pub fn ml_env_empty() -> Env {
  Env::{ bindings: @list.List::new() }
}

///|
/// 以 `(name, value)` 前插扩展环境（最近绑定在表头，实现遮蔽语义，R5.5）。
/// 命名加 `ml_` 前缀以避免与 semantics.mbt 中 MiniLet（基于 `Array`）的同名
/// 助手冲突。
pub fn ml_env_extend(env : Env, name : String, value : Val) -> Env {
  Env::{ bindings: env.bindings.prepend((name, value)) }
}

///|
/// 递归绑定的哨兵键：`"#rec#" ++ name`。MiniML 标识符由 `scan_ident` 产出，
/// 形如 `[A-Za-z][A-Za-z0-9_]*`，绝不含 `#`，故该键不可能与任何用户变量名
/// 冲突——用于在环境中区分「普通绑定」与「`let rec` 递归记录」。
fn rec_key(name : String) -> String {
  "#rec#" + name
}

///|
/// 环境查找（延迟按名查找，支撑 `let rec` 自指递归且尊重遮蔽，R5.5 / R5.6）。
///
/// 自表头（最近）向表尾（最旧）扫描，对每条绑定 `(k, v)`：
///   * `k == name`：普通绑定命中，直接返回 `v`（内层普通绑定可遮蔽外层及
///     递归记录）。
///   * `k == rec_key(name)`：递归记录命中，**就地重建**递归闭包——其捕获环境
///     为记录所携带的 `defEnv` 再加上同一条递归记录，使闭包体内对该名字的引用
///     再次命中记录并再次重建，从而支持任意深度递归（无物理回边）。
///
/// 首个命中者（普通或递归）胜出，从而最近绑定优先（遮蔽）。
fn ml_env_lookup(env : Env, name : String) -> Val? {
  let rk = rec_key(name)
  for kv in env.bindings.iter() {
    let (k, v) = kv
    if k == name {
      return Some(v)
    }
    if k == rk {
      return Some(
        match v {
          VClosure(px, pbody, def_env) =>
            VClosure(px, pbody, ml_env_extend(def_env, rk, v))
          _ => v
        },
      )
    }
  }
  None
}

// ---------------------------------------------------------------------------
// 运行期值的全函数投影助手（输入经 infer 保证类型正确，回退仅为保持全函数）
// ---------------------------------------------------------------------------

///|
/// 取整数值；非整数值回退为 `0`（经 `infer` 的程序不会触发回退，仅保证全函数）。
fn as_int(v : Val) -> Int {
  match v {
    VInt(n) => n
    _ => 0
  }
}

///|
/// 取布尔值；非布尔值回退为 `false`（同上，仅保证全函数）。
fn as_bool(v : Val) -> Bool {
  match v {
    VBool(b) => b
    _ => false
  }
}

///|
/// 施加二元整数运算；除零定义为 `0`（沿用 MiniLet 约定，R5.4，保证全函数且
/// 三后端一致）。
fn ml_apply_arith(op : BinOp, a : Int, b : Int) -> Int {
  match op {
    Add => a + b
    Sub => a - b
    Mul => a * b
    Div => if b == 0 { 0 } else { a / b }
  }
}

///|
/// 施加比较运算，产出布尔结果。
fn ml_apply_cmp(op : CmpOp, a : Int, b : Int) -> Bool {
  match op {
    Lt => a < b
    Le => a <= b
    Gt => a > b
    Ge => a >= b
    Eq_ => a == b
    Ne => a != b
  }
}

// ---------------------------------------------------------------------------
// 求值器
// ---------------------------------------------------------------------------

///|
/// 在给定环境对带类型标注 `TExpr` 求值（树遍历解释器核心，R5.1）。
fn eval_env(te : TExpr, env : Env) -> Val {
  match te {
    TEInt(n, _, _) => VInt(n)
    TEBool(b, _, _) => VBool(b)
    TEVar(x, _, _) =>
      // 经 infer/作用域检查的程序变量必有绑定；None 仅为全函数回退（R5.8）。
      match ml_env_lookup(env, x) {
        Some(v) => v
        None => VInt(0)
      }
    TEArith(op, l, r, _, _) => {
      let a = as_int(eval_env(l, env))
      let b = as_int(eval_env(r, env))
      VInt(ml_apply_arith(op, a, b))
    }
    TECmp(op, l, r, _, _) => {
      let a = as_int(eval_env(l, env))
      let b = as_int(eval_env(r, env))
      VBool(ml_apply_cmp(op, a, b))
    }
    TELogic(op, l, r, _, _) => {
      let a = as_bool(eval_env(l, env))
      let b = as_bool(eval_env(r, env))
      VBool(
        match op {
          And => a && b
          Or => a || b
        },
      )
    }
    TEIf(c, a, b, _, _) =>
      if as_bool(eval_env(c, env)) {
        eval_env(a, env)
      } else {
        eval_env(b, env)
      }
    // 函数抽象 → 捕获当前环境的闭包（词法作用域，R5.2）。
    TELam(x, body, _, _) => VClosure(x, body, env)
    // 应用 → 在闭包捕获环境上扩展形参绑定后求值体（R5.3）。
    TEApp(f, a, _, _) => {
      let fv = eval_env(f, env)
      let av = eval_env(a, env)
      match fv {
        VClosure(px, body, cap) => eval_env(body, ml_env_extend(cap, px, av))
        // 经类型检查的程序应用位必为闭包；回退保持全函数（R5.8）。
        _ => VInt(0)
      }
    }
    // let：在外层环境求值 e1，再在扩展环境求值 e2（非递归，R5.1）。
    TELet(x, e1, e2, _, _) => {
      let v = eval_env(e1, env)
      eval_env(e2, ml_env_extend(env, x, v))
    }
    // let rec：以哨兵键存入递归记录，按名延迟查找实现自指递归（R5.6）。
    TELetRec(f, e1, e2, _, _) => eval_env(e2, bind_rec(env, f, e1))
    TETuple(items, _, _) => VTuple(items.map(fn(it) { eval_env(it, env) }))
  }
}

///|
/// 为 `let rec f = e1 in ...` 在环境中引入 `f` 的绑定（R5.6）。
///
/// * `e1` 为函数抽象 `TELam(x, body)`：以哨兵键 `rec_key(f)` 存入递归记录
///   `VClosure(x, body, env)`（捕获环境为外层 `env`，**不含物理回边**）。
///   后续对 `f` 的查找将就地重建带递归记录的闭包（见 `ml_env_lookup`）。
/// * `e1` 非函数抽象（如 `let rec x = 5 in ...`）：退化为普通绑定——在外层
///   环境求值 `e1` 后将其值绑定到 `f`。此时 `f` 不出现在 `e1` 的作用域内，
///   符合「递归仅对函数有意义」的直觉，并保持 `eval_env` 为全函数。
fn bind_rec(env : Env, f : String, e1 : TExpr) -> Env {
  match e1 {
    TELam(px, pbody, _, _) =>
      ml_env_extend(env, rec_key(f), VClosure(px, pbody, env))
    _ => ml_env_extend(env, f, eval_env(e1, env))
  }
}

///|
/// 求值入口（R5.1）：以空环境对带类型标注 `TExpr` 做树遍历解释，产出 `Val`。
/// 输入应为经 `infer` 产出的良类型 `TExpr`；求值为全函数（除零=0、变量必有
/// 绑定），故不卡住（R5.8）且确定（R5.7）。
pub fn eval_ml(te : TExpr) -> Val {
  eval_env(te, ml_env_empty())
}

// ---------------------------------------------------------------------------
// 作用域检查（R8.6 / R8.4）
// ---------------------------------------------------------------------------

///|
/// 作用域名字集合是否包含 `name`（自表头向表尾扫描）。
fn scope_has(scope : @list.List[String], name : String) -> Bool {
  for n in scope.iter() {
    if n == name {
      return true
    }
  }
  false
}

///|
/// 作用域检查：验证 `Expr` 的全部变量引用都能解析到某个绑定（R8.6）。
///
/// 返回 `Ok(())` 当且仅当不存在自由变量；否则返回携带首个自由变量的 span 行列
/// 与变量名的 `TypeError` 诊断（R8.4）。可用于在推断前后独立验证闭合性，并支撑
/// 作用域属性测试（Property 14）。
pub fn scope_check_ml(e : Expr) -> Result[Unit, Diagnostic] {
  scope_check_go(e, @list.List::new())
}

///|
/// 作用域检查递归助手：`scope` 为当前可见的绑定名（最近引入者在表头）。
fn scope_check_go(
  e : Expr,
  scope : @list.List[String],
) -> Result[Unit, Diagnostic] {
  match e {
    EInt(_, _) => Ok(())
    EBool(_, _) => Ok(())
    EVar(x, sp) =>
      if scope_has(scope, x) {
        Ok(())
      } else {
        Err(
          Diagnostic::new(TypeError, sp.line, sp.col, "未绑定变量 '\{x}'"),
        )
      }
    EArith(_, l, r, _) => check_two(l, r, scope)
    ECmp(_, l, r, _) => check_two(l, r, scope)
    ELogic(_, l, r, _) => check_two(l, r, scope)
    EIf(c, a, b, _) =>
      match scope_check_go(c, scope) {
        Err(d) => Err(d)
        Ok(_) => check_two(a, b, scope)
      }
    // 形参在函数体内可见。
    ELam(x, body, _) => scope_check_go(body, scope.prepend(x))
    EApp(f, a, _) => check_two(f, a, scope)
    // 非递归 let：e1 在外层作用域检查；body 在引入 name 后检查。
    ELet(name, e1, e2, _) =>
      match scope_check_go(e1, scope) {
        Err(d) => Err(d)
        Ok(_) => scope_check_go(e2, scope.prepend(name))
      }
    // 递归 let：name 在 e1 与 e2 **均**可见（R5.6 的静态对应）。
    ELetRec(name, e1, e2, _) => {
      let scope1 = scope.prepend(name)
      match scope_check_go(e1, scope1) {
        Err(d) => Err(d)
        Ok(_) => scope_check_go(e2, scope1)
      }
    }
    ETuple(items, _) => {
      for it in items {
        match scope_check_go(it, scope) {
          Err(d) => return Err(d)
          Ok(_) => continue
        }
      }
      Ok(())
    }
  }
}

///|
/// 依次检查两个子表达式，向上传播首个诊断。
fn check_two(
  l : Expr,
  r : Expr,
  scope : @list.List[String],
) -> Result[Unit, Diagnostic] {
  match scope_check_go(l, scope) {
    Err(d) => Err(d)
    Ok(_) => scope_check_go(r, scope)
  }
}
