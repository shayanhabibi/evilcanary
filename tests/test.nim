
import std/osproc
import std/strutils
import std/logging
import std/atomics
import std/os
import std/macros
import std/hashes

import balls
import evilcanary

const
  continuationCount = 1_000
let
  threadCount = 12

type
  C = ref object
    r: bool
    e: int

addHandler newConsoleLogger()

setLogFilter:
  when defined(danger):
    lvlNotice
  elif defined(release):
    lvlInfo
  else:
    lvlDebug

var q = newEvilCage[C](150_000)


proc enqueue(c: C) =
  c.r = true
  c.e = c.e + 1
  discard q.push(c)

var counter {.global.}: Atomic[int]

proc noop =
  var i: int
  while true:
    let v = hash i
    if i == 1_000: break
    inc i


proc runThings() {.thread.} =
  var i: int
  while true:
    var job = pop q
    if job.isNil:
      if counter.load() > (continuationCount div 2):
        echo "breaking"
        break
      noop()
    elif job.r:
      if job.e < 2:
        enqueue job
      elif job.e == 2:
        noop()
        enqueue job
      else:
        discard counter.fetchAdd(1, moRelaxed)

template expectCounter(n: int): untyped =
  ## convenience
  try:
    check counter.load == n
  except Exception:
    checkpoint " counter: ", load counter
    checkpoint "expected: ", n
    raise

suite "evilCanary":
  block:
    ## Do some amazing shit
    var threads: seq[Thread[void]]
    newSeq(threads, threadCount)

    counter.store 0
    for thread in threads.mitems:
      createThread(thread, runThings)
    checkpoint "created $# threads" % [ $threadCount ]

    for i in 0 ..< continuationCount:
      var c = new C
      enqueue c
    checkpoint "queued $# ref objects" % [ $continuationCount ]

    for thread in threads.mitems:
      joinThread thread
    checkpoint "joined $# threads" % [ $threadCount ]
    echo repr q.pop()


    echo counter.load
    # expectCounter continuationCount
