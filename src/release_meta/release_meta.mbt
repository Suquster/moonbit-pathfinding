// release_meta.mbt —— 独立发布元数据模型与 release-ready 聚合门禁。
//
// 设计依据（design.md §「数据模型 → 发布元数据模型」）：
//
//   pub struct DirectionRelease {
//     name : String              // 方向包名，如 "regex_engine"
//     version : String           // SemVer，如 "0.1.0"
//     changelog_path : String    // 该方向的 CHANGELOG 路径
//     release_ready : Bool       // 测试 + 证明谓词 + 可执行文档全绿才为 true
//   }
//
// ── 各方向独立 SemVer 与 changelog 约定（Requirement 11.5）──────────────
//
// SemVer 约定：
//   * 每个方向（`src/{方向}` 子包）作为可独立发布单元，拥有**独立**的
//     语义化版本号，形如 `MAJOR.MINOR.PATCH`（遵循 https://semver.org）；
//   * 骨架阶段（broadth-first）首版一律登记为 `0.1.0`——主版本号 0 表示
//     公共 API 仍可能演进，与 umbrella 模块自身的 `moon.mod.json` 版本解耦；
//   * 版本号合法性由本包 `parse_semver` / `is_valid_semver` 纯函数校验，
//     仅接受三段非负整数，不接受 `v` 前缀或预发布 / 构建元数据后缀，
//     以保持骨架阶段门禁的确定性与三后端一致性。
//
// changelog 约定：
//   * 每个方向维护一份**独立**的变更日志，约定路径为
//     `src/{方向}/CHANGELOG.md`（见 `default_changelog_path`）；
//   * 格式沿用仓库根 CHANGELOG 的 Keep a Changelog + 双语风格，
//     由各方向子 spec 在登记 `DirectionRelease` 时一并建立。
//
// ── release-ready 聚合门禁（Requirement 11.6）──────────────────────────
//
//   只有当某方向的「测试」「证明谓词」「可执行文档」三项质量门禁**全部**
//   通过时，该方向才允许进入发布就绪（release-ready）状态。聚合判定被实现
//   为纯函数（三项布尔 → release_ready），便于在 CI 聚合检查中复用，并可被
//   属性测试穷举验证。

///|
/// 方向质量门禁三要素。
///
/// 三个布尔分别对应 design.md 测试策略中区分的三条独立证据链：
///   * `tests_passing`：三后端（wasm-gc / native / js）测试套件全绿；
///   * `proofs_passing`：`src/proofs/{方向}_proof.mbt` 证明谓词校验全绿；
///   * `docs_passing`：`moon test *.mbt.md` 可执行文档校验全绿。
pub(all) struct QualityGates {
  tests_passing : Bool
  proofs_passing : Bool
  docs_passing : Bool
} derive(Eq, Show)

///|
/// 方向发布元数据模型（design.md「数据模型 → 发布元数据模型」）。
///
/// 每个方向作为独立发布单元，由一份 `DirectionRelease` 描述其发布身份与
/// 当前是否满足发布就绪门禁。
pub(all) struct DirectionRelease {
  name : String
  version : String
  changelog_path : String
  release_ready : Bool
} derive(Eq, Show)

///|
/// 语义化版本号（SemVer）的结构化表示：`MAJOR.MINOR.PATCH`。
pub(all) struct SemVer {
  major : Int
  minor : Int
  patch : Int
} derive(Eq, Show)

///|
/// 聚合判定纯函数：给定质量门禁三要素，返回该方向是否可进入 release-ready。
///
/// 语义即三项门禁的逻辑合取（all-green gate）——任一门禁未通过即不就绪
/// （Requirement 11.6）。本函数为纯函数，无副作用，便于 CI 聚合检查复用
/// 并可被属性测试在 2^3 个输入上穷举验证。
pub fn aggregate_release_ready(gates : QualityGates) -> Bool {
  gates.tests_passing && gates.proofs_passing && gates.docs_passing
}

///|
/// 聚合判定纯函数（裸布尔入口）：测试 / 证明谓词 / 可执行文档三项布尔
/// → release_ready。
///
/// 与 `aggregate_release_ready` 语义完全一致，仅免去构造 `QualityGates`，
/// 方便调用方直接传入三项布尔。
pub fn release_ready_of(
  tests_passing : Bool,
  proofs_passing : Bool,
  docs_passing : Bool,
) -> Bool {
  tests_passing && proofs_passing && docs_passing
}

///|
/// 显式构造 `DirectionRelease`（`release_ready` 由调用方给定）。
pub fn DirectionRelease::new(
  name : String,
  version : String,
  changelog_path : String,
  release_ready : Bool,
) -> DirectionRelease {
  { name, version, changelog_path, release_ready }
}

///|
/// 依据质量门禁评估并构造 `DirectionRelease`：`release_ready` 由
/// `aggregate_release_ready` 计算，杜绝「门禁未全绿却标记为就绪」的不一致。
pub fn DirectionRelease::evaluate(
  name : String,
  version : String,
  changelog_path : String,
  gates : QualityGates,
) -> DirectionRelease {
  {
    name,
    version,
    changelog_path,
    release_ready: aggregate_release_ready(gates),
  }
}

///|
/// 方向 changelog 的约定路径：`src/{方向}/CHANGELOG.md`。
pub fn default_changelog_path(name : String) -> String {
  "src/" + name + "/CHANGELOG.md"
}

///|
/// 解析语义化版本号字符串 `MAJOR.MINOR.PATCH`。
///
/// 仅接受恰好三段、每段为非空非负十进制整数的形式；含 `v` 前缀、字母、
/// 预发布 / 构建元数据后缀或段数不为 3 时返回 `None`（保持骨架阶段门禁
/// 的确定性）。逐字符扫描而不依赖字符串切分 API，以保证三后端行为一致。
pub fn parse_semver(s : String) -> SemVer? {
  let parts : Array[Int] = []
  let mut cur = 0
  let mut has_digit = false
  for c in s {
    let code = c.to_int()
    if code >= 0x30 && code <= 0x39 {
      // 数字 '0'..'9'
      cur = cur * 10 + (code - 0x30)
      has_digit = true
    } else if code == 0x2E {
      // 分隔符 '.'
      if !has_digit {
        return None
      }
      parts.push(cur)
      cur = 0
      has_digit = false
    } else {
      // 任何其它字符均非法
      return None
    }
  }
  if !has_digit {
    return None
  }
  parts.push(cur)
  if parts.length() != 3 {
    return None
  }
  Some({ major: parts[0], minor: parts[1], patch: parts[2] })
}

///|
/// 判定字符串是否为合法 SemVer（语法约定见 `parse_semver`）。
pub fn is_valid_semver(s : String) -> Bool {
  match parse_semver(s) {
    Some(_) => true
    None => false
  }
}
