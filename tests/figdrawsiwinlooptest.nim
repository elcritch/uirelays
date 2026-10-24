## Headless regression tests for the optional FigDraw + Siwin relay driver.
## Build with FigDraw/Siwin dependency paths from an Atlas workspace.
import std/unittest
include ../src/uirelays/drivers/figdraw_siwin_driver

type
  TestGlobals = ref object of SiwinGlobals
    polls: int
    waits: seq[Duration]
    events: seq[input.EventKind]
    results: seq[EventWaitResult]

  TestWindow = ref object of siwin.Window
    renderPending: bool
    services: int

  TestContext = ref object of BackendContext
    table: Table[Hash, bumpy.Rect]
    metadata: Table[Hash, AtlasEntryMeta]
    puts, updates, draws: int

method pollEventsImpl(globals: TestGlobals): bool =
  inc globals.polls
  false

method waitEventsImpl(globals: TestGlobals, timeout: Duration): EventWaitResult =
  let index = globals.waits.len
  globals.waits.add(timeout)
  if index < globals.events.len and globals.events[index] != input.NoEvent:
    queueEvent(input.Event(kind: globals.events[index]))
  if index < globals.results.len:
    globals.results[index]
  else:
    eventTimeout

method redraw(window: TestWindow) =
  window.renderPending = true

method serviceWindow(window: TestWindow) =
  inc window.services
  if window.renderPending:
    window.renderPending = false
    handleRenderRequest()

method entriesPtr(ctx: TestContext): ptr Table[Hash, bumpy.Rect] =
  addr ctx.table

method atlasEntryMetaPtr(ctx: TestContext): var Table[Hash, AtlasEntryMeta] =
  ctx.metadata

method putImage(ctx: TestContext, key: Hash, image: pixie.Image) =
  inc ctx.puts
  ctx.table[key] = bumpy.rect(0, 0, image.width.float32, image.height.float32)

method updateImage(ctx: TestContext, key: Hash, image: pixie.Image) =
  inc ctx.updates

method drawImage(
    ctx: TestContext,
    key: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  inc ctx.draws

suite "Siwin relay event loop":
  setup:
    let globals = TestGlobals()
    let window = TestWindow()
    appGlobals = globals
    appWindow = window
    eventQueue.clear()
    presentationPending = false
    renderer = nil
  teardown:
    appGlobals = nil
    appWindow = nil
    eventQueue.clear()

  test "polling services the window without waiting":
    var event: input.Event
    check not figPollEvent(event, {})
    check globals.polls == 1
    check globals.waits.len == 0
    check window.services == 1

  test "indefinite waits use the native event wait and return input":
    globals.events = @[MouseMoveEvent]
    globals.results = @[eventActivity]
    var event: input.Event
    check figWaitEvent(event, -1, {})
    check event.kind == MouseMoveEvent
    check globals.waits == @[high(Duration)]

  test "queued input returns without pumping or waiting":
    queueEvent(input.Event(kind: KeyDownEvent))
    var event: input.Event
    check figWaitEvent(event, -1, {})
    check globals.polls == 0
    check globals.waits.len == 0

  test "untranslated native wakes continue waiting":
    globals.events = @[input.NoEvent, KeyDownEvent]
    globals.results = @[eventActivity, eventActivity]
    var event: input.Event
    check figWaitEvent(event, -1, {})
    check event.kind == KeyDownEvent
    check globals.waits.len == 2

  test "finite native timeouts return false without polling sleeps":
    globals.results = @[eventTimeout]
    var event: input.Event
    check not figWaitEvent(event, 1000, {})
    check globals.waits.len == 1
    check globals.waits[0] > initDuration(milliseconds = 0)
    check globals.waits[0] <= initDuration(milliseconds = 1000)
    check not figWaitEvent(event, 0, {})
    check globals.waits.len == 1

  test "refresh presents without requesting another application frame":
    figRefresh()
    var event: input.Event
    check not figPollEvent(event, {})
    check not presentationPending
    check not figPollEvent(event, {})
    window.redraw() # A later native exposure still requests a repaint.
    check figPollEvent(event, {})
    check event.kind == input.NoEvent
    check not figPollEvent(event, {})

suite "Siwin relay animated pixel uploads":
  setup:
    pixelUploadSlots.setLen(0)
    let ctx = TestContext()
    let image = pixie.newImage(2, 2)

  test "animation updates one atlas entry and unchanged pixels skip upload":
    for frame in 0 ..< 100:
      ctx.replayPixels(
        DrawOp(
          kind: dopPixels,
          pixels: image,
          pixelsKey: Hash(frame + 1),
          pixelsDst: coords.rect(0, 0, 2, 2),
        ),
        0,
      )
    check ctx.puts == 1
    check ctx.updates == 99
    check ctx.table.len == 1

    ctx.replayPixels(
      DrawOp(
        kind: dopPixels,
        pixels: image,
        pixelsKey: Hash(100),
        pixelsDst: coords.rect(0, 0, 2, 2),
      ),
      0,
    )
    check ctx.updates == 99

  test "multiple blits retain distinct entries and atlas resets upload again":
    let op = DrawOp(
      kind: dopPixels,
      pixels: image,
      pixelsKey: Hash(1),
      pixelsDst: coords.rect(0, 0, 2, 2),
    )
    ctx.replayPixels(op, 0)
    ctx.replayPixels(op, 1)
    check ctx.table.len == 2
    check ctx.puts == 2
    ctx.table.clear()
    ctx.noteAtlasRebuilt()
    ctx.replayPixels(op, 0)
    check ctx.puts == 3

  test "resized buffers replace the same logical slot":
    ctx.replayPixels(
      DrawOp(
        kind: dopPixels,
        pixels: image,
        pixelsKey: Hash(1),
        pixelsDst: coords.rect(0, 0, 2, 2),
      ),
      0,
    )
    let larger = pixie.newImage(4, 4)
    ctx.replayPixels(
      DrawOp(
        kind: dopPixels,
        pixels: larger,
        pixelsKey: Hash(2),
        pixelsDst: coords.rect(0, 0, 4, 4),
      ),
      0,
    )
    check ctx.puts == 2
    check ctx.table.len == 1

when defined(uirelaysSiwinWindowTests):
  suite "Siwin relay native window":
    test "presentation does not feed repaint events and resize still invalidates":
      initFigDrawSiwinDriver()
      defer:
        figShutdown()
      var layout = ScreenLayout(width: 300, height: 220)
      figCreateWindow(layout, nil, 0)
      var event: input.Event
      while figPollEvent(event, {}):
        discard
      figFillRect(coords.rect(0, 0, layout.width, layout.height), color(40, 80, 120))
      figRefresh()
      while figPollEvent(event, {}):
        check event.kind != input.NoEvent
      check not figWaitEvent(event, 40, {})

      appWindow.size = ivec2(640, 480)
      var resized = false
      let deadline = getMonoTime() + initDuration(seconds = 1)
      while not resized and getMonoTime() < deadline:
        if figWaitEvent(event, 100, {}):
          resized = event.kind == WindowMetricsEvent
      check resized
      let afterResize = figGetWindowLayout()
      check event.x == afterResize.width
      check event.y == afterResize.height
