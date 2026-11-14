## V8's `Math.sin`, `cos`, `acos`, `atan` and `atan2`, for the C build. Not a port of a file of
## Pele: a port of the functions of fdlibm that V8 12.4 (Node 22, the oracle's) compiles in
## `src/base/ieee754.cc`. The C library gives the same results most of the time and differs in
## the last bit otherwise, which a layout that iterates (venn's) turns into a different drawing.
## `jsmath` calls these; the JavaScript build calls JavaScript's own.
##
## Arguments past 2^19·π/2 for sin and cos take fdlibm's long reduction, which is not ported:
## they fall back to the C library. No diagram of Pele turns that far.
##
## ====================================================
## Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
##
## Developed at SunSoft, a Sun Microsystems, Inc. business.
## Permission to use, copy, modify, and distribute this
## software is freely granted, provided that this notice
## is preserved.
## ====================================================
##
## The original source code covered by the above license above has been
## modified significantly by Google Inc.
## Copyright 2016 the V8 project authors. All rights reserved.
## (V8's licence is BSD-3-Clause; nimaki's NOTICE lists it.)

import std/math as nm

func highWord(x: float): int32 = cast[int32](cast[uint64](x) shr 32)
func lowWord(x: float): uint32 = cast[uint32](cast[uint64](x) and 0xFFFF_FFFF'u64)
func withWords(high: int32, low: uint32): float =
  cast[float]((cast[uint64](cast[uint32](high)) shl 32) or uint64(low))
func withLowWord(x: float, low: uint32): float =
  cast[float]((cast[uint64](x) and 0xFFFF_FFFF_0000_0000'u64) or uint64(low))

const NPIO2_HW = [
  0x3FF921FB'i32, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C,
  0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C,
  0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A,
  0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
  0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB,
  0x404858EB, 0x404921FB]

func remPio2(x: float, y: var array[2, float]): tuple[n: int32, ok: bool] =
  ## __ieee754_rem_pio2 for |x| up to 2^19·π/2; `ok` false beyond.
  const
    half = 5.00000000000000000000e-01
    invpio2 = 6.36619772367581382433e-01
    pio2_1 = 1.57079632673412561417e+00
    pio2_1t = 6.07710050650619224932e-11
    pio2_2 = 6.07710050630396597660e-11
    pio2_2t = 2.02226624879595063154e-21
    pio2_3 = 2.02226624871116645580e-21
    pio2_3t = 8.47842766036889956997e-32
  let hx = highWord(x)
  let ix = hx and 0x7FFFFFFF
  if ix <= 0x3FE921FB:
    y[0] = x
    y[1] = 0
    return (0'i32, true)
  if ix < 0x4002D97C:
    if hx > 0:
      var z = x - pio2_1
      if ix != 0x3FF921FB:
        y[0] = z - pio2_1t
        y[1] = (z - y[0]) - pio2_1t
      else:
        z -= pio2_2
        y[0] = z - pio2_2t
        y[1] = (z - y[0]) - pio2_2t
      return (1'i32, true)
    else:
      var z = x + pio2_1
      if ix != 0x3FF921FB:
        y[0] = z + pio2_1t
        y[1] = (z - y[0]) + pio2_1t
      else:
        z += pio2_2
        y[0] = z + pio2_2t
        y[1] = (z - y[0]) + pio2_2t
      return (-1'i32, true)
  if ix <= 0x413921FB:
    var t = abs(x)
    let n = int32(t * invpio2 + half)
    let fn = float(n)
    var r = t - fn * pio2_1
    var w = fn * pio2_1t
    if n < 32 and ix != NPIO2_HW[n - 1]:
      y[0] = r - w
    else:
      let j = ix shr 20
      y[0] = r - w
      var i = j - ((highWord(y[0]) shr 20) and 0x7FF)
      if i > 16:
        t = r
        w = fn * pio2_2
        r = t - w
        w = fn * pio2_2t - ((t - r) - w)
        y[0] = r - w
        i = j - ((highWord(y[0]) shr 20) and 0x7FF)
        if i > 49:
          t = r
          w = fn * pio2_3
          r = t - w
          w = fn * pio2_3t - ((t - r) - w)
          y[0] = r - w
    y[1] = (r - y[0]) - w
    if hx < 0:
      y[0] = -y[0]
      y[1] = -y[1]
      return (-n, true)
    return (n, true)
  (0'i32, false)

func kernelCos(x, y: float): float =
  const
    C1 = 4.16666666666666019037e-02
    C2 = -1.38888888888741095749e-03
    C3 = 2.48015872894767294178e-05
    C4 = -2.75573143513906633035e-07
    C5 = 2.08757232129817482790e-09
    C6 = -1.13596475577881948265e-11
  let ix = highWord(x) and 0x7FFFFFFF
  if ix < 0x3E400000:
    if int(x) == 0: return 1.0
  let z = x * x
  let r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
  if ix < 0x3FD33333:
    return 1.0 - (0.5 * z - (z * r - x * y))
  let qx = if ix > 0x3FE90000: 0.28125 else: withWords(ix - 0x00200000, 0)
  let iz = 0.5 * z - qx
  let a = 1.0 - qx
  a - (iz - (z * r - x * y))

func kernelSin(x, y: float, iy: int): float =
  const
    half = 5.00000000000000000000e-01
    S1 = -1.66666666666666324348e-01
    S2 = 8.33333333332248946124e-03
    S3 = -1.98412698298579493134e-04
    S4 = 2.75573137070700676789e-06
    S5 = -2.50507602534068634195e-08
    S6 = 1.58969099521155010221e-10
  let ix = highWord(x) and 0x7FFFFFFF
  if ix < 0x3E400000:
    if int(x) == 0: return x
  let z = x * x
  let v = z * x
  let r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
  if iy == 0: x + v * (S1 + z * r)
  else: x - ((z * (half * y - v * r) - y) - v * S1)

func fdSin*(x: float): float =
  let ix = highWord(x) and 0x7FFFFFFF
  if ix <= 0x3FE921FB: return kernelSin(x, 0.0, 0)
  if ix >= 0x7FF00000: return x - x
  var y: array[2, float]
  let (n, ok) = remPio2(x, y)
  if not ok: return nm.sin(x)
  case n and 3
  of 0: kernelSin(y[0], y[1], 1)
  of 1: kernelCos(y[0], y[1])
  of 2: -kernelSin(y[0], y[1], 1)
  else: -kernelCos(y[0], y[1])

func fdCos*(x: float): float =
  let ix = highWord(x) and 0x7FFFFFFF
  if ix <= 0x3FE921FB: return kernelCos(x, 0.0)
  if ix >= 0x7FF00000: return x - x
  var y: array[2, float]
  let (n, ok) = remPio2(x, y)
  if not ok: return nm.cos(x)
  case n and 3
  of 0: kernelCos(y[0], y[1])
  of 1: -kernelSin(y[0], y[1], 1)
  of 2: -kernelCos(y[0], y[1])
  else: kernelSin(y[0], y[1], 1)

func fdAcos*(x: float): float =
  const
    pi = 3.14159265358979311600e+00
    pio2_hi = 1.57079632679489655800e+00
    pio2_lo = 6.12323399573676603587e-17
    pS0 = 1.66666666666666657415e-01
    pS1 = -3.25565818622400915405e-01
    pS2 = 2.01212532134862925881e-01
    pS3 = -4.00555345006794114027e-02
    pS4 = 7.91534994289814532176e-04
    pS5 = 3.47933107596021167570e-05
    qS1 = -2.40339491173441421878e+00
    qS2 = 2.02094576023350569471e+00
    qS3 = -6.88283971605453293030e-01
    qS4 = 7.70381505559019352791e-02
  let hx = highWord(x)
  let ix = hx and 0x7FFFFFFF
  if ix >= 0x3FF00000:
    if ((uint32(ix - 0x3FF00000)) or lowWord(x)) == 0:
      return if hx > 0: 0.0 else: pi + 2.0 * pio2_lo
    return NaN
  if ix < 0x3FE00000:
    if ix <= 0x3C600000: return pio2_hi + pio2_lo
    let z = x * x
    let p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
    let q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
    let r = p / q
    return pio2_hi - (x - (pio2_lo - x * r))
  elif hx < 0:
    let z = (1.0 + x) * 0.5
    let p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
    let q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
    let s = nm.sqrt(z)
    let r = p / q
    let w = r * s - pio2_lo
    return pi - 2.0 * (s + w)
  else:
    let z = (1.0 - x) * 0.5
    let s = nm.sqrt(z)
    let df = withLowWord(s, 0)
    let c = (z - df * df) / (s + df)
    let p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
    let q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
    let r = p / q
    let w = r * s + c
    return 2.0 * (df + w)

const
  ATANHI = [4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01,
            1.57079632679489655800e+00]
  ATANLO = [2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17,
            6.12323399573676603587e-17]
  AT = [3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01,
        -1.11111104054623557880e-01, 9.09088713343650656196e-02, -7.69187620504482999495e-02,
        6.66107313738753120669e-02, -5.83357013379057348645e-02, 4.97687799461593236017e-02,
        -3.65315727442169155270e-02, 1.62858201153657823623e-02]

func fdAtan*(x: float): float =
  var x = x
  let hx = highWord(x)
  let ix = hx and 0x7FFFFFFF
  var id: int
  if ix >= 0x44100000:
    if ix > 0x7FF00000 or (ix == 0x7FF00000 and lowWord(x) != 0): return x + x
    return if hx > 0: ATANHI[3] + ATANLO[3] else: -ATANHI[3] - ATANLO[3]
  if ix < 0x3FDC0000:
    if ix < 0x3E400000:
      if 1.0e300 + x > 1.0: return x
    id = -1
  else:
    x = abs(x)
    if ix < 0x3FF30000:
      if ix < 0x3FE60000:
        id = 0
        x = (2.0 * x - 1.0) / (2.0 + x)
      else:
        id = 1
        x = (x - 1.0) / (x + 1.0)
    else:
      if ix < 0x40038000:
        id = 2
        x = (x - 1.5) / (1.0 + 1.5 * x)
      else:
        id = 3
        x = -1.0 / x
  let z = x * x
  let w = z * z
  let s1 = z * (AT[0] + w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10])))))
  let s2 = w * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * AT[9]))))
  if id < 0: return x - x * (s1 + s2)
  let r = ATANHI[id] - ((x * (s1 + s2) - ATANLO[id]) - x)
  if hx < 0: -r else: r

