// row_poly.mbt —— T1.3 类型推断深化：行多态（row polymorphism）记录类型合一
// （paper-to-code：Rémy 1993 / Gaster & Jones 1996 "A Polymorphic Type System
// for Extensible Records and Variants" 的行合一算法，特化到记录）。
//
// 旁路新增（freeze + bypass）：既有 `Ty` 不含记录构造子，本文件引入自含的
// **行类型层** `RTy`，与既有推断互不侵入：
//
//   RTy ::= RInt | RBool | RFun(RTy, RTy) | RVar(id)      —— 常规类型
//         | RRecord(Row)                                   —— 记录类型
//   Row ::= REmpty                                         —— 封闭行 {}
//         | RowVar(id)                                     —— 行变量 ρ
//         | RExtend(label, RTy, Row)                       —— {l : t | r}
//
// 关键操作 `rewrite_row(row, l)`：把行改写为以标签 `l` 打头的形态——
//   * 行中已含 `l` ⇒ 直接提到头部（标签集合无序，字段顺序不影响相等）；
//   * 行尾为行变量 ρ ⇒ 以 `ρ ↦ {l : β | ρ'}`（β、ρ' 新鲜）扩张（吸收缺字段）；
//   * 封闭行且缺 `l` ⇒ 合一失败（记录缺少字段）。
//
// 由此 `{x: Int | ρ₁} ~ {y: Bool | ρ₂}` 可解：ρ₁ 吸收 y、ρ₂ 吸收 x，
// 即**开放记录**（结构子类型效果）；封闭记录则要求标签集合恰好相等。

///|
/// 行多态层的类型项。
pub(all) enum RTy {
  RInt
  RBool
  RFun(RTy, RTy)
  RVar(Int)
  RRecord(Row)
} derive(Eq)

///|
/// 行（record row）：字段序列 + 封闭（REmpty）或开放（RowVar）行尾。
pub(all) enum Row {
  REmpty
  RowVar(Int)
  RExtend(String, RTy, Row)
} derive(Eq)

