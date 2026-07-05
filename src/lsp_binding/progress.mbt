// progress.mbt —— T5.2 协议完整性：`$/progress` 工作进度（Work Done Progress）
// 数据模型、编解码与生命周期校验（旁路新增，不改既有消息类型）。
//
// paper-to-code 追溯（LSP 3.17 规范 §Progress Support / §Work Done Progress）：
//   * 进度经 `$/progress` 通知报告，params 形如
//     `{"token": <ProgressToken>, "value": <WorkDoneProgress...>}`；
//   * `ProgressToken = integer | string`；
//   * value 三态：`kind:"begin"`（title 必填，可带 cancellable / message /
//     percentage）→ `kind:"report"`（可带 cancellable / message / percentage）
//     → `kind:"end"`（可带 message）；
//   * 规范要求 percentage 「应当单调上升」（rule: value should steadily rise）。
//   * 补齐 LSP 保留区错误码常量（既有五个 JSON-RPC 标准码 + RequestCancelled
//     保持冻结）：ServerNotInitialized(-32002)、UnknownErrorCode(-32001)、
//     ContentModified(-32801)、ServerCancelled(-32802)、RequestFailed(-32803)。
//
// 生命周期以不可变 `ProgressTracker` 表达（与 `CancelRegistry` 同款纯数据模型）：
// `observe` 返回 `Ok(新跟踪器)` 或 `Err(违规描述)`，锁定 begin → report* → end
// 的合法序与 percentage 单调不减。

// ───────────────────────────── LSP 保留区错误码 ────────────────────────

///|
/// LSP 规范 `ServerNotInitialized = -32002`：`initialize` 前收到请求。
pub let server_not_initialized_code : Int = -32002

///|
/// LSP 规范 `UnknownErrorCode = -32001`。
pub let unknown_error_code : Int = -32001

///|
/// LSP 规范 `ContentModified = -32801`：结果因文档内容变更而失效。
pub let content_modified_code : Int = -32801

///|
/// LSP 规范 `ServerCancelled = -32802`：服务端主动取消。
pub let server_cancelled_code : Int = -32802

///|
/// LSP 规范 `RequestFailed = -32803`：请求语法上有效但执行失败。
pub let request_failed_code : Int = -32803

// ───────────────────────────── 进度令牌与三态 ──────────────────────────

///|
/// 进度令牌（LSP `ProgressToken = integer | string`）。
pub(all) enum ProgressToken {
  TokNum(Int)
  TokStr(String)
} derive(Eq, Debug)

///|
/// 工作进度三态（LSP `WorkDoneProgressBegin / Report / End`）。
/// 可选字段以 `Option` 表达；percentage 取值 [0, 100]。
pub(all) enum WorkDoneProgress {
  Begin(
    title~ : String,
    cancellable~ : Bool?,
    message~ : String?,
    percentage~ : Int?
  )
  Report(cancellable~ : Bool?, message~ : String?, percentage~ : Int?)
  End(message~ : String?)
} derive(Eq, Debug)

// ───────────────────────────── 编码（→ $/progress） ────────────────────

///|
/// 把进度令牌编码为 JSON。
fn token_to_json(tok : ProgressToken) -> Json {
  match tok {
    TokNum(n) => JNum(n.to_string())
    TokStr(s) => JStr(s)
  }
}

///|
/// 把三态 value 编码为带 `kind` 判别字段的 JSON 对象（与规范字段名一致，
/// 缺省可选字段不输出）。
fn progress_value_to_json(v : WorkDoneProgress) -> Json {
  let fields : Array[(String, Json)] = []
  match v {
    Begin(title~, cancellable~, message~, percentage~) => {
      fields.push(("kind", JStr("begin")))
      fields.push(("title", JStr(title)))
      match cancellable {
        Some(b) => fields.push(("cancellable", JBool(b)))
        None => ()
      }
      match message {
        Some(m) => fields.push(("message", JStr(m)))
        None => ()
      }
      match percentage {
        Some(p) => fields.push(("percentage", JNum(p.to_string())))
        None => ()
      }
    }
    Report(cancellable~, message~, percentage~) => {
      fields.push(("kind", JStr("report")))
      match cancellable {
        Some(b) => fields.push(("cancellable", JBool(b)))
        None => ()
      }
      match message {
        Some(m) => fields.push(("message", JStr(m)))
        None => ()
      }
      match percentage {
        Some(p) => fields.push(("percentage", JNum(p.to_string())))
        None => ()
      }
    }
    End(message~) => {
      fields.push(("kind", JStr("end")))
      match message {
        Some(m) => fields.push(("message", JStr(m)))
        None => ()
      }
    }
  }
  JObj(fields)
}

///|
/// 合成一条 `$/progress` 通知（LSP 规范 params：`{token, value}`）。
pub fn progress_notification(
  token : ProgressToken,
  value : WorkDoneProgress,
) -> JsonRpcMessage {
  Notification(
    method_name="$/progress",
    params=JObj([
      ("token", token_to_json(token)),
      ("value", progress_value_to_json(value)),
    ]),
  )
}

// ───────────────────────────── 解码（$/progress →） ────────────────────

///|
/// 从 JSON 解析进度令牌；仅接受整数或字符串（与 `ProgressToken` 域一致）。
fn parse_token(j : Json) -> ProgressToken? {
  match j {
    JStr(s) => Some(TokStr(s))
    JNum(s) =>
      match parse_int_literal(s) {
        Some(n) => Some(TokNum(n))
        None => None
      }
    _ => None
  }
}

