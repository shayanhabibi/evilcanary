import std/strformat
import std/strutils
import std/atomics
import std/hashes

import evilcanary


echo fmt"""
OPTIONS:
  objectCount = {$objectCount}
  threadCount = {$threadCount}
  doNoop = {$doNoop}
  doRef = {$doRef}
  doQueueFirst = {$doQueueFirst}
  noPeeking = {$noPeeking}
"""

type
  Co = object
    r: bool
    e: int
when defined(doRef):
  type C = ref Co
else:
  type C = ptr Co

var q = newEvilCage[C]()
var counter {.global.}: Atomic[int]

proc noop =
  when defined(doNoop):
    var i: int
    while true:
      let v = hash i
      if i == 1_000: break
      inc i
  else:
    discard

proc enqueue(c: C) =
  when not defined(noPeeking):
    c.r = true
    c.e = c.e + 1
  q.push(c)

proc runThings() {.thread.} =
  var i: int
  while true:
    var job = pop q
    if job.isNil:
      if counter.load() >= 1:
        break
    when defined(noPeeking):
      if counter.load(moRelaxed) >= objectCount:
        break
      else:
        enqueue job
        discard counter.fetchAdd(1, moRelaxed)
    else:
      if not job.isNil and job.r:
        if job.e < 2:
          enqueue job
        elif job.e == 2:
          noop()
          enqueue job
        else:
          discard counter.fetchAdd(1, moRelaxed)

proc main =
  ## Dumb shit
  var threads: seq[Thread[void]]
  newSeq(threads, threadCount)
  template startThreads: untyped =
    for thread in threads.mitems:
      createThread(thread, runThings)
    echo "created $# threads" % [ $threadCount ]
  template enqueueObjects: untyped =
    for i in 0 ..< objectCount:
      when defined(doRef):
        var c = new C
      else:
        var c = cast[C](createShared(Co))
      enqueue c
    when defined(doRef):
      echo "queued $# ref objects" % [ $objectCount ]
    else:
      echo "queued $# ptr objects" % [ $objectCount ]
  template joinAllThreads: untyped =
    for thread in threads.mitems:
      joinThread thread
    echo "joined $# threads" % [ $threadCount ]

  when defined(doQueueFirst):
    enqueueObjects()
    startThreads()
    joinAllThreads()
  else:
    startThreads()
    enqueueObjects()
    joinAllThreads()

  var endCount: int
  var loadedIn: int
  var refval: string
  for i in 0..<painLevel:
    let val = q.feed[i].load()
    if (val and CONSUMED) == CONSUMED:
      inc endCount
    elif (val and WRITER) == WRITER:
      inc loadedIn
      refval =
        cast[C](q.feed[i].load() and PTR_MASK).repr
  when defined(noPeeking):
    doAssert endCount == (objectCount * 1), fmt " {endCount} were consumed; and {loadedIn} were written to"
  else:
    doAssert endCount == (objectCount * 3), fmt " {endCount} were consumed; and {loadedIn} were written to: {refval}"
  doAssert counter.load() == objectCount

main()