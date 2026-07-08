// evidence.mbt —— 可校验证据索引引擎（H-4 + G-C2）。
//
// 证据三元组约定（psv 行）：`claim|test_ref|commit`
//   * claim    —— 能力声明（如「zstd 帧 RFC 8878 往返」）；
//   * test_ref —— 测试锚点 `包路径::测试名`（可执行见证）；
//   * commit   —— 引入该证据的 commit 短哈希（git 可回放）。
// 引擎职责：解析、断链校验（三字段皆非空、test_ref 含 `::` 分隔、
// commit 为 7..40 位十六进制）、SHA-256 索引摘要（防篡改锚点，
// 复用 @infra_hash 自家实现——自举吃自家狗粮）、markdown 渲染。

///|
/// 证据三元组。
pub struct EvidenceEntry {
  claim : String
  test_ref : String
  commit : String
}

///|
/// 解析结果：条目 + 逐行断链诊断（行号从 1 起）。
pub struct EvidenceIndex {
  entries : Array[EvidenceEntry]
  diagnostics : Array[String]
}

///|
fn split_psv(line : String) -> Array[String] {
  let parts : Array[String] = []
  let mut cur = ""
  for c in line {
    if c == '|' {
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
fn is_hex_commit(s : String) -> Bool {
  let mut len = 0
  for c in s {
    let code = c.to_int()
    let ok = (code >= '0'.to_int() && code <= '9'.to_int()) ||
      (code >= 'a'.to_int() && code <= 'f'.to_int())
    if !ok {
      return false
    }
    len = len + 1
  }
  len >= 7 && len <= 40
}

///|
/// 解析并校验证据索引。断链行不入 entries、只入 diagnostics（显式暴露）。
pub fn parse_evidence(lines : Array[String]) -> EvidenceIndex {
  let entries : Array[EvidenceEntry] = []
  let diagnostics : Array[String] = []
  let mut lineno = 0
  for line in lines {
    lineno = lineno + 1
    if line == "" {
      continue
    }
    let parts = split_psv(line)
    if parts.length() != 3 {
      diagnostics.push("line " + lineno.to_string() + ": expected 3 fields")
      continue
    }
    let claim = parts[0]
    let test_ref = parts[1]
    let commit = parts[2]
    if claim == "" {
      diagnostics.push("line " + lineno.to_string() + ": empty claim")
      continue
    }
    if !test_ref.contains("::") {
      diagnostics.push(
        "line " + lineno.to_string() + ": test_ref missing `::` anchor",
      )
      continue
    }
    if !is_hex_commit(commit) {
      diagnostics.push("line " + lineno.to_string() + ": bad commit hash")
      continue
    }
    entries.push({ claim, test_ref, commit })
  }
  { entries, diagnostics }
}

///|
/// 索引是否完整无断链。
pub fn EvidenceIndex::is_sound(self : EvidenceIndex) -> Bool {
  self.diagnostics.length() == 0
}

///|
/// 索引 SHA-256 摘要（十六进制）：对全部条目的规范化拼接
/// `claim|test_ref|commit\n` 求哈希；任何篡改（增删改、重排）都改变摘要。
pub fn EvidenceIndex::digest(self : EvidenceIndex) -> String {
  let mut canon = ""
  for e in self.entries {
    canon = canon + e.claim + "|" + e.test_ref + "|" + e.commit + "\n"
  }
  @infra_hash.sha256_hex(canon)
}

///|
/// 渲染 markdown 证据表（docs/verification 可直接嵌入），
/// 表尾附条目数与防篡改摘要。
pub fn EvidenceIndex::render_markdown(self : EvidenceIndex) -> String {
  let mut md = "| 声明 | 测试见证 | commit |\n|---|---|---|\n"
  for e in self.entries {
    md = md + "| " + e.claim + " | `" + e.test_ref + "` | " + e.commit + " |\n"
  }
  md +
  "\n条目 " +
  self.entries.length().to_string() +
  " 项；索引摘要 `sha256:" +
  self.digest() +
  "`。\n"
}
