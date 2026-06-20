// router.mbt —— 路由器与三种路由策略（任务 8.1，Requirement 8）。
//
//   * `RoundRobin`     —— 按固定循环顺序分发（Requirement 8.2）；
//   * `Broadcast`      —— 复制到全部 worker 各一份（Requirement 8.3）；
//   * `ConsistentHash` —— 按路由键的一致性哈希定位 worker（Requirement 8.4 / 8.5）。
//
// 三后端确定性：一致性哈希仅用**整数运算**（FNV-1a over 码点字节），环节点按
// `(hash, worker_index)` 全序排序消除并列歧义，绝不使用浮点（design §三后端一致性）。

// ───────────────────────────── 路由策略 ──────────────────────────────────

///|
/// 路由策略（routing strategy）（Requirement 8.1）。
pub(all) enum RoutingStrategy {
  RoundRobin
  Broadcast
  ConsistentHash
} derive(Eq, Show)

///|
/// 路由器（router）—— 以一组 worker 与策略构造。
pub struct Router[M] {
  strategy : RoutingStrategy
  workers : Array[ActorRef[M]]
  mut cursor : Int
}

///|
/// 以策略与一组 worker 构造路由器（游标从 0 起）。
pub fn[M] Router::new(
  strategy : RoutingStrategy,
  workers : Array[ActorRef[M]],
) -> Router[M] {
  { strategy, workers, cursor: 0 }
}

///|
/// worker 数量。
pub fn[M] Router::worker_count(self : Router[M]) -> Int {
  self.workers.length()
}

// ───────────────────────────── FNV-1a 整数哈希 ───────────────────────────

///|
/// 32 位 FNV-1a 哈希（over 字符串码点的小端 4 字节）—— 纯整数、三后端一致。
fn fnv1a_hash(key : String) -> UInt {
  let prime : UInt = 16777619
  let mut h : UInt = 2166136261
  for c in key {
    let code = c.to_int()
    let mut shift = 0
    while shift < 32 {
      let byte = (code >> shift) & 0xff
      h = (h ^ byte.reinterpret_as_uint()) * prime
      shift = shift + 8
    }
  }
  h
}

///|
/// 一致性哈希环节点：(节点哈希, worker 下标)。
struct RingNode {
  hash : UInt
  index : Int
}

///|
/// 构造排序后的哈希环：每个 worker 以其 id 派生一个环节点，按 (hash, index) 升序
/// 全序排序（消除并列歧义，保证三后端一致）。
fn[M] Router::ring(self : Router[M]) -> Array[RingNode] {
  let nodes : Array[RingNode] = []
  for i in 0..<self.workers.length() {
    let h = fnv1a_hash("worker#\{self.workers[i].id.value}")
    nodes.push({ hash: h, index: i })
  }
  // 插入排序（worker 数较小），按 (hash, index) 全序。
  for i in 1..<nodes.length() {
    let cur = nodes[i]
    let mut j = i - 1
    while j >= 0 &&
          (
            nodes[j].hash > cur.hash ||
            (nodes[j].hash == cur.hash && nodes[j].index > cur.index)
          ) {
      nodes[j + 1] = nodes[j]
      j = j - 1
    }
    nodes[j + 1] = cur
  }
  nodes
}

// ───────────────────────────── 分发 ──────────────────────────────────────

///|
/// 分发一条消息（RoundRobin / Broadcast 主入口；ConsistentHash 以空键退化）。
///
///   * `RoundRobin` —— 按游标命中下一 worker，游标循环递进（Requirement 8.2）；
///   * `Broadcast`  —— 复制到全部 worker（Requirement 8.3）；
///   * `ConsistentHash` —— 等价于 `route_keyed("", msg)`（一般应改用 `route_keyed`）。
pub fn[M] Router::route(self : Router[M], msg : M) -> Unit {
  match self.strategy {
    RoundRobin => {
      if self.workers.is_empty() {
        return
      }
      let target = self.workers[self.cursor % self.workers.length()]
      target.send(msg)
      self.cursor = (self.cursor + 1) % self.workers.length()
    }
    Broadcast =>
      for w in self.workers {
        w.send(msg)
      }
    ConsistentHash => self.route_keyed("", msg)
  }
}

///|
/// 携带路由键的分发（ConsistentHash 主入口；其它策略忽略 key 委托 `route`）。
///
/// ConsistentHash：以 key 的哈希在排序哈希环上顺时针选取首个 `hash >= key_hash`
/// 的节点（无则回绕到环首），worker 集合不变时相同键稳定命中同一 worker
/// （Requirement 8.4 / 8.5 / 8.8）。
pub fn[M] Router::route_keyed(self : Router[M], key : String, msg : M) -> Unit {
  match self.strategy {
    ConsistentHash => {
      if self.workers.is_empty() {
        return
      }
      let idx = self.index_for_key(key)
      self.workers[idx].send(msg)
    }
    _ => self.route(msg)
  }
}

///|
/// 计算某 key 在哈希环上命中的 worker 下标（纯函数，可观测）。
fn[M] Router::index_for_key(self : Router[M], key : String) -> Int {
  let ring = self.ring()
  if ring.is_empty() {
    return 0
  }
  let kh = fnv1a_hash(key)
  for node in ring {
    if node.hash >= kh {
      return node.index
    }
  }
  // 回绕到环首。
  ring[0].index
}

///|
/// 某 key 在 ConsistentHash 下命中的 worker 标识（可观测：键→worker，Requirement 8.5）。
/// 非 ConsistentHash 策略以当前游标对应 worker 作为可观测目标。
pub fn[M] Router::worker_for_key(self : Router[M], key : String) -> ActorId {
  if self.workers.is_empty() {
    return { value: -1 }
  }
  match self.strategy {
    ConsistentHash => self.workers[self.index_for_key(key)].id
    _ => self.workers[self.cursor % self.workers.length()].id
  }
}
