// cache.mbt —— 内容寻址增量缓存、动作缓存与缓存持久化（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.2 / §4.3）：内容寻址缓存模型对标 Bazel / Nix /
// Ninja——以**内容哈希**（而非时间戳）为主键索引构建结果。缓存键采用**长度
// 前缀单射编码**（length-prefixed / netstring 式），使「相同输入产相同键、
// 任一分量不同即产不同键」成为**构造性事实**而非抗碰撞散列的概率保证
// （R3.4 / R3.6，正确性属性 3）。
//
// 三后端一致（R14.1）：`content_hash` 以 64 位 FNV-1a（`UInt64` 取模环绕）实现，
// `cache_key` / 序列化全程纯整型 / 字符串运算、`Map` 序列化键显式升序——
// `wasm-gc` / `js` / `native` 逐位一致，不依赖浮点或哈希表遍历顺序。
//
// 既有 `BuildCache` 复用而非改写：持久化（`serialize_cache` /
// `deserialize_cache`）以旁路函数提供，不改 `BuildCache` 结构；反序列化错误
// 复用既有 `ParseError`（行式格式，行号即出错行，R4.3）。

// ───────────────────────────── 内容哈希与指纹 ─────────────────────────────

///|
/// 内容哈希：64 位 FNV-1a 摘要的十进制字符串。
///
/// 纯 `UInt64` 环绕运算 + `Char` 码点混合，三后端逐位一致。内容相同即哈希
/// 相同（确定性）。
pub fn content_hash(content : String) -> String {
  let mut h : UInt64 = 14695981039346656037UL
  for c in content.iter().to_array() {
    h = (h ^ c.to_int().to_uint64()) * 1099511628211UL
  }
  h.to_string()
}

///|
/// 长度前缀单射编码 `len|s`：字段边界由「十进制长度 + '|' + 恰 len 个字符」
/// 唯一确定，故任意字段序列的拼接可无歧义解析，编码为单射。
fn lp(s : String) -> String {
  s.length().to_string() + "|" + s
}

///|
/// 动作指纹：对 recipe 全部命令行做长度前缀编码后取内容哈希（R1.2 动作维度）。
pub fn action_fingerprint(recipe : Recipe) -> String {
  let mut enc = ""
  for line in recipe.lines {
    enc = enc + lp(line)
  }
  content_hash(enc)
}

///|
/// 缓存键：目标名、其全部输入内容哈希（调用方按依赖名升序提供）与动作指纹的
/// **长度前缀单射编码**（R3.1）。相同输入产相同键、任一分量不同即产不同键
/// （R3.4 / R3.6，构造性单射）。
pub fn cache_key(
  target : String,
  input_hashes : Array[String],
  action_fp : String,
) -> String {
  let mut out = lp(target) + lp(input_hashes.length().to_string())
  for h in input_hashes {
    out = out + lp(h)
  }
  out + lp(action_fp)
}

// ───────────────────────────── 动作缓存 ─────────────────────────────

///|
/// 动作缓存：缓存键 → 输出内容哈希；命中即跳过该目标重建（R3.2）。
pub(all) struct ActionCache {
  entries : Map[String, String]
}

///|
/// 构造空动作缓存。
pub fn ActionCache::new() -> ActionCache {
  { entries: Map([]) }
}

///|
/// 登记一条「缓存键 → 输出哈希」记录。
pub fn ActionCache::record(
  self : ActionCache,
  key : String,
  output_hash : String,
) -> Unit {
  self.entries[key] = output_hash
}

///|
/// 缓存键是否命中。
pub fn ActionCache::hit(self : ActionCache, key : String) -> Bool {
  self.entries.contains(key)
}

///|
/// 取缓存键对应的输出哈希（未命中返回 `None`）。
pub fn ActionCache::get(self : ActionCache, key : String) -> String? {
  self.entries.get(key)
}

///|
/// 基于缓存键判定目标是否需重建：命中 → `false`（排除重建集，R3.2）；
/// 未命中 → `true`（纳入重建集，R3.3）。内容哈希变而 mtime 未变仍因键变化
/// 判为需重建（R3.5，内容寻址优于纯时间戳）。
pub fn needs_rebuild_by_key(
  cache : ActionCache,
  target : String,
  input_hashes : Array[String],
  action_fp : String,
) -> Bool {
  !cache.hit(cache_key(target, input_hashes, action_fp))
}

// ───────────────────────────── 缓存持久化 ─────────────────────────────

///|
/// Map[String, Int64] 的升序键列表。
fn sorted_keys_i64(m : Map[String, Int64]) -> Array[String] {
  let ks = m.keys().to_array()
  ks.sort()
  ks
}

