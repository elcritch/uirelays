## Relay contract tests; no window or platform driver is initialized.
import std/unittest
import ../src/uirelays/[screen, coords]
import ../src/uirelays/pixelutils

var sourceW, sourceH, calls: int
var destination: Rect
var receivedFormat: RGBAFormat

proc draw(
    pixels: ptr UncheckedArray[uint32], w, h: int, dst: Rect, format: RGBAFormat
): bool =
  sourceW = w
  sourceH = h
  destination = dst
  receivedFormat = format
  inc calls
  true

suite "RGBA image relays":
  setup:
    let saved = drawRelays
    drawRelays.drawRGBA = draw
    drawRelays.blitRGBA = draw
    calls = 0
  teardown:
    drawRelays = saved

  test "full-resolution sources retain their logical destination":
    var pixels = [0xff0000'u32, 0x00ff00'u32, 0x0000ff'u32, 0xffffff'u32]
    check drawRGBA(
      cast[ptr UncheckedArray[uint32]](addr pixels[0]), 4, 1, rect(5, 6, 2, 1)
    )
    check sourceW == 4
    check sourceH == 1
    check destination == rect(5, 6, 2, 1)
    check receivedFormat == RGBAFormat.rgbOpaque

  test "alpha draws and clipping-only blits pass the format unchanged":
    var pixels = [0x80800000'u32, 0x00000000'u32]
    let data = cast[ptr UncheckedArray[uint32]](addr pixels[0])
    check drawRGBA(data, 2, 1, rect(3, 4, 8, 4), RGBAFormat.argbPremultiplied)
    check receivedFormat == RGBAFormat.argbPremultiplied
    check sourceW == 2
    check destination == rect(3, 4, 8, 4)
    check blitRGBA(data, 2, 1, rect(3, 4, 1, 1), RGBAFormat.argbPremultiplied)
    check receivedFormat == RGBAFormat.argbPremultiplied
    check pixels == [0x80800000'u32, 0x00000000'u32]

  test "legacy fallback retains alpha and still refuses scaling":
    drawRelays.drawRGBA = nil
    var pixel = 0x80800000'u32
    let data = cast[ptr UncheckedArray[uint32]](addr pixel)
    check drawRGBA(data, 1, 1, rect(0, 0, 1, 1), RGBAFormat.argbPremultiplied)
    check receivedFormat == RGBAFormat.argbPremultiplied
    check not drawRGBA(data, 1, 1, rect(0, 0, 2, 1), RGBAFormat.argbPremultiplied)

  test "legacy relay fallback requires matching dimensions":
    drawRelays.drawRGBA = nil
    var pixels = [0'u32, 0'u32]
    let data = cast[ptr UncheckedArray[uint32]](addr pixels[0])
    check drawRGBA(data, 2, 1, rect(0, 0, 2, 1))
    check calls == 1
    check not drawRGBA(data, 2, 1, rect(0, 0, 1, 1))
    check calls == 1

  test "invalid images do not invoke the driver":
    check not drawRGBA(nil, 1, 1, rect(0, 0, 1, 1))
    check calls == 0
    var pixel = 0'u32
    let data = cast[ptr UncheckedArray[uint32]](addr pixel)
    check not blitRGBA(data, int.high, 2, rect(0, 0, 1, 1))
    check not drawRGBA(data, 1, 0, rect(0, 0, 1, 1))
    check calls == 0

suite "opaque RGB image resizing":
  test "premultiplied resampling interpolates alpha with the color channels":
    var pixels = [0x80800000'u32, 0x00000000'u32]
    let data = cast[ptr UncheckedArray[uint32]](addr pixels[0])
    check resizedRGBA(data, 2, 1, 1, 1, preserveAlpha = true) == @[0x40400000'u32]
  test "matching sizes retain every channel and source row":
    var pixels = [0xff0000'u32, 0x00ff00'u32, 0x0000ff'u32, 0xffffff'u32]
    let data = cast[ptr UncheckedArray[uint32]](addr pixels[0])
    check resizedRGBA(data, 2, 2, 2, 2) == @pixels

  test "bilinear downsampling averages complete sources":
    var pixels = [0xff0000'u32, 0x0000ff'u32]
    let data = cast[ptr UncheckedArray[uint32]](addr pixels[0])
    check resizedRGBA(data, 2, 1, 1, 1) == @[0x800080'u32]
    check resizedRGBA(data, 2, 1, 4, 1) ==
      @[0xff0000'u32, 0xbf0040'u32, 0x4000bf'u32, 0x0000ff'u32]

  test "invalid dimensions are rejected":
    var pixel = 0'u32
    expect ValueError:
      discard resizedRGBA(cast[ptr UncheckedArray[uint32]](addr pixel), 1, 1, 0, 1)
