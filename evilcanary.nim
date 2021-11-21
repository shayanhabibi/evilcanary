import std/atomics
import evilcanary/spec

type
  EvilCage*[T; L: static int] = ref object
    head: Atomic[uint]
    paddingHead: array[63, uint]
    tail: Atomic[uint]
    paddingTail: array[63, uint]
    feed: array[L, Atomic[uint]]

proc fetchEarAss[T, L](ec: EvilCage[T, L]): (uint, uint) {.inline.} =
  (ec.head.load(moRelaxed), ec.tail.load(moRelaxed))

proc newEvilCage*[T](painLevel: static int = 1024): auto =
  result = new EvilCage[T, painLevel]
  result.head.store(0u, moRelaxed)
  result.tail.store(0u, moRelaxed)
  for i in 0..<painLevel:
    result.feed[i].store(0u, moRelaxed)


proc push*[T, L](ec: EvilCage[T, L], el: T): bool =
  # Returs a bool because it can be used in different tests
  var idx = ec.tail.fetchAdd(1, moAcquireRelease)
  assert idx < L, "You've exceeded the length of the cage."
  when T is ref:
    GC_ref el
  else:
    discard
  var pel = cast[uint](el) or spec.WRITER

  atomicThreadFence(ATOMIC_RELEASE)
  var prev = ec.feed[idx].fetchAdd(pel, moAcquireRelease)
  # assert prev == spec.UNINIT
  result = true

proc pop*[T, L](ec: EvilCage[T, L]): T =
  var (head, tail) = ec.fetchEarAss()
  var it: int
  if not head < tail:
    return
  var idx = ec.head.fetchAdd(1, moAcquireRelease)
  assert idx < L, "You've exceeded the length of the cage. Head: " & $head & " Tail: " & $tail
  var slotval = ec.feed[idx].fetchAdd(spec.READER, moAcquireRelease)
  var i: int
  while (slotval and spec.WRITER) == 0 and (slotval and PTR_MASK) == 0:
    slotval = ec.feed[idx].load(moRelaxed)
    if i == 1_000:
      return
    else:
      inc i
  atomicThreadFence(ATOMIC_ACQUIRE)
  result = cast[T](slotval and PTR_MASK)
  when T is ref:
    GC_unref result
  else:
    discard
  