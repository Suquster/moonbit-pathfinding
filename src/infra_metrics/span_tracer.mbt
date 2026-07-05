// span_tracer.mbt —— E5 可观测性深化：tracing span 树 + 增量火焰聚合。
//
// 对标 OpenTelemetry SDK 的 span 处理管线与 pprof/火焰图聚合：span 以
// start/end 括号流进入，运行时维护活动 span 栈（父子由栈隐式给出，
// O(1)/事件），span 结束时即时结算 total（含子）与 self（不含子）耗时，
// 并按名字增量累入聚合表——任意时刻查询聚合统计 O(1)，无需回放事件日志。
//
// 朴素做法（工程中常见）：只追加事件日志，每次查询用栈全量回放重建树
// O(总事件数)；高频查询（面板刷新/告警评估）下退化为 O(n²)。本实现把
// 结算摊到 span 结束点，查询与 trace 规模无关。
//
// 单线程确定性建模：时间戳由调用方显式传入（与 DST/timer wheel 同一套
// 确定性时钟约定），同一事件流必然产出逐位一致的树与聚合。
//
// 对外 API：SpanTracer::new / start / end / active_depth / finished_count /
// stat / stat_names / children_of / span_name / span_total / span_self /
// root_spans。

///|
/// 已结算 span 记录。
struct SpanRec {
  name : String
  parent : Int // -1 = 根
  start_ts : Int64
  mut end_ts : Int64
  mut child_time : Int64
  children : Array[Int]
}

///|
/// 按名聚合：次数 / total（含子）/ self（不含子）。
struct SpanAgg {
  mut count : Int
  mut total : Int64
  mut self_time : Int64
}

///|
/// tracing span 树 + 增量聚合。
pub struct SpanTracer {
  spans : Array[SpanRec]
  stack : Array[Int]
  roots : Array[Int]
  agg : Map[String, SpanAgg]
  mut finished : Int
}

///|
/// 空 tracer。
pub fn SpanTracer::new() -> SpanTracer {
  { spans: [], stack: [], roots: [], agg: Map([]), finished: 0 }
}

///|
/// 开启一个 span（父 = 当前栈顶）。返回 span id。O(1)。
pub fn SpanTracer::start(self : SpanTracer, name : String, ts : Int64) -> Int {
  let id = self.spans.length()
  let parent = if self.stack.length() == 0 {
    -1
  } else {
    self.stack[self.stack.length() - 1]
  }
  self.spans.push({
    name,
    parent,
    start_ts: ts,
    end_ts: -1L,
    child_time: 0L,
    children: [],
  })
  if parent == -1 {
    self.roots.push(id)
  } else {
    self.spans[parent].children.push(id)
  }
  self.stack.push(id)
  id
}

///|
/// 结束当前活动 span（栈顶），即时结算并增量聚合。返回其 id；栈空返回 -1。
/// O(1)。
pub fn SpanTracer::end(self : SpanTracer, ts : Int64) -> Int {
  match self.stack.pop() {
    None => -1
    Some(id) => {
      let rec = self.spans[id]
      rec.end_ts = ts
      let total = ts - rec.start_ts
      let self_time = total - rec.child_time
      if rec.parent != -1 {
        let p = self.spans[rec.parent]
        p.child_time = p.child_time + total
      }
      match self.agg.get(rec.name) {
        Some(a) => {
          a.count = a.count + 1
          a.total = a.total + total
          a.self_time = a.self_time + self_time
        }
        None => self.agg.set(rec.name, { count: 1, total, self_time })
      }
      self.finished = self.finished + 1
      id
    }
  }
}

///|
/// 当前活动嵌套深度。
pub fn SpanTracer::active_depth(self : SpanTracer) -> Int {
  self.stack.length()
}

///|
/// 已结束 span 数。
pub fn SpanTracer::finished_count(self : SpanTracer) -> Int {
  self.finished
}

///|
/// 按名聚合统计 (count, total, self)。O(1)。
pub fn SpanTracer::stat(
  self : SpanTracer,
  name : String,
) -> (Int, Int64, Int64)? {
  match self.agg.get(name) {
    Some(a) => Some((a.count, a.total, a.self_time))
    None => None
  }
}

///|
/// 出现过的（已结束）span 名列表。
pub fn SpanTracer::stat_names(self : SpanTracer) -> Array[String] {
  let out : Array[String] = []
  for k, _ in self.agg {
    out.push(k)
  }
  out
}

///|
/// span 的子 span id 列表（按开启顺序）。
pub fn SpanTracer::children_of(self : SpanTracer, id : Int) -> Array[Int] {
  if id < 0 || id >= self.spans.length() {
    return []
  }
  self.spans[id].children.copy()
}

///|
/// span 名（越界返回 None）。
pub fn SpanTracer::span_name(self : SpanTracer, id : Int) -> String? {
  if id < 0 || id >= self.spans.length() {
    None
  } else {
    Some(self.spans[id].name)
  }
}

///|
/// span total 耗时（未结束返回 None）。
pub fn SpanTracer::span_total(self : SpanTracer, id : Int) -> Int64? {
  if id < 0 || id >= self.spans.length() || self.spans[id].end_ts < 0L {
    None
  } else {
    Some(self.spans[id].end_ts - self.spans[id].start_ts)
  }
}

///|
/// span self 耗时（total − 子合计；未结束返回 None）。
pub fn SpanTracer::span_self(self : SpanTracer, id : Int) -> Int64? {
  if id < 0 || id >= self.spans.length() || self.spans[id].end_ts < 0L {
    None
  } else {
    let rec = self.spans[id]
    Some(rec.end_ts - rec.start_ts - rec.child_time)
  }
}

///|
/// 根 span id 列表（按开启顺序）。
pub fn SpanTracer::root_spans(self : SpanTracer) -> Array[Int] {
  self.roots.copy()
}
