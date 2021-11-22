const
  objectCount* {.intdefine.} = 10_000
  threadCount* {.intdefine.} = 12
  doNoop* {.booldefine.} = false
  doRef* {.booldefine.} = false
  doQueueFirst* {.booldefine.} = false
  noPeeking* {.booldefine.} = false
  
  painLevel* = objectCount * 5
  UNINIT* = 0u
  READER* = 1u
  WRITER* = 2u
  EATEN* = WRITER shl 1
  CONSUMED* = READER or WRITER or EATEN
  FLAG_MASK* = 1u shl 3 - 1
  PTR_MASK* = high(uint) xor FLAG_MASK
