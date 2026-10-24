## Real-window tests for native composition, with no FigDraw dependency.
## Linux requires an X11 display (for example xvfb-run).
include ../src/uirelays/drivers/siwin_driver

when defined(linux) or defined(bsd):
  type ReadImage {.bycopy.} = object
    width, height, offset, format: cint
    data: pointer
    byteOrder, unit, bitOrder, pad, depth, stride, bits: cint
    redMask, greenMask, blueMask: culong

  proc XGetImage(
    display: pointer,
    drawable: culong,
    x, y: cint,
    width, height: cuint,
    mask: culong,
    format: cint,
  ): ptr ReadImage {.cdecl, dynlib: "libX11.so(|.6)", importc.}

  proc XFree(data: pointer): cint {.cdecl, dynlib: "libX11.so(|.6)", importc.}

proc pixel(x, y: int): uint32 =
  when defined(linux) or defined(bsd):
    let window = xWindow.WindowX11SoftwareRendering(appWindow)
    let image = XGetImage(
      window.nativeDisplayHandle(),
      window.nativeWindowHandle().culong,
      x.cint,
      y.cint,
      1,
      1,
      culong.high,
      2,
    )
    doAssert image != nil and image.bits == 32
    result = cast[ptr uint32](image.data)[] and 0xffffff
    discard XFree(image.data)
    discard XFree(image)
  else:
    let buffer = appWindow.pixelBuffer()
    let bytes = cast[ptr UncheckedArray[uint8]](buffer.data)
    let offset = (y * buffer.size.x.int + x) * 4
    when defined(macosx):
      result =
        (bytes[offset].uint32 shl 16) or (bytes[offset + 1].uint32 shl 8) or
        bytes[offset + 2].uint32
    else:
      result =
        (bytes[offset + 2].uint32 shl 16) or (bytes[offset + 1].uint32 shl 8) or
        bytes[offset].uint32

proc main() =
  initSiwinDriver()
  discard screen.createWindow(64, 48)
  defer:
    shutdown()
  screen.fillRect(coords.rect(0, 0, 64, 48), screen.color(0, 0, 255))
  var source = [0x80800000'u32, 0x00000000'u32]
  doAssert screen.drawRGBA(
    cast[ptr UncheckedArray[uint32]](addr source[0]),
    2,
    1,
    coords.rect(0, 0, 2, 1),
    RGBAFormat.argbPremultiplied,
  )
  refresh()
  doAssert pixel(0, 0) == 0x80007f
  # Native drawing remains intact when Siwin replaces/presents its client buffer.
  refresh()
  doAssert pixel(0, 0) == 0x80007f
  let before = events.len
  refresh()
  doAssert events.len == before
  let oldSize = appWindow.size
  appWindow.size = oldSize + ivec2(20, 20)
  discard appGlobals.pollEvents()
  appWindow.redraw()
  appWindow.serviceWindow()
  bindSurface()
  doAssert pixel(0, 0) == 0x80007f
  screen.fillRect(coords.rect(0, 0, 4, 4), screen.color(0, 255, 0))
  refresh()
  doAssert pixel(0, 0) == 0x00ff00
  doAssert appWindow.size.x > oldSize.x
  echo "Native Siwin composition, refresh, alpha, and resize passed"

main()
