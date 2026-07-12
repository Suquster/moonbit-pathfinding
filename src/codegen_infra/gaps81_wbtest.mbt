// gaps81_wbtest.mbt —— dom_ncd 支配树外节点回退臂收口（第八十一批）。

///|
/// b 既不在 a 的祖先链上、又无 idom 记录（支配树外节点）：
/// 上溯一步即失败，按约定返回 b 自身。
test "dom_ncd：树外节点无 idom 时返回其自身" {
  let idom : Map[String, String] = Map([])
  idom["a"] = "r"
  let children : Map[String, Array[String]] = Map([])
  children["r"] = ["a"]
  let dom : DomTree = { root: "r", idom, children, reachable: ["r", "a"] }
  assert_eq(dom_ncd(dom, "a", "z"), "z")
}
