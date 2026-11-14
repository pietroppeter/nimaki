Every place where nimaki knowingly behaves differently from Pele at the pin, with the reason
([decision 0003](#0003-pele-at-the-pin-is-the-specification-and-its-npm-package-is-the-oracle)).
Anything not listed here must be identical, byte for byte.

### Text that is not UTF-8

`render` and `detectType` read a byte that is not UTF-8 as U+FFFD, the replacement character, as
the browser's `TextDecoder` does
([decision 0015](#0015-regular-expressions-as-pele-writes-them-on-nim-regex)). A JavaScript
string cannot hold such a byte, so there is no Pele behaviour to copy; the nearest thing, a lone
surrogate, is dropped by Pele's `esc`, and is dropped by nimaki's too.

### Half of an emoji

A regular expression in JavaScript reads UTF-16 code units: without the `u` flag, `.` or a
negated class such as `[^"]` can match the first half of a character outside the Basic
Multilingual Plane (most emoji) and stop there. nimaki reads code points, so the same pattern
takes the whole character. No case of difftest or of the fuzzer draws differently because of it;
`tests/test_jsregex.nim` finds three of its probe strings where JavaScript stops inside an emoji,
and leaves them out of its comparison.
Where Pele counts in UTF-16 on purpose (`/\W/g` in use case ids, the fill character of a treemap
format), the port keeps a hand-written scanner that counts the same way.

### Captures inside a repeated group

In JavaScript a capture inside a repeated group, such as `(?:(a)|b)+`, is reset at each turn of
the repeat; in nitely's `regex` it keeps the last value it had. No pattern of Pele at the pin has
such a capture, and the wrapper's tests would show one that appears.
