const
  UNINIT* = 0u
  READER* = 1u
  WRITER* = 2u
  CONSUMED* = 3u

  FLAG_MASK* = 1u shl 3 - 1
  PTR_MASK* = high(uint) xor FLAG_MASK