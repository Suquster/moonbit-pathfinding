// streaming.mbt —— L1 流式 / 增量输入（incremental / streaming input）。
//
// 对应 tasks.md 任务 10.1，落地 design.md §「组件与接口 → 9. 流式 / 增量输入」。
// 既有 `Input` 持有完整 `Array[Char]` 不变；流式以**新增**的分段缓冲游标与
// 单步状态机承载（R14.5）。
//
// 设计要点（R10）：对同一完整输入，任意分段喂入方式得到的最终结果与一次性
// 喂入完整输入逐字段一致（R10.5 分段无关性）。本实现以「分段累积 + 在已到达
// 数据上重解析」达成：在数据耗尽于边界且尚未 closed 时返回 `NeedMore` 续延
// （R10.2），追加新段后从累积数据继续（R10.3）；标记结束（closed）后若仍不
// 满足则返回语法失败（R10.4）。

///|
/// 流式输入源：分段缓冲 + 是否已结束（end-of-input）。导出但抽象（`pub`）。
pub struct StreamSource {
  chunks : Array[Char]
  mut closed : Bool
}

///|
/// 单步结果（incremental step）。导出全部构造器（`pub(all)`），供调用方区分
/// 「已判定」与「需要更多输入」两态：
///   * `Done(result)` —— 已判定：成功或语法失败；
///   * `NeedMore(k)` —— 数据不足：喂入下一段后调用续延 `k` 继续（R10.2/10.3）。
pub(all) enum Step[T] {
  Done(ParseResult[T])
  NeedMore((String) -> Step[T])
}

///|
/// 内部辅助：由字符数组构造一个起始游标位置的 `Input`。
///
/// 物化为不可变 `String` 快照，隔离后续对 source.chunks 的追加（避免共享
/// 可变缓冲污染已建 Input）；快照建成后各 `Input` 间零拷贝共享。
fn pc_input_of_chars(chars : Array[Char]) -> Input {
  let sb = StringBuilder::new()
  for c in chars {
    sb.write_char(c)
  }
  Input::from_string(sb.to_string())
}

///|
/// 在当前累积数据上单步求值流式解析。
fn[T] pc_stream_eval(g : Grammar[T], src : StreamSource) -> Step[T] {
  let input = pc_input_of_chars(src.chunks)
  let res = g.run_naive(input)
  match res {
    Ok(_, _) => Step::Done(res)
    Fail(pos, ..) => {
      let avail = input.source.length()
      if src.closed {
        // 已结束且不满足 → 语法失败（R10.4）。
        Step::Done(res)
      } else if pos.offset >= avail {
        // 数据耗尽于边界 → 需要更多输入（R10.2）。
        Step::NeedMore(fn(chunk) {
          if chunk == "" {
            // 空段约定为「标记结束」（close），用于驱动收束。
            src.closed = true
          } else {
            for c in chunk {
              src.chunks.push(c)
            }
          }
          pc_stream_eval(g, src) // 从累积数据继续（R10.3）。
        })
      } else {
        // 在可用数据中部失败 → 追加尾部数据无法挽回，判定为语法失败。
        Step::Done(res)
      }
    }
  }
}

///|
/// `run_incremental`：以增量方式运行富解析器，从 `initial` 段起步。
///
/// 在已到达数据上推进解析（R10.1）；数据不足且未结束时返回 `NeedMore` 续延
/// （R10.2）。
pub fn[T] Grammar::run_incremental(
  self : Grammar[T],
  initial : String,
) -> Step[T] {
  let src : StreamSource = { chunks: initial.iter().to_array(), closed: false }
  pc_stream_eval(self, src)
}

///|
/// `drive`：把一串分段顺序喂入单步状态机，驱动至最终 `ParseResult`。
///
/// 依次以每个分段调用 `NeedMore` 续延；分段耗尽后，若 `closed` 为真则发送结束
/// 信号（空段）收束。供分段无关性属性测试（Property 26）以「随机切点」分段后
/// 与一次性喂入对照。
pub fn[T] drive(
  step : Step[T],
  chunks : Array[String],
  closed~ : Bool,
) -> ParseResult[T] {
  let mut cur = step
  for chunk in chunks {
    match cur {
      Done(r) => return r
      NeedMore(k) => cur = k(chunk)
    }
  }
  // 分段耗尽：发送结束信号（空段）以收束至 Done。
  let _ = closed
  let mut loops = 0
  while loops < 1000000 {
    match cur {
      Done(r) => return r
      NeedMore(k) => cur = k("")
    }
    loops = loops + 1
  }
  // 理论不可达：极端情况下以一次性求值兜底。
  match cur {
    Done(r) => r
    NeedMore(_) =>
      ParseResult::Fail(Pos::start(), expected=["流式解析未收敛"])
  }
}