///|
/// 手写 Show：规避 derive(Debug) 弃用告警，与本包其他类型一致。
pub impl Show for RTy with fn output(self : RTy, logger : &Logger) -> Unit {
  match self {
    RInt => logger.write_string("RInt")
    RBool => logger.write_string("RBool")
    RFun(a, b) => {
      logger.write_string("RFun(")
      Show::output(a, logger)
      logger.write_string(", ")
      Show::output(b, logger)
      logger.write_string(")")
    }
    RVar(v) => {
      logger.write_string("RVar(")
      logger.write_string(v.to_string())
      logger.write_string(")")
    }
    RRecord(r) => {
      logger.write_string("RRecord(")
      Show::output(r, logger)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for Row with fn output(self : Row, logger : &Logger) -> Unit {
  match self {
    REmpty => logger.write_string("REmpty")
    RowVar(v) => {
      logger.write_string("RowVar(")
      logger.write_string(v.to_string())
      logger.write_string(")")
    }
    RExtend(l, t, rest) => {
      logger.write_string("RExtend(")
      logger.write_string(l)
      logger.write_string(": ")
      Show::output(t, logger)
      logger.write_string(" | ")
      Show::output(rest, logger)
      logger.write_string(")")
    }
  }
}

///|
/// 行层替换：类型变量与行变量两张绑定表。
pub(all) struct RSubst {
  tys : Map[Int, RTy]
  rows : Map[Int, Row]
}

///|
/// 空替换。
pub fn RSubst::empty() -> RSubst {
  { tys: Map([]), rows: Map([]) }
}

///|
/// 对类型项施加替换（追链到不动点）。
pub fn apply_rty(s : RSubst, t : RTy) -> RTy {
  match t {
    RInt | RBool => t
    RVar(v) =>
      match s.tys.get(v) {
        Some(bound) => apply_rty(s, bound)
        None => t
      }
    RFun(a, b) => RFun(apply_rty(s, a), apply_rty(s, b))
    RRecord(r) => RRecord(apply_row(s, r))
  }
}

///|
/// 对行施加替换。
pub fn apply_row(s : RSubst, r : Row) -> Row {
  match r {
    REmpty => REmpty
    RowVar(v) =>
      match s.rows.get(v) {
        Some(bound) => apply_row(s, bound)
        None => r
      }
    RExtend(l, t, rest) => RExtend(l, apply_rty(s, t), apply_row(s, rest))
  }
}

///|
/// 新鲜变量发生器（类型变量与行变量共用计数）。
pub(all) struct RFresh {
  mut next : Int
}

///|
pub fn RFresh::new(start : Int) -> RFresh {
  { next: start }
}

///|
fn RFresh::fresh(self : RFresh) -> Int {
  let v = self.next
  self.next = self.next + 1
  v
}

///|
/// 规范化：施加替换后把记录字段按标签升序重排（行相等是**模字段重排**的，
/// 直接结构比较前先规范化）。
pub fn normalize_rty(s : RSubst, t : RTy) -> RTy {
  match apply_rty(s, t) {
    RInt => RInt
    RBool => RBool
    RVar(v) => RVar(v)
    RFun(a, b) => RFun(normalize_rty(s, a), normalize_rty(s, b))
    RRecord(r) => RRecord(normalize_row(s, r))
  }
}

///|
/// 行规范化：字段按标签升序、字段类型递归规范化，行尾保持。
pub fn normalize_row(s : RSubst, r : Row) -> Row {
  let fields : Array[(String, RTy)] = []
  let mut cur = apply_row(s, r)
  while true {
    match cur {
      RExtend(l, t, rest) => {
        fields.push((l, normalize_rty(s, t)))
        cur = rest
      }
      _ => break
    }
  }
  fields.sort_by(fn(a, b) { a.0.compare(b.0) })
  let mut out = cur
  let mut i = fields.length() - 1
  while i >= 0 {
    out = RExtend(fields[i].0, fields[i].1, out)
    i = i - 1
  }
  out
}

///|
/// occurs-check：类型变量出现于类型项。
fn r_occurs_ty(v : Int, t : RTy) -> Bool {
  match t {
    RInt | RBool => false
    RVar(w) => v == w
    RFun(a, b) => r_occurs_ty(v, a) || r_occurs_ty(v, b)
    RRecord(r) => r_occurs_ty_row(v, r)
  }
}

///|
fn r_occurs_ty_row(v : Int, r : Row) -> Bool {
  match r {
    REmpty | RowVar(_) => false
    RExtend(_, t, rest) => r_occurs_ty(v, t) || r_occurs_ty_row(v, rest)
  }
}

///|
/// 行变量出现于行尾（含字段类型内的记录嵌套）。
fn r_occurs_row(v : Int, r : Row) -> Bool {
  match r {
    REmpty => false
    RowVar(w) => v == w
    RExtend(_, t, rest) => r_occurs_row_ty(v, t) || r_occurs_row(v, rest)
  }
}

///|
fn r_occurs_row_ty(v : Int, t : RTy) -> Bool {
  match t {
    RInt | RBool | RVar(_) => false
    RFun(a, b) => r_occurs_row_ty(v, a) || r_occurs_row_ty(v, b)
    RRecord(r) => r_occurs_row(v, r)
  }
}

///|
/// 把行改写为以标签 `l` 打头的形态（Gaster–Jones 行重排引理）。成功返回
/// `(l 的字段类型, 余行)`；行尾为行变量时以新鲜变量扩张并把绑定写入 `s`。
fn rewrite_row(
  s : RSubst,
  fresh : RFresh,
  row : Row,
  l : String,
) -> Result[(RTy, Row), String] {
  match apply_row(s, row) {
    REmpty => Err("record lacks field '" + l + "'")
    RowVar(v) => {
      // ρ ↦ {l : β | ρ'}，β / ρ' 新鲜。
      let beta = RVar(fresh.fresh())
      let rho2 = RowVar(fresh.fresh())
      s.rows[v] = RExtend(l, beta, rho2)
      Ok((beta, rho2))
    }
    RExtend(l2, t2, rest) =>
      if l2 == l {
        Ok((t2, rest))
      } else {
        match rewrite_row(s, fresh, rest, l) {
          Err(e) => Err(e)
          Ok((tl, rest2)) => Ok((tl, RExtend(l2, t2, rest2)))
        }
      }
  }
}

///|
/// 行尾行变量（若开放行）。
fn row_tail_var(s : RSubst, r : Row) -> Int? {
  match apply_row(s, r) {
    REmpty => None
    RowVar(v) => Some(v)
    RExtend(_, _, rest) => row_tail_var(s, rest)
  }
}

///|
/// 行多态合一（T1.3）：产出使两类型相等的替换（就地累积在 `s`），失败返回
/// 确定性消息。记录合一逐标签重排（字段顺序无关），开放行经行变量吸收缺
/// 字段，封闭行要求标签集合恰好相等；行变量绑定前做 occurs-check 防止
/// 无限行。
pub fn unify_rty(
  s : RSubst,
  fresh : RFresh,
  t1 : RTy,
  t2 : RTy,
) -> Result[Unit, String] {
  let a = apply_rty(s, t1)
  let b = apply_rty(s, t2)
  match (a, b) {
    (RInt, RInt) | (RBool, RBool) => Ok(())
    (RVar(v), RVar(w)) => {
      if v != w {
        s.tys[v] = RVar(w)
      }
      Ok(())
    }
    (RVar(v), other) | (other, RVar(v)) =>
      if r_occurs_ty(v, other) {
        Err("occurs check: infinite type via t" + v.to_string())
      } else {
        s.tys[v] = other
        Ok(())
      }
    (RFun(a1, b1), RFun(a2, b2)) =>
      match unify_rty(s, fresh, a1, a2) {
        Err(e) => Err(e)
        Ok(_) => unify_rty(s, fresh, b1, b2)
      }
    (RRecord(r1), RRecord(r2)) => unify_row(s, fresh, r1, r2)
    (x, y) => Err("cannot unify \{x} with \{y}")
  }
}

///|
/// 行合一：逐字段重排对齐。
fn unify_row(
  s : RSubst,
  fresh : RFresh,
  r1 : Row,
  r2 : Row,
) -> Result[Unit, String] {
  let a = apply_row(s, r1)
  let b = apply_row(s, r2)
  match (a, b) {
    (REmpty, REmpty) => Ok(())
    (RowVar(v), RowVar(w)) => {
      if v != w {
        s.rows[v] = RowVar(w)
      }
      Ok(())
    }
    (RowVar(v), other) | (other, RowVar(v)) =>
      if r_occurs_row(v, other) {
        Err("occurs check: infinite row via r" + v.to_string())
      } else {
        s.rows[v] = other
        Ok(())
      }
    (RExtend(l, t, rest), _) => {
      // Gaster–Jones 副条件：改写 b 期间 a 的行尾变量不得被绑定（防循环）。
      let tail_before = row_tail_var(s, rest)
      match rewrite_row(s, fresh, b, l) {
        Err(e) => Err(e)
        Ok((t2, rest2)) => {
          match tail_before {
            Some(v) =>
              if s.rows.contains(v) {
                return Err("recursive row via r" + v.to_string())
              }
            None => ()
          }
          match unify_rty(s, fresh, t, t2) {
            Err(e) => Err(e)
            Ok(_) => unify_row(s, fresh, rest, rest2)
          }
        }
      }
    }
    (REmpty, RExtend(l, _, _)) => Err("record lacks field '" + l + "'")
  }
}
