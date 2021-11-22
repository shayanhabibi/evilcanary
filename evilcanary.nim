import std/atomics

import evilcanary/spec
export spec


type
  EvilCage*[T] = object
    head: Atomic[uint]
    paddingHead: array[63, uint]
    tail: Atomic[uint]
    paddingTail: array[63, uint]
    feed*: array[painLevel, Atomic[uint]]

proc newEvilCage*[T](): ptr EvilCage[T] =
  result = createShared(EvilCage[T])
  result.head.store(0u, moRelaxed)
  result.tail.store(0u, moRelaxed)
  for i in 0..<painLevel:
    result.feed[i].store(0u, moRelaxed)

proc push*[T](ec: ptr EvilCage[T], el: T) =
  var idx = ec.tail.fetchAdd(1, moAcquireRelease)
  doAssert idx < painLevel, "You've exceeded the length of the cage."
  when T is ref:
    GC_ref el
  else:
    discard
  var pel = cast[uint](el) or WRITER

  atomicThreadFence(ATOMIC_RELEASE)
  var prev = ec.feed[idx].fetchAdd(pel, moAcquireRelease)
  doAssert (prev and (high(uint) xor READER)) == UNINIT

proc pop*[T](ec: ptr EvilCage[T]): T =
  proc fetchEarAss: (uint, uint) =
    (ec.head.load(moRelaxed), ec.tail.load(moRelaxed))

  var (head, tail) = fetchEarAss()

  if not (head < tail):
    return

  var idx = ec.head.fetchAdd(1, moAcquireRelease)
  doAssert idx < painLevel, "You've exceeded the length of the cage. Head: " & $head & " Tail: " & $tail

  var slotval = ec.feed[idx].fetchOr(READER, moAcquireRelease)
  var i: int
  while (slotval and WRITER) == 0 and (slotval and PTR_MASK) == 0:
    slotval = ec.feed[idx].load(moRelaxed)
    if i >= 10: return
    inc i

  discard ec.feed[idx].fetchAdd(EATEN, moAcquireRelease)
  atomicThreadFence(ATOMIC_ACQUIRE)

  result = cast[T](slotval and PTR_MASK)
  when T is ref:
    GC_unref result
  else:
    discard

# ============================================================================