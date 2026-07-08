// audit.mbt —— mooncakes 索引审计引擎（G-A3 + H-1）。
//
// 输入约定（psv 快照，由 scripts/mooncakes_audit.ps1 生成）：
//   每行 `name|version|license|description`，字段内不含 `|`；
//   空行与字段数不足的行按畸形计数跳过（不静默丢弃信息）。
// 输出：能力域覆盖统计（关键词匹配）、缺口清单、markdown 摘要——
// 使 docs/ECOSYSTEM_COMPARISON.md 的「生态覆盖」表可由 CI 自动刷新。

///|
/// 索引条目：包名 / 版本 / 许可证 / 描述。
pub struct IndexEntry {
  name : String
  version : String
  license : String
  description : String
}

///|
/// 解析结果：合法条目与畸形行数（显式暴露、不静默）。
pub struct IndexSnapshot {
  entries : Array[IndexEntry]
  malformed : Int
}

///|
/// 按 `sep` 切分一行（不依赖字符串切分 API，三后端一致）。
fn split_on(line : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let mut cur = ""
  for c in line {
    if c == sep {
      parts.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  parts.push(cur)
  parts
}

///|
/// 解析 psv 快照行集合：每行 `name|version|license|description`；
/// 空行跳过（不计畸形），字段数 < 4 记畸形。
pub fn parse_index(lines : Array[String]) -> IndexSnapshot {
  let entries : Array[IndexEntry] = []
  let mut malformed = 0
  for line in lines {
    if line == "" {
      continue
    }
    let parts = split_on(line, '|')
    if parts.length() < 4 {
      malformed = malformed + 1
      continue
    }
    // description 可能含被切开的余段，重新拼接（description 是尾字段）。
    let mut desc = parts[3]
    for k in 4..<parts.length() {
      desc = desc + "|" + parts[k]
    }
    entries.push({
      name: parts[0],
      version: parts[1],
      license: parts[2],
      description: desc,
    })
  }
  { entries, malformed }
}

///|
/// 大小写不敏感的子串包含（ASCII 折叠）。
fn contains_ci(haystack : String, needle : String) -> Bool {
  fn lower(s : String) -> String {
    let mut out = ""
    for c in s {
      let code = c.to_int()
      if code >= 'A'.to_int() && code <= 'Z'.to_int() {
        out = out + Int::unsafe_to_char(code + 32).to_string()
      } else {
        out = out + c.to_string()
      }
    }
    out
  }

  lower(haystack).contains(lower(needle))
}

///|
/// 能力域：域名 + 关键词集合（名称或描述命中任一关键词即归入该域）。
pub struct CapabilityDomain {
  domain : String
  keywords : Array[String]
}

///|
/// 由域名与关键词构造能力域。
pub fn CapabilityDomain::new(
  domain : String,
  keywords : Array[String],
) -> CapabilityDomain {
  { domain, keywords }
}

///|
/// 单个能力域的生态覆盖：命中的包名清单（按索引顺序去重）。
pub fn domain_coverage(
  snapshot : IndexSnapshot,
  domain : CapabilityDomain,
) -> Array[String] {
  let out : Array[String] = []
  for e in snapshot.entries {
    let mut hit = false
    for kw in domain.keywords {
      if contains_ci(e.name, kw) || contains_ci(e.description, kw) {
        hit = true
        break
      }
    }
    if hit && !out.contains(e.name) {
      out.push(e.name)
    }
  }
  out
}

///|
/// 生态缺口报告：各能力域的命中包数；命中数 ≤ `gap_threshold`
/// 的域视为「生态缺口」（本仓库 INFRA 包填补的对象）。
pub fn gap_report(
  snapshot : IndexSnapshot,
  domains : Array[CapabilityDomain],
  gap_threshold : Int,
) -> Array[(String, Int, Bool)] {
  let out : Array[(String, Int, Bool)] = []
  for d in domains {
    let hits = domain_coverage(snapshot, d).length()
    out.push((d.domain, hits, hits <= gap_threshold))
  }
  out
}

///|
/// 许可证审计：统计各许可证出现次数（含空许可证，键为 "(none)"），
/// 返回 (许可证, 计数) 对，按首次出现顺序。
pub fn license_histogram(snapshot : IndexSnapshot) -> Array[(String, Int)] {
  let keys : Array[String] = []
  let counts : Array[Int] = []
  for e in snapshot.entries {
    let key = if e.license == "" { "(none)" } else { e.license }
    let mut found = false
    for k in 0..<keys.length() {
      if keys[k] == key {
        counts[k] = counts[k] + 1
        found = true
        break
      }
    }
    if !found {
      keys.push(key)
      counts.push(1)
    }
  }
  let out : Array[(String, Int)] = []
  for k in 0..<keys.length() {
    out.push((keys[k], counts[k]))
  }
  out
}

///|
/// 渲染 ECOSYSTEM_COMPARISON 可直接嵌入的 markdown 覆盖表：
/// 表头 + 每域一行 `| 域 | 命中数 | 缺口? |`，行序与 `domains` 一致。
pub fn render_coverage_markdown(
  snapshot : IndexSnapshot,
  domains : Array[CapabilityDomain],
  gap_threshold : Int,
) -> String {
  let mut md = "| 能力域 | 生态命中包数 | 缺口 |\n|---|---|---|\n"
  for row in gap_report(snapshot, domains, gap_threshold) {
    let (domain, hits, is_gap) = row
    md = md +
      "| " +
      domain +
      " | " +
      hits.to_string() +
      " | " +
      (if is_gap { "是" } else { "否" }) +
      " |\n"
  }
  md +
  "\n索引条目 " +
  snapshot.entries.length().to_string() +
  " 个，畸形行 " +
  snapshot.malformed.to_string() +
  " 条。\n"
}
