// regex_engine_proof.mbt —— Regex_Engine（R2）方向的契约谓词。
//
// 复用约定：正则语法树往返复用 `round_trip_eq`；本文件补充方向特有的
// NFA/DFA 差分一致性谓词。真实 `Regex` / `Nfa` / `Dfa` 差分测试把两条
// 执行路径的判定交给本纯、全（total）谓词比较。

///|
/// NFA/DFA 差分一致性。
///
/// 对同一输入，Thompson 构造的 NFA 与子集构造确定化的 DFA 必须给出一致的
/// 匹配判定。当且仅当二者结果相等时成立。实现为 `nfa_match == dfa_match`。
/// 这刻画了「同一正则的两条执行路径语义等价」这一核心正确性性质。
/// 纯、全函数，对任意两布尔输入恒返回 `Bool`。
pub fn nfa_dfa_consistent(nfa_match : Bool, dfa_match : Bool) -> Bool {
  nfa_match == dfa_match
}
