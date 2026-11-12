## How readable the colours of Pomice are: the browser mixes the tokens in Oklab
## (`color-mix(in oklab, ...)`); this does the same mix in Nim and measures the WCAG contrast
## ratio of a text colour on the paper (4.5 is the AA level for body text, 7 is AAA).

import std/[math, strutils]

type
  Srgb* = tuple[r, g, b: float]   ## sRGB, 0..1
  Lab = tuple[l, a, b: float]    ## Oklab

func srgbOf*(hex: string): Srgb =
  ## `#1B2631` as sRGB.
  let h = hex.strip(chars = {'#'})
  (parseHexInt(h[0..1]) / 255, parseHexInt(h[2..3]) / 255, parseHexInt(h[4..5]) / 255)

func toLinear(c: float): float =
  if c <= 0.04045: c / 12.92 else: pow((c + 0.055) / 1.055, 2.4)

func toGamma(c: float): float =
  let c = clamp(c, 0.0, 1.0)
  if c <= 0.0031308: 12.92 * c else: 1.055 * pow(c, 1 / 2.4) - 0.055

func oklab(c: Srgb): Lab =
  let (r, g, b) = (toLinear(c.r), toLinear(c.g), toLinear(c.b))
  let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
   1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
   0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)

func srgb(c: Lab): Srgb =
  let l = (c.l + 0.3963377774 * c.a + 0.2158037573 * c.b) ^ 3
  let m = (c.l - 0.1055613458 * c.a - 0.0638541728 * c.b) ^ 3
  let s = (c.l - 0.0894841775 * c.a - 1.2914855480 * c.b) ^ 3
  (toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
   toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
   toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))

func mixOklab*(a, b: Srgb, share: float): Srgb =
  ## `color-mix(in oklab, a share%, b)`, with `share` from 0 to 100.
  let (x, y, t) = (oklab(a), oklab(b), share / 100)
  srgb((x.l * t + y.l * (1 - t), x.a * t + y.a * (1 - t), x.b * t + y.b * (1 - t)))

func luminance(c: Srgb): float =
  0.2126 * toLinear(c.r) + 0.7152 * toLinear(c.g) + 0.0722 * toLinear(c.b)

func contrastRatio*(a, b: Srgb): float =
  ## The WCAG contrast ratio, from 1 (none) to 21 (black on white).
  let (x, y) = (luminance(a), luminance(b))
  (max(x, y) + 0.05) / (min(x, y) + 0.05)