func fdAtan2*(y, x: float): float =
  const
    tiny = 1.0e-300
    pi_o_4 = 7.8539816339744827900E-01
    pi_o_2 = 1.5707963267948965580E+00
    pi = 3.1415926535897931160E+00
    pi_lo = 1.2246467991473531772E-16
  if x.isNaN or y.isNaN: return x + y
  let hx = highWord(x)
  let lx = lowWord(x)
  let ix = hx and 0x7FFFFFFF
  let hy = highWord(y)
  let ly = lowWord(y)
  let iy = hy and 0x7FFFFFFF
  if ((cast[uint32](hx) - 0x3FF00000'u32) or lx) == 0: return fdAtan(y)
  var m = ((hy shr 31) and 1) or ((hx shr 30) and 2)
  if (uint32(iy) or ly) == 0:
    case m
    of 0, 1: return y
    of 2: return pi + tiny
    else: return -pi - tiny
  if (uint32(ix) or lx) == 0: return if hy < 0: -pi_o_2 - tiny else: pi_o_2 + tiny
  if ix == 0x7FF00000:
    if iy == 0x7FF00000:
      case m
      of 0: return pi_o_4 + tiny
      of 1: return -pi_o_4 - tiny
      of 2: return 3.0 * pi_o_4 + tiny
      else: return -3.0 * pi_o_4 - tiny
    else:
      case m
      of 0: return 0.0
      of 1: return -0.0
      of 2: return pi + tiny
      else: return -pi - tiny
  if iy == 0x7FF00000: return if hy < 0: -pi_o_2 - tiny else: pi_o_2 + tiny
  let k = (iy - ix) shr 20
  var z: float
  if k > 60:
    z = pi_o_2 + 0.5 * pi_lo
    m = m and 1
  elif hx < 0 and k < -60:
    z = 0.0
  else:
    z = fdAtan(abs(y / x))
  case m
  of 0: z
  of 1: -z
  of 2: pi - (z - pi_lo)
  else: (z - pi_lo) - pi
