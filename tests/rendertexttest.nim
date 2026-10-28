## Text rendered into pixels of its own, by a driver that has no window: the
## way a GPU renderer with a window from elsewhere asks for its glyphs.
when defined(windows):
  import uirelays/screen
  import uirelays/drivers/winapi_driver

  initWinapiDriver()

  var metrics = FontMetrics()
  let font = openFont("", 16, metrics)
  doAssert font.int != 0
  doAssert metrics.lineHeight > 0

  let measured = measureText(font, "Hello, world")
  doAssert measured.w > 0 and measured.h > 0

  var pixels: seq[uint32]
  let fg = Color(r: 200, g: 100, b: 50, a: 255)
  let rendered = renderText(font, "Hello, world", fg, pixels)
  doAssert rendered == measured
  doAssert pixels.len == rendered.w * rendered.h

  var inked = 0
  for p in pixels:
    let a = p shr 24
    # Premultiplied: no channel is brighter than the pixel is opaque.
    doAssert ((p shr 16) and 0xFF) <= a
    doAssert ((p shr 8) and 0xFF) <= a
    doAssert (p and 0xFF) <= a
    if a > 0: inked.inc
  doAssert inked > 0
  doAssert inked < pixels.len, "text is drawn on transparency"

  doAssert renderText(font, "", fg, pixels) == TextExtent()
  doAssert pixels.len == 0
  closeFont(font)
  echo "rendertexttest: OK"
