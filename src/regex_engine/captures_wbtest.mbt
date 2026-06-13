// captures_wbtest.mbt —— 捕获结果 `Captures` 白盒单元测试（任务 4.2）。
//
// `Captures` 是只读公开结构（`pub struct`，用户仅经 `group`/`name`/
// `group_count` 检索）。本测试为**白盒**（`_wbtest.mbt`），在包内直接构造
// 寄存器布局以独立校验检索语义（R1.4/1.5/1.6/8.4），无需经完整执行流水线。

///|
/// 整体组（0）与各子组区间检索；未设置组（任一端为 -1）返回 `None`。
test "Captures::group returns overall and sub-group spans, None for unset" {
  // slots: 组0=[0,5) 组1=[0,2) 组2=未设置(-1) 组3=[3,5)
  let names : Map[String, Int] = Map([])
  names["tail"] = 3
  let caps : Captures = { slots: [0, 5, 0, 2, -1, -1, 3, 5], names }
  assert_true(caps.group(0) == Some({ start: 0, end: 5 }))
  assert_true(caps.group(1) == Some({ start: 0, end: 2 }))
  // 第 2 组未参与匹配 → None（而非整体失败）。
  assert_true(caps.group(2) == None)
  assert_true(caps.group(3) == Some({ start: 3, end: 5 }))
  // 含第 0 组共 4 组。
  assert_eq(caps.group_count(), 4)
}

///|
/// 越界查询返回 `None`。
test "Captures::group out of range returns None" {
  let caps : Captures = { slots: [0, 3], names: Map([]) }
  assert_eq(caps.group_count(), 1)
  assert_true(caps.group(0) == Some({ start: 0, end: 3 }))
  assert_true(caps.group(1) == None)
  assert_true(caps.group(-1) == None)
  assert_true(caps.group(99) == None)
}

///|
/// 命名检索与编号检索一致；未知名称返回 `None`。
test "Captures::name agrees with numbered group and None for unknown" {
  let names : Map[String, Int] = Map([])
  names["year"] = 1
  names["day"] = 2
  let caps : Captures = { slots: [0, 10, 0, 4, 6, 10], names }
  // 命名检索得到与编号检索一致的区间。
  assert_true(caps.name("year") == caps.group(1))
  assert_true(caps.name("year") == Some({ start: 0, end: 4 }))
  assert_true(caps.name("day") == caps.group(2))
  // 未知名称 → None。
  assert_true(caps.name("month") == None)
}

///|
/// 命名组未参与匹配时按名检索返回 `None`。
test "Captures::name returns None for unset named group" {
  let names : Map[String, Int] = Map([])
  names["opt"] = 1
  let caps : Captures = { slots: [0, 5, -1, -1], names }
  assert_true(caps.name("opt") == None)
}
