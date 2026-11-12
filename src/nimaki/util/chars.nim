## port-of: src/util/chars.ts
## port-status: draft
##
## Tests on UTF-16 code units, as the lexers read them with charCodeAt. Past the end of a string
## the code is NaN, which is none of these (here: -1, which is none of these either).

func isSpace*(c: int): bool =
  ## Whitespace as `\s` sees it.
  if c < 128: return c == 32 or (c >= 9 and c <= 13)
  c == 0xa0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200a) or c == 0x2028 or c == 0x2029 or
    c == 0x202f or c == 0x205f or c == 0x3000 or c == 0xfeff

func isBlank*(c: int): bool = c == 32 or c == 9

func isLineEnd*(c: int): bool =
  ## A line terminator: what `.` does not match.
  c == 10 or c == 13 or c == 0x2028 or c == 0x2029

func isDigit*(c: int): bool = c >= 48 and c <= 57

func isLetter*(c: int): bool = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

func isHex*(c: int): bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102)

func isWord*(c: int): bool =
  ## A character of `\w`.
  (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
