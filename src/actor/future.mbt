// future.mbt —— async/await 风格 ask API（C2 旗舰深化）。
//
// 在既有 `AskBroker[R]` 关联注册表之上提供 `Future[R]` 抽象：`ask_future` 发起
// 请求立即返回句柄，`await_within` 才驱动系统等待完成——把「发起」与「等待」
// 解耦，可同时在飞多个请求（并发 ask），再逐个 await。组合子 `map` /
// `and_then` 支持结果的惰性变换与链式续体，语义确定性（不依赖墙钟），三后端
// 逐位一致。

///|
/// 异步结果句柄（future）：`resolve` 惰性从注册表拉取并变换底层响应。
///
/// 同一底层关联 id 的响应至多被消费一次（继承 `AskBroker::poll` 语义）；
/// 消费后句柄自身缓存结果，重复 `poll_result` / `await_within` 幂等返回。
pub struct Future[R] {
  resolve : () -> AskResult[R]
  mut cached : AskResult[R]?
}

///|
/// 由「已解析值」构造一个立即就绪的 future（单元构造子，组合子恒等元）。
pub fn[R] Future::ready(value : R) -> Future[R] {
  { resolve: () => Replied(value), cached: Some(Replied(value)) }
}

///|
/// 非阻塞轮询：已缓存直接返回；未缓存则尝试解析，成功（`Replied`）才缓存。
/// `Timeout` 不缓存——底层响应尚未到达时后续仍可再次轮询。
pub fn[R] Future::poll_result(self : Future[R]) -> AskResult[R] {
  match self.cached {
    Some(r) => r
    None =>
      match (self.resolve)() {
        Replied(v) => {
          self.cached = Some(Replied(v))
          Replied(v)
        }
        Timeout => Timeout
      }
  }
}

///|
/// future 是否已就绪（已缓存或底层响应已到达；观测用，不消费）。
pub fn[R] Future::is_ready(self : Future[R]) -> Bool {
  match self.cached {
    Some(_) => true
    None => self.poll_result() is Replied(_)
  }
}

///|
/// 结果变换组合子：就绪后把 `R` 映射为 `T`（惰性，不驱动系统）。
pub fn[R, T] Future::map(self : Future[R], f : (R) -> T) -> Future[T] {
  {
    resolve: () => {
      match self.poll_result() {
        Replied(v) => Replied(f(v))
        Timeout => Timeout
      }
    },
    cached: None,
  }
}

///|
/// 链式续体组合子：第一个 future 就绪后，用其值构造下一个 future 并轮询之。
/// 两段中的任一段未就绪即整体 `Timeout`（可反复轮询直至两段都完成）。
pub fn[R, T] Future::and_then(
  self : Future[R],
  f : (R) -> Future[T],
) -> Future[T] {
  {
    resolve: () => {
      match self.poll_result() {
        Replied(v) => f(v).poll_result()
        Timeout => Timeout
      }
    },
    cached: None,
  }
}

///|
/// 发起一次 async 风格 ask：分配关联 id、发送嵌入 id 的请求消息、**立即**返回
/// `Future[R]` 句柄（不驱动系统）。与 `ask()` 的区别：发起与等待解耦，可先
/// 发起多个请求（并发在飞），再分别 `await_within`。
pub fn[S, M, R] ask_future(
  _system : ActorSystem[S, M],
  broker : AskBroker[R],
  target : ActorRef[M],
  make_req : (CorrelationId) -> M,
) -> Future[R] {
  let id = broker.allocate()
  target.send(make_req(id))
  { resolve: () => broker.poll(id), cached: None }
}

///|
/// await：驱动 `system` 至多 `budget` 步等待 future 就绪；就绪即提前返回
/// `Replied(v)`，预算耗尽或系统空转仍未就绪返回 `Timeout`（确定性，无墙钟）。
pub fn[S, M, R] Future::await_within(
  self : Future[R],
  system : ActorSystem[S, M],
  budget : Int,
) -> AskResult[R] {
  let mut steps = 0
  for ;; {
    match self.poll_result() {
      Replied(v) => return Replied(v)
      Timeout => ()
    }
    if steps >= budget {
      return Timeout
    }
    if !system.step() {
      return self.poll_result()
    }
    steps = steps + 1
  }
}
