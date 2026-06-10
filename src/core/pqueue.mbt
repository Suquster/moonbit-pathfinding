// Binary min-heap priority queue, generic over node type and weight type.
//
// Used by Dijkstra, A*, Yen, CH, ALT, and any other algorithm that needs to
// repeatedly extract the minimum-priority item.

///|
/// A min-heap priority queue with entries of type `(W, N)`.
///
/// Only the weight `W` needs to be `Compare`; the node `N` has no constraints
/// from the queue itself. This is important because Dijkstra-style algorithms
/// often use "stale entry skipping" and need to store arbitrary payloads.
pub struct PQueue[N, W] {
  priv heap : Array[(W, N)]
}

///|
/// Create an empty priority queue.
pub fn[N, W] PQueue::new() -> PQueue[N, W] {
  { heap: [] }
}

///|
/// Current number of entries in the queue.
pub fn[N, W] PQueue::len(self : PQueue[N, W]) -> Int {
  self.heap.length()
}

///|
/// Whether the queue is empty.
pub fn[N, W] PQueue::is_empty(self : PQueue[N, W]) -> Bool {
  self.heap.length() == 0
}

///|
/// Insert a node with the given priority weight. O(log n).
pub fn[N, W : Compare] PQueue::push(
  self : PQueue[N, W],
  weight : W,
  node : N,
) -> Unit {
  self.heap.push((weight, node))
  // Sift up from the last index.
  let mut i = self.heap.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if self.heap[parent].0 <= self.heap[i].0 {
      break
    }
    let tmp = self.heap[parent]
    self.heap[parent] = self.heap[i]
    self.heap[i] = tmp
    i = parent
  }
}

///|
/// Remove and return the minimum-weight entry, or `None` if empty. O(log n).
pub fn[N, W : Compare] PQueue::pop(self : PQueue[N, W]) -> (W, N)? {
  let n = self.heap.length()
  if n == 0 {
    return None
  }
  let top = self.heap[0]
  if n == 1 {
    ignore(self.heap.pop())
    return Some(top)
  }
  self.heap[0] = self.heap[n - 1]
  ignore(self.heap.pop())
  // Sift down from index 0.
  let size = self.heap.length()
  let mut i = 0
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut smallest = i
    if left < size && self.heap[left].0 < self.heap[smallest].0 {
      smallest = left
    }
    if right < size && self.heap[right].0 < self.heap[smallest].0 {
      smallest = right
    }
    if smallest == i {
      break
    }
    let tmp = self.heap[i]
    self.heap[i] = self.heap[smallest]
    self.heap[smallest] = tmp
    i = smallest
  }
  Some(top)
}
