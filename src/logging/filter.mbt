// filter.mbt —— 过滤与路由（任务 6.1 / 6.2）。
//
// 设计依据：design.md §4.5「过滤与路由」（Requirement 4.*）。提供 EnvFilter
// 风格的分 target 级别过滤、字段谓词过滤与多 sink 路由：
//
//   * `EnvFilter` —— 各 target 的级别阈值表 + 全局兜底阈值；
//   * `parse_env_filter(spec)` —— 解析 `target=level,…,level` 指令集合，先完整
//     校验后构造，任一项非法返回 `Err(FilterError{pos, message})` 且不登记任何
//     阈值（Requirement 4.3 / 4.4）；
//   * `EnvFilter::threshold_for` / `allows` —— 取 target 有效阈值 / 事件保留判定
//     （Requirement 4.1 / 4.6）；
//   * `field_filter(pred, e)` —— 字段谓词过滤（Requirement 4.2）；
//   * `route(sinks, e)` —— 路由匹配的全部 sink 名称（Requirement 4.5）。
//
// EnvFilter 指令文法对标 Rust `tracing-subscriber` 的 `EnvFilter`（见 README
// paper-to-code 追溯，Requirement 10.5）。

///|
/// EnvFilter：各 target 的级别阈值表 + 全局兜底阈值（Requirement 4.3）。
///
/// `directives` 命中某 target 时用其阈值，否则用 `fallback` 兜底。`fallback`
/// 缺省（指令集中无裸 level）取 `Trace`（最宽松，与日志运行时默认阈值一致）。
pub(all) struct EnvFilter {
  directives : Map[String, Level]
  fallback : Level
} derive(Eq, Show)

///|
/// EnvFilter 指令解析错误（携带定位信息，Requirement 4.4）。
///
/// `pos` 为出错处的字符偏移（自 0 起），`message` 为人类可读原因。
pub(all) struct FilterError {
  pos : Int
  message : String
} derive(Eq, Show)

///|
/// 解析 EnvFilter 指令集合（Requirement 4.3 / 4.4）。
///
/// 文法：逗号分隔的项，每项为 `target=level` 或裸 `level`（裸 level 作为全局
/// 兜底，多次出现以最后一次为准）。`level` 经大小写归一后由 `Level::from_label`
/// 识别。空 `spec` 合法（无指令 + 默认兜底 `Trace`）。
///
/// 「先完整校验后构造」：任一项非法（缺 `=`、target 为空、级别标签不可识别）
/// 返回 `Err(FilterError{pos, message})`，且不登记任何阈值（Requirement 4.4）。
pub fn parse_env_filter(spec : String) -> Result[EnvFilter, FilterError] {
  let directives : Map[String, Level] = Map::new()
  let mut fallback : Level = Trace
  let chars : Array[Char] = []
  for c in spec {
    chars.push(c)
  }
  let n = chars.length()
  // 空 spec：无指令，默认兜底。
  if n == 0 {
    return Ok({ directives, fallback })
  }
  // 切分为逗号分隔的段，记录每段起始偏移。
  let segments : Array[(Int, String)] = []
  let mut seg_start = 0
  let cur = @infra_text.TextBuilder::new()
  for i = 0; i < n; i = i + 1 {
    let c = chars[i]
    if c == ',' {
      segments.push((seg_start, cur.build()))
      cur.reset()
      seg_start = i + 1
    } else {
      cur.push_char(c)
    }
  }
  segments.push((seg_start, cur.build()))
  // 逐段校验并暂存（先完整校验，全部合法后再登记）。
  let pending : Array[(String, Level)] = []
  let mut pending_fallback : Level? = None
  for seg in segments {
    let (off, text) = seg
    if text == "" {
      return Err({ pos: off, message: "empty directive segment" })
    }
    // 定位 '=' 位置。
    let mut eq = -1
    let tchars : Array[Char] = []
    for c in text {
      tchars.push(c)
    }
    for i = 0; i < tchars.length(); i = i + 1 {
      if tchars[i] == '=' {
        eq = i
        break
      }
    }
    if eq < 0 {
      // 裸 level → 兜底。
      match parse_level_ci(text) {
        Some(lv) => pending_fallback = Some(lv)
        None =>
          return Err({ pos: off, message: "unrecognized level label: " + text })
      }
    } else {
      // target=level。
      let target = substr_chars(tchars, 0, eq)
      let level_str = substr_chars(tchars, eq + 1, tchars.length())
      if target == "" {
        return Err({ pos: off, message: "empty target before '='" })
      }
      match parse_level_ci(level_str) {
        Some(lv) => pending.push((target, lv))
        None =>
          return Err({
            pos: off + eq + 1,
            message: "unrecognized level label: " + level_str,
          })
      }
    }
  }
  // 全部合法：登记。
  for p in pending {
    directives[p.0] = p.1
  }
  match pending_fallback {
    Some(lv) => fallback = lv
    None => ()
  }
  Ok({ directives, fallback })
}

///|
/// 取某 target 的有效阈值：命中指令用其阈值，否则用全局兜底（Requirement 4.1）。
pub fn EnvFilter::threshold_for(self : EnvFilter, target : String) -> Level {
  match self.directives.get(target) {
    Some(lv) => lv
    None => self.fallback
  }
}

///|
/// 事件是否被保留（Requirement 4.1 / 4.6）。
///
/// 保留 ⟺ `e.level.rank() >= threshold_for(target).rank()`，其中 target 取自
/// 事件的 `"target"` 字段（缺失或非字符串则用空串走兜底）。
pub fn EnvFilter::allows(self : EnvFilter, e : Event) -> Bool {
  let target = match e.fields.get("target") {
    Some(VStr(t)) => t
    _ => ""
  }
  e.level.rank() >= self.threshold_for(target).rank()
}

///|
/// 字段谓词过滤：事件被保留 ⟺ 其字段满足谓词（Requirement 4.2 / 4.6）。
pub fn field_filter(pred : (Map[String, Value]) -> Bool, e : Event) -> Bool {
  pred(e.fields)
}

///|
/// 路由：返回路由条件匹配该事件的全部 sink 名称（Requirement 4.5）。
///
/// 无匹配返回空数组（与 `dispatch` 协同：无匹配则不交付）。
pub fn route(sinks : Array[Sink], e : Event) -> Array[String] {
  let out : Array[String] = []
  for s in sinks {
    if (s.route)(e) {
      out.push(s.name)
    }
  }
  out
}

///|
/// 大小写不敏感的级别标签解析：归一为大写后经 `Level::from_label` 识别。
fn parse_level_ci(s : String) -> Level? {
  let up = @infra_text.TextBuilder::new()
  for c in s {
    let code = c.to_int()
    if code >= 'a'.to_int() && code <= 'z'.to_int() {
      up.push_str((code - 32).unsafe_to_char().to_string())
    } else {
      up.push_char(c)
    }
  }
  Level::from_label(up.build())
}

///|
/// 从字符数组取 `[start, end)` 子串。
fn substr_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let out = @infra_text.TextBuilder::new()
  for i = start; i < end; i = i + 1 {
    out.push_char(chars[i])
  }
  out.build()
}