///|
/// 从 value 对象中解析可选字段组（cancellable / message / percentage）。
fn parse_optionals(fields : Array[(String, Json)]) -> (Bool?, String?, Int?) {
  let cancellable = match json_obj_get(fields, "cancellable") {
    Some(JBool(b)) => Some(b)
    _ => None
  }
  let message = match json_obj_get(fields, "message") {
    Some(JStr(m)) => Some(m)
    _ => None
  }
  let percentage = match json_obj_get(fields, "percentage") {
    Some(JNum(s)) => parse_int_literal(s)
    _ => None
  }
  (cancellable, message, percentage)
}

///|
/// 从 `$/progress` 通知的 `params` 中解析 `(token, value)`。
/// params 非对象、缺字段、`kind` 非法或 `begin` 缺 `title` 时返回 `None`。
pub fn progress_of(params : Json) -> (ProgressToken, WorkDoneProgress)? {
  match params {
    JObj(fields) => {
      let token = match json_obj_get(fields, "token") {
        Some(j) =>
          match parse_token(j) {
            Some(t) => t
            None => return None
          }
        None => return None
      }
      match json_obj_get(fields, "value") {
        Some(JObj(vf)) => {
          let (cancellable, message, percentage) = parse_optionals(vf)
          match json_obj_get(vf, "kind") {
            Some(JStr("begin")) =>
              match json_obj_get(vf, "title") {
                Some(JStr(title)) =>
                  Some(
                    (token, Begin(title~, cancellable~, message~, percentage~)),
                  )
                _ => None
              }
            Some(JStr("report")) =>
              Some((token, Report(cancellable~, message~, percentage~)))
            Some(JStr("end")) => Some((token, End(message~)))
            _ => None
          }
        }
        _ => None
      }
    }
    _ => None
  }
}

// ───────────────────────────── 生命周期校验 ────────────────────────────

///|
/// 单个令牌的进度生命周期状态。
priv enum ProgressPhase {
  PActive(Int) // 已 begin，记录最近一次报告的 percentage（未报告过为 -1）
  PDone // 已 end
}

///|
/// 进度生命周期跟踪器（不可变值）：锁定 LSP 规范约束——
///   * 同一令牌必须先 `begin`，且不得重复 `begin`；
///   * `report` / `end` 仅在活跃（已 begin 未 end）令牌上合法；
///   * percentage 单调不减且落在 [0, 100]（规范 rule: value should steadily rise）。
pub struct ProgressTracker {
  priv phases : Map[String, ProgressPhase]
}

///|
/// 令牌的规范字符串键（数值与字符串令牌互不碰撞，与 `id_key` 同款约定）。
fn token_key(tok : ProgressToken) -> String {
  match tok {
    TokNum(n) => "n:" + n.to_string()
    TokStr(s) => "s:" + s
  }
}

///|
/// 构造空跟踪器（无任何进行中的进度）。
pub fn ProgressTracker::new() -> ProgressTracker {
  { phases: Map([]) }
}

///|
/// 复制底层表（写时复制，保持不可变语义）。
fn ProgressTracker::copy_phases(
  self : ProgressTracker,
) -> Map[String, ProgressPhase] {
  let next : Map[String, ProgressPhase] = Map([])
  for k, v in self.phases {
    next[k] = v
  }
  next
}

///|
/// 观察一条进度事件：合法则返回携带新状态的 `Ok(新跟踪器)`（原实例不变），
/// 违规返回 `Err(违规描述)`。校验项见 `ProgressTracker` 文档。
pub fn ProgressTracker::observe(
  self : ProgressTracker,
  token : ProgressToken,
  value : WorkDoneProgress,
) -> Result[ProgressTracker, String] {
  let key = token_key(token)
  let cur = self.phases.get(key)
  fn check_pct(p : Int?, last : Int) -> Result[Int, String] {
    match p {
      None => Ok(last)
      Some(v) =>
        if v < 0 || v > 100 {
          Err("percentage \{v} out of range [0, 100]")
        } else if v < last {
          Err(
            "percentage must be monotonically non-decreasing (\{last} -> \{v})",
          )
        } else {
          Ok(v)
        }
    }
  }

  match value {
    Begin(percentage~, ..) =>
      match cur {
        Some(_) => Err("duplicate begin for token \{key}")
        None =>
          match check_pct(percentage, -1) {
            Ok(p) => {
              let next = self.copy_phases()
              next[key] = PActive(p)
              Ok({ phases: next })
            }
            Err(e) => Err(e)
          }
      }
    Report(percentage~, ..) =>
      match cur {
        Some(PActive(last)) =>
          match check_pct(percentage, last) {
            Ok(p) => {
              let next = self.copy_phases()
              next[key] = PActive(p)
              Ok({ phases: next })
            }
            Err(e) => Err(e)
          }
        Some(PDone) => Err("report after end for token \{key}")
        None => Err("report before begin for token \{key}")
      }
    End(..) =>
      match cur {
        Some(PActive(_)) => {
          let next = self.copy_phases()
          next[key] = PDone
          Ok({ phases: next })
        }
        Some(PDone) => Err("duplicate end for token \{key}")
        None => Err("end before begin for token \{key}")
      }
  }
}