///|
/// Map[String, String] 的升序键列表。
fn sorted_keys_str(m : Map[String, String]) -> Array[String] {
  let ks = m.keys().to_array()
  ks.sort()
  ks
}

///|
/// 将 `BuildCache` 的四张指纹映射序列化为可持久化文本（行式 section，键升序，
/// 确定性输出，R4.1）。
///
/// 格式（每行 `<marker> <name> <value>`，`marker ∈ {M,H,m,h}`）：
/// ```text
/// # recorded_mtimes
/// M name mtime
/// # recorded_hashes
/// H name hash
/// # current_mtimes
/// m name mtime
/// # current_hashes
/// h name hash
/// ```
pub fn serialize_cache(cache : BuildCache) -> String {
  let mut out = "# recorded_mtimes\n"
  for name in sorted_keys_i64(cache.recorded_mtimes) {
    out = out +
      "M " +
      name +
      " " +
      cache.recorded_mtimes.get(name).unwrap_or(0L).to_string() +
      "\n"
  }
  out = out + "# recorded_hashes\n"
  for name in sorted_keys_str(cache.recorded_hashes) {
    out = out + "H " + name + " " + cache.recorded_hashes.get(name).unwrap_or("") + "\n"
  }
  out = out + "# current_mtimes\n"
  for name in sorted_keys_i64(cache.current_mtimes) {
    out = out +
      "m " +
      name +
      " " +
      cache.current_mtimes.get(name).unwrap_or(0L).to_string() +
      "\n"
  }
  out = out + "# current_hashes\n"
  for name in sorted_keys_str(cache.current_hashes) {
    out = out + "h " + name + " " + cache.current_hashes.get(name).unwrap_or("") + "\n"
  }
  out
}

///|
/// 解析十进制 `Int64`（可选负号）；非法返回 `None`。
fn parse_int64_opt(s : String) -> Int64? {
  let cs = s.iter().to_array()
  if cs.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if cs[0] == '-' {
    neg = true
    i = 1
    if cs.length() == 1 {
      return None
    }
  }
  let mut acc : Int64 = 0L
  while i < cs.length() {
    let c = cs[i]
    if c < '0' || c > '9' {
      return None
    }
    acc = acc * 10L + (c.to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  Some(if neg { -acc } else { acc })
}

///|
/// 从文本反序列化重建 `BuildCache`（R4.2）；格式非法 / 字段缺失 / 数值非法
/// 返回带行号 `ParseError`，且不产出部分构造缓存（R4.3）。
pub fn deserialize_cache(text : String) -> Result[BuildCache, ParseError] {
  let cache = BuildCache::new()
  let lines = split_lines(text.iter().to_array())
  let mut line_no = 0
  for line in lines {
    line_no = line_no + 1
    let trimmed = trim_chars(line)
    if trimmed.length() == 0 || trimmed[0] == '#' {
      continue
    }
    let sp1 = first_index_char(line, ' ')
    if sp1 < 0 {
      return Err(ParseError::new("缓存行缺少字段分隔空格", line_no))
    }
    let marker = chars_to_string(slice_chars(line, 0, sp1))
    let mut sp2 = -1
    for k in (sp1 + 1)..<line.length() {
      if line[k] == ' ' {
        sp2 = k
        break
      }
    }
    let (name, value) = if sp2 < 0 {
      (chars_to_string(slice_chars(line, sp1 + 1, line.length())), "")
    } else {
      (
        chars_to_string(slice_chars(line, sp1 + 1, sp2)),
        chars_to_string(slice_chars(line, sp2 + 1, line.length())),
      )
    }
    if name == "" {
      return Err(ParseError::new("缓存行目标名为空", line_no))
    }
    match marker {
      "M" =>
        match parse_int64_opt(value) {
          Some(v) => cache.recorded_mtimes[name] = v
          None => return Err(ParseError::new("非法 mtime 数值", line_no))
        }
      "m" =>
        match parse_int64_opt(value) {
          Some(v) => cache.current_mtimes[name] = v
          None => return Err(ParseError::new("非法 mtime 数值", line_no))
        }
      "H" => cache.recorded_hashes[name] = value
      "h" => cache.current_hashes[name] = value
      _ => return Err(ParseError::new("未知缓存段标记 '" + marker + "'", line_no))
    }
  }
  Ok(cache)
}

///|
/// 按四张指纹映射逐字段比较两份缓存（属性测试与去重判等用，R4.4）。
pub fn cache_eq(a : BuildCache, b : BuildCache) -> Bool {
  a.recorded_mtimes == b.recorded_mtimes &&
  a.recorded_hashes == b.recorded_hashes &&
  a.current_mtimes == b.current_mtimes &&
  a.current_hashes == b.current_hashes
}
