## port-of: src/diagrams/common/caseless.ts
## port-status: conformant

func wordAt*(src: string, at: int, word: string): bool =
  ## Whether `word`, written in lower case, is at `at`. Only ASCII letters match in either case,
  ## as with the `i` flag on a regular expression without the `u` flag. Offsets are bytes: a
  ## character outside ASCII never matches, as `word` is ASCII.
  for k in 0 ..< word.len:
    if at + k >= src.len: return false
    let c = ord(src[at + k])
    let w = ord(word[k])
    if c != w and not (w >= 97 and w <= 122 and c == w - 32): return false
  true
