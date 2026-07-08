// dep_audit.mbt —— 依赖健康审计（H-2，L6 生态平台层）。
//
// 对 moon.mod 声明的依赖（名称 + 期望版本）逐一对照索引快照做健康检查：
//   * 存在性 —— 依赖是否仍在 mooncakes 索引中（下架 / 改名风险）；
//   * 版本时效 —— 声明版本是否落后于索引最新版（按 SemVer 逐段比较）；
//   * 许可证合规 —— 依赖许可证是否在许可清单内（空许可证视为不合规）。
// 输出结构化报告 + 一票否决的整体健康判定，供 CI 门禁消费。

///|
/// 依赖声明：名称 + moon.mod 中声明的版本。
pub struct DepRequirement {
  name : String
  version : String
}

///|
/// 由名称与版本构造依赖声明。
pub fn DepRequirement::new(name : String, version : String) -> DepRequirement {
  { name, version }
}

///|
/// 单个依赖的健康发现。
pub(all) enum DepFinding {
  DepHealthy
  DepMissingFromIndex
  DepVersionBehind(String)
  DepLicenseViolation(String)
} derive(Eq)

///|
/// 解析 `MAJOR.MINOR.PATCH`（宽松：段数 1..3，缺段补 0）；非法返回 None。
fn parse_version_loose(s : String) -> (Int, Int, Int)? {
  let parts : Array[Int] = []
  let mut cur = 0
  let mut has_digit = false
  for c in s {
    let code = c.to_int()
    if code >= '0'.to_int() && code <= '9'.to_int() {
      cur = cur * 10 + (code - '0'.to_int())
      has_digit = true
    } else if c == '.' {
      if !has_digit {
        return None
      }
      parts.push(cur)
      cur = 0
      has_digit = false
    } else {
      return None
    }
  }
  if !has_digit {
    return None
  }
  parts.push(cur)
  if parts.length() > 3 {
    return None
  }
  while parts.length() < 3 {
    parts.push(0)
  }
  Some((parts[0], parts[1], parts[2]))
}

///|
/// 版本序比较：a < b。
fn version_lt(a : (Int, Int, Int), b : (Int, Int, Int)) -> Bool {
  let (a0, a1, a2) = a
  let (b0, b1, b2) = b
  if a0 != b0 {
    return a0 < b0
  }
  if a1 != b1 {
    return a1 < b1
  }
  a2 < b2
}

///|
/// 审计单个依赖：按「存在性 → 许可证 → 版本时效」优先级返回首要发现。
pub fn audit_dep(
  snapshot : IndexSnapshot,
  dep : DepRequirement,
  allowed_licenses : Array[String],
) -> DepFinding {
  for e in snapshot.entries {
    if e.name == dep.name {
      if !allowed_licenses.contains(e.license) {
        return DepLicenseViolation(
          if e.license == "" {
            "(none)"
          } else {
            e.license
          },
        )
      }
      match (parse_version_loose(dep.version), parse_version_loose(e.version)) {
        (Some(want), Some(latest)) =>
          if version_lt(want, latest) {
            return DepVersionBehind(e.version)
          }
        _ => ()
      }
      return DepHealthy
    }
  }
  DepMissingFromIndex
}

///|
/// 依赖健康报告：逐依赖发现 + 整体健康（全部 DepHealthy 才为 true）。
pub fn audit_deps(
  snapshot : IndexSnapshot,
  deps : Array[DepRequirement],
  allowed_licenses : Array[String],
) -> (Array[(String, DepFinding)], Bool) {
  let findings : Array[(String, DepFinding)] = []
  let mut healthy = true
  for dep in deps {
    let f = audit_dep(snapshot, dep, allowed_licenses)
    if !(f == DepHealthy) {
      healthy = false
    }
    findings.push((dep.name, f))
  }
  (findings, healthy)
}

///|
/// 渲染依赖审计 markdown 报告（CI 工件 / PR 评论可直接嵌入）。
pub fn render_dep_audit_markdown(
  snapshot : IndexSnapshot,
  deps : Array[DepRequirement],
  allowed_licenses : Array[String],
) -> String {
  let (findings, healthy) = audit_deps(snapshot, deps, allowed_licenses)
  let mut md = "| 依赖 | 发现 |\n|---|---|\n"
  for row in findings {
    let (name, f) = row
    let label = match f {
      DepHealthy => "健康"
      DepMissingFromIndex => "索引缺失（下架/改名风险）"
      DepVersionBehind(latest) => "版本落后（最新 " + latest + "）"
      DepLicenseViolation(lic) => "许可证不合规（" + lic + "）"
    }
    md = md + "| " + name + " | " + label + " |\n"
  }
  md +
  "\n整体健康：" +
  (if healthy { "通过" } else { "不通过" }) +
  "\n"
}
