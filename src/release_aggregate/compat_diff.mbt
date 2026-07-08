// compat_diff.mbt —— 生态级 semver 兼容性 diff 流水线（G-A2）。
//
// paper-to-code：cargo-semver-checks / Go apidiff 的语义内核，作用对象为
// MoonBit 包的 `.mbti` 式 API 表面（声明名 → 签名文本）：
//   * 删除公开声明 / 修改既有签名 —— 破坏性变更（要求 MAJOR 升级）；
//   * 新增公开声明 —— 向后兼容的功能新增（要求 ≥ MINOR 升级）；
//   * 表面无变化 —— 任何升级（含 PATCH）均可。
// 版本判定遵循 semver.org §7/8：给定新旧 API 表面与新旧版本号，
// 校验「实际升级档位 ≥ 变更要求档位」，违规输出可读诊断。
//
// 复用：版本解析复用 @release_meta.parse_semver（单一事实源）；
// schema 级字段演进由 serialization.check_schema_evolution 承担，
// 本层聚合的是「包 API 表面」粒度。

///|
/// API 表面：包的公开声明集合（声明名 → 规范化签名文本）。
pub struct ApiSurface {
  decls : Map[String, String]
}

///|
/// 由 (名称, 签名) 对列表构造 API 表面（后写覆盖先写）。
pub fn ApiSurface::new(entries : Array[(String, String)]) -> ApiSurface {
  let decls : Map[String, String] = Map([])
  for e in entries {
    let (name, sig) = e
    decls.set(name, sig)
  }
  { decls, }
}

///|
/// semver 升级档位（要求侧与实际侧共用）：PATCH < MINOR < MAJOR。
pub(all) enum BumpLevel {
  PatchBump
  MinorBump
  MajorBump
} derive(Eq)

///|
/// 兼容性 diff 报告：删除 / 签名变更（破坏性）与新增（兼容性）声明清单，
/// 及由此推导的最低要求升级档位。
pub struct CompatDiff {
  removed : Array[String]
  changed : Array[String]
  added : Array[String]
  required : BumpLevel
}

///|
/// 读取 diff 的破坏性声明清单（removed ∪ changed，字典序无关、去重后）。
pub fn CompatDiff::breaking(self : CompatDiff) -> Array[String] {
  let out : Array[String] = []
  for r in self.removed {
    out.push(r)
  }
  for c in self.changed {
    out.push(c)
  }
  out
}

///|
/// 计算新旧 API 表面的兼容性 diff：
///   removed = 旧有新无；changed = 两侧均有但签名不同；added = 新有旧无；
///   required = removed/changed 非空 → MAJOR；仅 added → MINOR；否则 PATCH。
pub fn compat_diff(old_api : ApiSurface, new_api : ApiSurface) -> CompatDiff {
  let removed : Array[String] = []
  let changed : Array[String] = []
  let added : Array[String] = []
  for name, old_sig in old_api.decls {
    match new_api.decls.get(name) {
      None => removed.push(name)
      Some(new_sig) => if old_sig != new_sig { changed.push(name) }
    }
  }
  for name, _sig in new_api.decls {
    if old_api.decls.get(name) is None {
      added.push(name)
    }
  }
  let required = if removed.length() > 0 || changed.length() > 0 {
    MajorBump
  } else if added.length() > 0 {
    MinorBump
  } else {
    PatchBump
  }
  { removed, changed, added, required }
}

///|
/// 实际版本升级的档位：MAJOR 增 → MAJOR；同 MAJOR 下 MINOR 增 → MINOR；
/// 仅 PATCH 增 → PATCH。非单调升级（新 ≤ 旧）或版本非法返回 None。
pub fn actual_bump(old_version : String, new_version : String) -> BumpLevel? {
  match
    (
      @release_meta.parse_semver(old_version),
      @release_meta.parse_semver(new_version),
    ) {
    (Some(o), Some(n)) =>
      if n.major > o.major {
        Some(MajorBump)
      } else if n.major == o.major && n.minor > o.minor {
        Some(MinorBump)
      } else if n.major == o.major && n.minor == o.minor && n.patch > o.patch {
        Some(PatchBump)
      } else {
        None
      }
    _ => None
  }
}

///|
/// 档位序：a 是否覆盖（≥）b。
fn bump_covers(a : BumpLevel, b : BumpLevel) -> Bool {
  match (a, b) {
    (MajorBump, _) => true
    (MinorBump, MajorBump) => false
    (MinorBump, _) => true
    (PatchBump, PatchBump) => true
    (PatchBump, _) => false
  }
}

///|
/// 发布流水线判定：给定新旧 API 表面与新旧版本号，校验实际升级档位
/// 覆盖 diff 要求档位。通过返回 None；违规返回首要诊断消息
/// （版本非法/不单调，或档位不足并列出首个破坏性声明）。
pub fn check_release_compat(
  old_api : ApiSurface,
  new_api : ApiSurface,
  old_version : String,
  new_version : String,
) -> String? {
  let diff = compat_diff(old_api, new_api)
  match actual_bump(old_version, new_version) {
    None =>
      Some(
        "invalid or non-increasing version: " +
        old_version +
        " -> " +
        new_version,
      )
    Some(actual) =>
      if bump_covers(actual, diff.required) {
        None
      } else {
        let kind = match diff.required {
          MajorBump => "breaking change requires MAJOR bump"
          MinorBump => "added API requires MINOR bump"
          PatchBump => "patch"
        }
        let witness = if diff.breaking().length() > 0 {
          diff.breaking()[0]
        } else if diff.added.length() > 0 {
          diff.added[0]
        } else {
          ""
        }
        Some(kind + " (e.g. `" + witness + "`)")
      }
  }
}
