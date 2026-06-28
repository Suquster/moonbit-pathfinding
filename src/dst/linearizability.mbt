// linearizability.mbt —— DST_Framework 旗舰深化：线性一致性检查（旁路新增，设计 4.10）。
//
// paper-to-code 追溯：Herlihy & Wing 1990《Linearizability》与 Wing & Gong 线性化点
// 方法；对标 Jepsen / Knossos 的历史一致性检查（纯内存模型下的对应实现）。
//
// 线性一致性（linearizability）：并发历史可被重排为某个**保持实时先后序**
// （一个操作的返回早于另一个的调用 → 前者在线性顺序中居前）且**满足顺序规约**的
// 合法顺序历史。本检查以回溯搜索逐步选取一个「实时极小且在当前状态下合法」的已
// 完成操作并应用到顺序模型，直至清空历史；无法清空即非线性一致并报告冲突操作
// （R7.4 / R7.5）。顺序规约为单寄存器 / 单键 KV：`put` 改写当前值，`get` 须读到
// 当前值。可选能力（`WHERE` 启用）。

///|
/// 操作事件类别：调用（`Invoke`）或返回（`Return`）。
pub(all) enum OpKind {
  Invoke
  Return
} derive(Eq, Debug)

///|
/// 操作事件（operation event）—— 历史的基本元素。
///
///   * `proc` —— 发起操作的客户端 / 进程；
///   * `kind` —— 调用 / 返回；
///   * `op`   —— 操作名（`"put"` / `"get"`）；
///   * `arg`  —— 调用参数（`put` 的写入值）；
///   * `ret`  —— 返回值（`get` 的读出值）；
///   * `time` —— 事件发生的逻辑时间（实时先后序据此判定）。
pub(all) struct OpEvent {
  proc : Int
  kind : OpKind
  op : String
  arg : Int
  ret : Int
  time : LogicalTime
} derive(Eq, Debug)

///|
/// 构造一个调用事件。
pub fn OpEvent::invoke(
  proc : Int,
  op : String,
  arg : Int,
  time : LogicalTime,
) -> OpEvent {
  { proc, kind: Invoke, op, arg, ret: 0, time }
}

///|
/// 构造一个返回事件。
pub fn OpEvent::ret(
  proc : Int,
  op : String,
  ret : Int,
  time : LogicalTime,
) -> OpEvent {
  { proc, kind: Return, op, arg: 0, ret, time }
}

///|
/// 历史（history）—— 操作的调用 / 返回事件按时间排列的序列。
pub type History = Array[OpEvent]

///|
/// 顺序规约：单寄存器 / 单键 KV，`init` 为初始值。
pub(all) struct RegisterModel {
  init : Int
} derive(Eq, Debug)

///|
/// 线性一致性判定结果：线性一致 `Linearizable`，或非线性一致 `NotLinearizable`
/// 并携带导致冲突的操作事件（R7.5）。
pub(all) enum LinResult {
  Linearizable
  NotLinearizable(conflict~ : Array[OpEvent])
} derive(Eq, Debug)

///|
/// 内部完成操作（complete operation）：由配对的调用 / 返回事件构成。
priv struct LinOp {
  op : String
  arg : Int
  ret : Int
  inv : LogicalTime
  ret_t : LogicalTime
  inv_ev : OpEvent
  ret_ev : OpEvent
}

///|
/// 由历史配对出完成操作序列（同一进程的调用 / 返回按 FIFO 配对）。未配对事件忽略。
fn build_ops(history : Array[OpEvent]) -> Array[LinOp] {
  let mut open : Array[OpEvent] = []
  let ops : Array[LinOp] = []
  for ev in history {
    match ev.kind {
      Invoke => open.push(ev)
      Return => {
        let mut mi = -1
        for i in 0..<open.length() {
          if open[i].proc == ev.proc {
            mi = i
            break
          }
        }
        if mi >= 0 {
          let inv = open[mi]
          let no : Array[OpEvent] = []
          for i in 0..<open.length() {
            if i != mi {
              no.push(open[i])
            }
          }
          open = no
          ops.push({
            op: inv.op,
            arg: inv.arg,
            ret: ev.ret,
            inv: inv.time,
            ret_t: ev.time,
            inv_ev: inv,
            ret_ev: ev,
          })
        }
      }
    }
  }
  ops
}

///|
/// 在状态 `state` 下应用操作：返回 `(是否合法, 新状态)`。`put` 恒合法并改写值；
/// `get` 须读到当前值；其余操作视为合法的无副作用读。
fn apply_op(o : LinOp, state : Int) -> (Bool, Int) {
  if o.op == "put" {
    (true, o.arg)
  } else if o.op == "get" {
    (o.ret == state, state)
  } else {
    (true, state)
  }
}

///|
/// 回溯搜索：是否存在保持实时先后序且满足顺序规约的线性化。
fn linearize(ops : Array[LinOp], state : Int) -> Bool {
  if ops.length() == 0 {
    return true
  }
  for i in 0..<ops.length() {
    let o = ops[i]
    // 实时极小：不存在另一操作完全先于 o（其返回早于 o 的调用）。
    let mut minimal = true
    for j in 0..<ops.length() {
      if j != i && ops[j].ret_t < o.inv {
        minimal = false
        break
      }
    }
    if !minimal {
      continue
    }
    let (ok, new_state) = apply_op(o, state)
    if ok {
      let rest : Array[LinOp] = []
      for k in 0..<ops.length() {
        if k != i {
          rest.push(ops[k])
        }
      }
      if linearize(rest, new_state) {
        return true
      }
    }
  }
  false
}

///|
/// Wing & Gong 线性化点检查：在寄存器 / 单键 KV 顺序规约下判定历史是否线性一致。
/// 线性一致返回 `Linearizable`；否则返回 `NotLinearizable` 并携带冲突操作（R7.4/7.5）。
pub fn is_linearizable(
  history : Array[OpEvent],
  model : RegisterModel,
) -> LinResult {
  let ops = build_ops(history)
  if linearize(ops, model.init) {
    Linearizable
  } else {
    let conflict : Array[OpEvent] = []
    for o in ops {
      conflict.push(o.inv_ev)
      conflict.push(o.ret_ev)
    }
    NotLinearizable(conflict~)
  }
}
