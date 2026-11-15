import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Bar icon and panel for phonelink. The phonelink command does all the work;
// this shows its state (`phonelink status --json`) and runs it.
//
// The panel is a header (the phone, how it's connected, and icon buttons for
// the rest) over a grid of tiles: the mirror, recent and pinned apps, and
// the full app list. Names and explanations live in tooltips.
//
// Left click opens the panel, right click mirrors the phone, middle click
// opens the full app picker.
Panel {
  id: root
  moduleName: "phonelink.panel"
  ipcTarget: "phonelink.panel"
  // This panel owns its IPC target, for the extra `network` call.
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string command: Quickshell.env("HOME") + "/.local/bin/phonelink"

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  // --- state -----------------------------------------------------------------

  property bool loaded: false
  property bool connected: false
  property string via: "none"
  property bool relayed: false
  property bool reconnecting: false
  // Where the phone's sound plays now, and the mirror's own setting. Each app
  // carries its setting in `apps`.
  property string sound: "phone"
  property string mirrorSound: "pc"

  // Sound switches clicked here wait in `soundQueue` and run one at a time, in
  // order. Until a status check that started after the last of them comes
  // back, the buttons show what was clicked (`expectedPrefs` per window,
  // `expectedNow` for where the sound plays), so an older status reply can't
  // flip a button back and make the next click send the opposite.
  property var soundQueue: []
  property var expectedPrefs: ({})
  property string expectedNow: ""
  property real soundDoneAt: 0
  // Apps taken off the panel here run `phonelink hide` one at a time. Their
  // tiles stay gone (`removed`) until a status check that started after the
  // last of them comes back.
  property var removeQueue: []
  property var removed: ({})
  property real removeDoneAt: 0
  property real statusStartedAt: 0
  property bool refreshQueued: false
  property bool queuedBrief: true
  readonly property string effectiveSound: expectedNow !== "" ? expectedNow : sound
  property string deviceName: ""
  property bool directUp: false
  property bool directSupported: false
  property bool directBusy: false
  property var apps: []

  // Phone windows come straight from Hyprland, so the icon lights up the
  // moment one opens rather than at the next status check.
  readonly property var phoneWindows: {
    var ids = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i].wayland
      var appId = toplevel && toplevel.appId ? String(toplevel.appId) : ""
      if (appId === "phonelink" || appId.indexOf("phonelink.") === 0) ids.push(appId)
    }
    return ids
  }
  readonly property bool mirrorOpen: phoneWindows.indexOf("phonelink") >= 0
  function appOpen(pkg) { return phoneWindows.indexOf("phonelink." + pkg) >= 0 }

  readonly property string viaGlyph: reconnecting ? "󰑐"
    : via === "direct" ? "󱚸"
    : via === "usb" ? "󰕓"
    : via === "wifi" ? "󰖩"
    : via === "tailscale" ? "󰖂"
    : "󰖪"

  readonly property string viaLabel: via === "direct" ? strings.t("viaDirect")
    : via === "usb" ? strings.t("viaUsb")
    : via === "wifi" ? strings.t("viaWifi")
    : via === "tailscale" ? (relayed ? strings.t("viaTailscaleRelayed") : strings.t("viaTailscale"))
    : strings.t("notConnected")

  readonly property string statusLabel: !loaded ? strings.t("checking")
    : reconnecting ? strings.t("reconnecting")
    : viaLabel

  readonly property string tooltip: connected || reconnecting
    ? strings.t("tooltipConnected").arg(deviceName || strings.t("phone"), statusLabel)
    : strings.t("tooltipDisconnected")

  readonly property int columns: 4

  // Header buttons, left to right.
  readonly property var tools: {
    var list = [{ kind: "network" }]
    // The direct link needs the phone nearby, so it's no use over Tailscale.
    if (directSupported && via !== "tailscale") list.push({ kind: "direct" })
    list.push({ kind: "menu" })
    if (connected) list.push({ kind: "disconnect" })
    return list
  }

  // While no phone is connected: connect to a paired one, or pair a new one.
  readonly property var starts: loaded && !connected && !reconnecting ? [{ kind: "connect" }, { kind: "pair" }] : []

  // The grid: the mirror, recent and pinned apps, and the full list.
  readonly property var tiles: {
    var list = [{ kind: "mirror" }]
    for (var i = 0; i < apps.length; i++) list.push({ kind: "app", app: apps[i] })
    list.push({ kind: "all" })
    return list
  }

  // Everything the keyboard reaches, by row and column: the header buttons,
  // the start buttons, then the grid.
  readonly property var items: {
    var list = []
    var i
    for (i = 0; i < tools.length; i++) list.push({ item: tools[i], row: 0, col: i, cols: tools.length })
    var row = 1
    if (starts.length > 0) {
      for (i = 0; i < starts.length; i++) list.push({ item: starts[i], row: 1, col: i, cols: starts.length })
      row = 2
    }
    for (i = 0; i < tiles.length; i++)
      list.push({ item: tiles[i], row: row + Math.floor(i / columns), col: i % columns, cols: columns })
    return list
  }
  readonly property int firstTile: items.length - tiles.length

  // The cursor stays on its item while the list changes under it (apps
  // reorder, buttons come and go), found again by its key. When its item is
  // gone, it takes whatever now stands in its place.
  property int selectedIndex: 0
  property string selectedKey: ""
  property int selectedRow: 0
  property int selectedCol: 0
  property bool cursorActive: false

  function itemKey(item) {
    return item.kind === "app" ? "app:" + item.app.package : item.kind
  }

  function isSelected(index) { return cursorActive && selectedIndex === index }

  function setCursor(index) {
    var entry = items[index]
    selectedIndex = index
    selectedKey = entry ? itemKey(entry.item) : ""
    selectedRow = entry ? entry.row : 0
    selectedCol = entry ? entry.col : 0
  }

  function select(index) {
    cursorActive = true
    setCursor(index)
  }

  function findCursor() {
    var i
    for (i = 0; i < items.length; i++) {
      if (itemKey(items[i].item) === selectedKey) {
        setCursor(i)
        return
      }
    }
    var place = 0
    for (i = 0; i < items.length; i++)
      if (items[i].row < selectedRow || (items[i].row === selectedRow && items[i].col <= selectedCol)) place = i
    setCursor(place)
  }

  onItemsChanged: findCursor()

  // The network map page, and the data it draws.
  property bool networkOpen: false
  property var network: null
  property int laneIndex: -1
  property bool laneByKeyboard: false

  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"

  // --- actions ---------------------------------------------------------------

  function run(args) {
    Quickshell.execDetached([root.command].concat(args))
    refreshSoon.restart()
  }

  function activate(row) {
    if (!row) return
    if (row.kind === "direct") {
      toggleDirect()
      return
    }
    if (row.kind === "network") {
      openNetwork()
      return
    }
    root.close()
    if (row.kind === "menu") Quickshell.execDetached(["omarchy-menu", "summon", "phone"])
    else if (row.kind === "mirror") run(["mirror"])
    else if (row.kind === "app") run(["open", row.app.package])
    else if (row.kind === "all") run(["apps"])
    else if (row.kind === "disconnect") run(["stop"])
    else if (row.kind === "connect") run(["connect"])
    else if (row.kind === "pair") run(["pair"])
  }

  // Phone windows share one sound, so an open window's row shows where it
  // plays now. A row for a window that isn't open shows where it will play
  // when that window opens. "pc", "phone", or "" for other rows.
  function rowIsOpen(row) {
    if (!row) return false
    if (row.kind === "mirror") return mirrorOpen
    if (row.kind === "app") return appOpen(row.app.package)
    return false
  }

  function rowKey(row) {
    return row.kind === "mirror" ? "mirror" : row.app.package
  }

  function soundOf(row) {
    if (!row || (row.kind !== "mirror" && row.kind !== "app")) return ""
    if (rowIsOpen(row)) return effectiveSound
    var key = rowKey(row)
    if (expectedPrefs[key] !== undefined) return expectedPrefs[key]
    return row.kind === "mirror" ? mirrorSound : row.app.sound
  }

  function toggleSound(row) {
    var current = soundOf(row)
    if (current === "") return
    var next = current === "pc" ? "phone" : "pc"
    var key = rowKey(row)

    var prefs = {}
    for (var k in expectedPrefs) prefs[k] = expectedPrefs[k]
    prefs[key] = next
    expectedPrefs = prefs
    if (rowIsOpen(row)) expectedNow = next

    // Each switch names its result, so a later one for the same window
    // replaces an earlier one still waiting.
    var queue = soundQueue.filter(function(item) { return item.key !== key })
    queue.push({ key: key, next: next })
    soundQueue = queue
    if (!soundProcess.running) runNextSound()
  }

  function runNextSound() {
    if (soundQueue.length === 0) {
      soundDoneAt = Date.now()
      refresh(!opened)
      return
    }
    var item = soundQueue[0]
    soundQueue = soundQueue.slice(1)
    soundProcess.command = [root.command, "sound", item.next, item.key]
    soundProcess.running = true
  }

  function removeApp(row) {
    if (!row || row.kind !== "app") return
    var pkg = row.app.package
    var map = {}
    for (var k in removed) map[k] = true
    map[pkg] = true
    removed = map
    apps = apps.filter(function(app) { return app.package !== pkg })
    removeQueue = removeQueue.concat([pkg])
    if (!removeProcess.running) runNextRemove()
  }

  function runNextRemove() {
    if (removeQueue.length === 0) {
      removeDoneAt = Date.now()
      refresh(!opened)
      return
    }
    removeProcess.command = [root.command, "hide", removeQueue[0]]
    removeQueue = removeQueue.slice(1)
    removeProcess.running = true
  }

  function toggleDirect() {
    if (directBusy) return
    shareDirectBusy(true)
    directProcess.command = [root.command, "direct", directUp ? "off" : "on"]
    directProcess.running = true
  }

  // The bar puts a copy of this widget on every monitor. The first copy checks
  // the phone for all of them and hands each what it found.
  function copies() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName).slice() : []
    if (items.indexOf(root) < 0) items.push(root)
    return items
  }

  // Should the bar ever list its widgets some other way, every copy checks
  // for itself rather than none of them.
  function isLeader() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return items.indexOf(root) <= 0
  }

  function shareDirectBusy(busy) {
    var items = copies()
    for (var i = 0; i < items.length; i++)
      if (items[i] && typeof items[i].setDirectBusy === "function") items[i].setDirectBusy(busy)
  }

  function setDirectBusy(busy) {
    directBusy = busy
  }

  // The monitor this copy of the widget is on.
  readonly property string screenName: {
    var window = button.QsWindow.window
    return window && window.screen ? String(window.screen.name) : ""
  }

  function openNetworkHere() {
    root.open()
    root.openNetwork()
  }

  // Calls from outside go where the bar sends its own panels' hotkeys: to a
  // copy that's open, else to the one on the monitor in focus.
  function targetCopy() {
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    var items = copies().filter(function(item) { return item && typeof item.openNetworkHere === "function" })
    var open = items.filter(function(item) { return item.opened === true })
    var pool = open.length > 0 ? open : items
    for (var i = 0; i < pool.length; i++)
      if (pool[i].screenName === focused) return pool[i]
    return pool.length > 0 ? pool[0] : root
  }

  function closeAll() {
    var items = copies()
    for (var i = 0; i < items.length; i++)
      if (items[i] && items[i].opened === true) items[i].close()
  }

  function openNetwork() {
    networkOpen = true
    laneIndex = -1
    refreshNetwork()
  }

  function closeNetwork() {
    networkOpen = false
    laneIndex = -1
  }

  function moveLane(dy) {
    var count = network && network.paths ? network.paths.length : 0
    if (count === 0) return
    laneIndex = laneIndex < 0 ? (dy > 0 ? 0 : count - 1) : Math.max(0, Math.min(count - 1, laneIndex + dy))
    laneByKeyboard = true
  }

  function refreshNetwork() {
    if (networkProcess.running) return
    networkProcess.running = true
  }

  // Everything here came from the computer and the phone, so it's checked,
  // bounded, and shown as plain text.
  function clean(value, max) {
    return typeof value === "string" ? value.slice(0, max || 64) : ""
  }
  function number(value) {
    return typeof value === "number" && isFinite(value) ? value : null
  }

  function parseNetwork(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object" || !Array.isArray(data.paths)) return

    var kinds = ["usb", "direct", "wifi", "tailscale"]
    var states = ["active", "connected", "available", "off", "unsupported"]
    var paths = []
    for (var i = 0; i < data.paths.length && paths.length < 4; i++) {
      var p = data.paths[i] || {}
      if (kinds.indexOf(p.kind) < 0) continue
      var link = p.link && typeof p.link === "object"
        ? { rttMs: number(p.link.rttMs) || 0, queueMs: number(p.link.queueMs) || 0, mbps: number(p.link.mbps) }
        : null
      var peer = p.peer && typeof p.peer === "object"
        ? { online: p.peer.online === true ? true : p.peer.online === false ? false : null,
            active: !!p.peer.active, direct: clean(p.peer.direct, 64) || null, relay: clean(p.peer.relay, 16) || null }
        : null
      paths.push({
        kind: p.kind,
        state: states.indexOf(p.state) >= 0 ? p.state : "off",
        phone: clean(p.phone, 72),
        computer: clean(p.computer, 40),
        found: clean(p.found, 20),
        otherChannel: p.otherChannel === true,
        link: link,
        peer: peer
      })
    }

    var streams = []
    var windows = Array.isArray(data.windows) ? data.windows : []
    for (var j = 0; j < windows.length && streams.length < 8; j++) {
      var w = windows[j] || {}
      streams.push({
        title: clean(w.title, 48),
        path: kinds.indexOf(w.path) >= 0 ? w.path : "wifi",
        sound: w.sound === true,
        bitRate: clean(w.bitRate, 8),
        codec: clean(w.codec, 8)
      })
    }

    var c = data.computer || {}
    var ph = data.phone && typeof data.phone === "object" ? data.phone : null
    var router = data.router && typeof data.router === "object" ? data.router : null
    network = {
      computer: { name: clean(c.name, 48), ssid: clean(c.ssid, 48) },
      phone: ph ? { name: clean(ph.name, 48), model: clean(ph.model, 48), ssid: clean(ph.ssid, 48), mobile: clean(ph.mobile, 20) } : null,
      router: router ? { ip: clean(router.ip, 20), sameAccessPoint: router.sameAccessPoint === false ? false : router.sameAccessPoint === true ? true : null } : null,
      port: { found: clean(data.port && data.port.found, 16) },
      paths: paths,
      windows: streams
    }
  }

  property string _networkText: ""

  Process {
    id: networkProcess
    running: false
    command: [root.command, "network", "--json"]
    stdout: StdioCollector {
      id: networkOut
      waitForEnd: true
      onStreamFinished: root._networkText = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.parseNetwork(String(networkOut.text || root._networkText || ""))
    }
  }

  // The map updates every 2 seconds, but only while it's open.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened && root.networkOpen
    onTriggered: root.refreshNetwork()
  }

  ShellIpc {
    target: "phonelink.panel"

    function open(): void { root.targetCopy().open() }
    function close(): void { root.closeAll() }
    function show(): void { root.targetCopy().open() }
    function hide(): void { root.closeAll() }
    function toggle(): void {
      var target = root.targetCopy()
      if (target.opened) root.closeAll()
      else target.open()
    }
    function network(): void { root.targetCopy().openNetworkHere() }
  }

  // Left and right move along a row, up and down to the nearest item in the
  // next row. The first key press lands on the mirror.
  function moveCursor(dx, dy) {
    var current = items[selectedIndex]
    if (!cursorActive || !current) {
      select(firstTile)
      return
    }
    if (dx !== 0) {
      var next = selectedIndex + dx
      if (next >= 0 && next < items.length && items[next].row === current.row) setCursor(next)
      return
    }
    var row = current.row + dy
    var x = (current.col + 0.5) / current.cols
    var best = -1
    var distance = 2
    for (var i = 0; i < items.length; i++) {
      if (items[i].row !== row) continue
      var d = Math.abs((items[i].col + 0.5) / items[i].cols - x)
      if (d < distance) {
        distance = d
        best = i
      }
    }
    if (best >= 0) setCursor(best)
  }

  onOpenedChanged: {
    if (!opened) {
      closeNetwork()
      return
    }
    cursorActive = false
    setCursor(0)
    refresh(false)
  }

  // --- status ----------------------------------------------------------------

  // A check asked for while one runs follows it rather than being dropped,
  // so the state after a change is always read after the change.
  function refresh(brief) {
    if (statusProcess.running) {
      queuedBrief = refreshQueued ? (queuedBrief && brief) : brief
      refreshQueued = true
      return
    }
    statusStartedAt = Date.now()
    statusProcess.command = brief
      ? [root.command, "status", "--json", "--brief"]
      : [root.command, "status", "--json"]
    statusProcess.running = true
  }

  // The device and app names come from the phone, so everything is checked
  // and shown as plain text.
  function parseStatus(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return

    var list = []
    var source = Array.isArray(data.apps) ? data.apps : []
    for (var i = 0; i < source.length && list.length < 8; i++) {
      var app = source[i] || {}
      var pkg = String(app.package || "")
      if (!/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/.test(pkg)) continue
      var icon = String(app.icon || "")
      list.push({
        package: pkg,
        name: String(app.name || pkg).slice(0, 60),
        icon: /^\/[^\n]+\.png$/.test(icon) ? icon : "",
        pinned: !!app.pinned,
        sound: app.sound === "phone" ? "phone" : "pc"
      })
    }

    var status = {
      connected: !!data.connected,
      via: ["direct", "wifi", "usb", "tailscale"].indexOf(data.via) >= 0 ? data.via : "none",
      relayed: !!data.relayed,
      reconnecting: !!data.reconnecting,
      name: typeof data.name === "string" ? data.name.slice(0, 80) : "",
      direct: !!data.direct,
      directSupported: !!data.directSupported,
      apps: list,
      sound: data.sound === "pc" ? "pc" : "phone",
      mirrorSound: data.mirrorSound === "phone" ? "phone" : "pc",
      startedAt: statusStartedAt
    }
    var items = copies()
    for (var j = 0; j < items.length; j++)
      if (items[j] && typeof items[j].applyStatus === "function") items[j].applyStatus(status)
  }

  function applyStatus(status) {
    connected = status.connected
    via = status.via
    relayed = status.relayed
    reconnecting = status.reconnecting
    if (status.name !== "") deviceName = status.name
    directUp = status.direct
    directSupported = status.directSupported
    if (removeQueue.length === 0 && !removeProcess.running && removeDoneAt > 0 && status.startedAt >= removeDoneAt)
      removed = ({})
    apps = status.apps.filter(function(app) { return !root.removed[app.package] })
    sound = status.sound
    mirrorSound = status.mirrorSound
    loaded = true

    // The switches clicked here are done and this check began after them, so
    // it shows their result: stop showing the clicks and show the state.
    if (soundQueue.length === 0 && !soundProcess.running && soundDoneAt > 0 && status.startedAt >= soundDoneAt) {
      expectedPrefs = ({})
      expectedNow = ""
    }
  }

  property string _statusText: ""

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: root._statusText = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.parseStatus(String(statusOut.text || root._statusText || ""))
      if (root.refreshQueued) {
        var brief = root.queuedBrief
        root.refreshQueued = false
        Qt.callLater(function() { root.refresh(brief) })
      }
    }
  }

  Process {
    id: soundProcess
    running: false
    command: []
    onExited: Qt.callLater(root.runNextSound)
  }

  Process {
    id: removeProcess
    running: false
    command: []
    onExited: Qt.callLater(root.runNextRemove)
  }

  Process {
    id: directProcess
    running: false
    command: []
    onExited: {
      root.shareDirectBusy(false)
      root.refresh(!root.opened)
    }
  }

  // A light check keeps the icon honest while the panel is closed; opening
  // the panel asks the phone for its name too.
  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.isLeader()) root.refresh(!root.opened)
  }

  Timer {
    id: refreshSoon
    interval: 3000
    onTriggered: root.refresh(!root.opened)
  }

  // --- bar icon --------------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄜"
    active: root.phoneWindows.length > 0
    activeColor: Commons.Color.accent
    dimmed: !root.connected && root.phoneWindows.length === 0
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run(["mirror"])
      else if (b === Qt.MiddleButton) root.run(["apps"])
      else root.toggle()
    }
  }

  // --- panel -----------------------------------------------------------------

  function toolGlyph(kind) {
    return kind === "network" ? "󰛳"
      : kind === "direct" ? "󱚸"
      : kind === "menu" ? "󰒓"
      : kind === "disconnect" ? "󰐥"
      : Commons.I18n.rightToLeft ? "󰁔" : "󰁍"
  }

  function toolTip(kind) {
    return kind === "network" ? strings.t("networkMap")
      : kind === "direct" ? (directBusy ? strings.t("directBusy") : directUp ? strings.t("directOn") : strings.t("directOff"))
      : kind === "menu" ? strings.t("moreOptions")
      : kind === "disconnect" ? strings.t("disconnect")
      : strings.t("back")
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(root.networkOpen ? 470 : 340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.networkOpen) {
          if (dx < 0) root.closeNetwork()
          else if (dy !== 0) root.moveLane(dy)
        } else {
          root.moveCursor(dx, dy)
        }
      }
      onActivateRequested: if (!root.networkOpen && root.cursorActive && root.items[root.selectedIndex]) root.activate(root.items[root.selectedIndex].item)
      onCloseRequested: root.networkOpen ? root.closeNetwork() : root.close()
      onDeleteRequested: if (!root.networkOpen && root.cursorActive && root.items[root.selectedIndex]) root.removeApp(root.items[root.selectedIndex].item)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m" || t === "M") root.activate({ kind: "mirror" })
        else if ((t === "s" || t === "S") && !root.networkOpen && root.cursorActive && root.items[root.selectedIndex]) root.toggleSound(root.items[root.selectedIndex].item)
        else if (t === "n" || t === "N") root.networkOpen ? root.closeNetwork() : root.openNetwork()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // The phone, how it's connected, and buttons for everything else.
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, toolRow.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.networkOpen ? "󰛳" : "󰄜"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.connected || root.networkOpen ? 1.0 : 0.45
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: toolRow.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.networkOpen ? strings.t("networkMap") : (root.deviceName || strings.t("phone"))
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
              // Set, so it mirrors in right-to-left languages.
              horizontalAlignment: Text.AlignLeft
            }

            // How the phone is connected, and a speaker when its sound plays here.
            Row {
              visible: !root.networkOpen
              width: parent.width
              spacing: Style.space(5)

              Text {
                id: viaIcon
                textFormat: Text.PlainText
                text: root.viaGlyph
                color: root.connected ? Commons.Color.accent : Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                RotationAnimation on rotation {
                  running: root.reconnecting && Style.duration(1000) > 0
                  from: 0
                  to: 360
                  loops: Animation.Infinite
                  duration: Style.duration(1200)
                  onRunningChanged: if (!running) viaIcon.rotation = 0
                }
              }
              Text {
                textFormat: Text.PlainText
                text: root.statusLabel
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                visible: root.connected && root.effectiveSound === "pc"
                textFormat: Text.PlainText
                text: "󰽟"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Row {
            id: toolRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Repeater {
              model: root.networkOpen ? [{ kind: "back" }] : root.tools

              PanelActionButton {
                required property var modelData
                required property int index
                readonly property bool on: modelData.kind === "direct" && root.directUp
                iconText: root.toolGlyph(modelData.kind)
                tooltipText: root.toolTip(modelData.kind)
                foreground: on ? Commons.Color.accent : root.bar.foreground
                hoverColor: modelData.kind === "disconnect" ? root.bar.urgent : foreground
                fontFamily: root.bar.fontFamily
                hasCursor: !root.networkOpen && root.isSelected(index)
                opacity: modelData.kind === "direct" && root.directBusy ? 0.5 : 1
                onHovered: function(isHovered) { if (isHovered && !root.networkOpen) root.select(index) }
                onClicked: modelData.kind === "back" ? root.closeNetwork() : root.activate(modelData)
              }
            }
          }
        }

        NetworkView {
          visible: root.networkOpen
          width: parent.width
          network: root.network
          catalog: strings
          foreground: root.bar.foreground
          accent: Commons.Color.accent
          fontFamily: root.bar.fontFamily
          laneIndex: root.laneIndex
          laneByKeyboard: root.laneByKeyboard
          onLaneHovered: function(index) {
            root.laneIndex = index
            root.laneByKeyboard = false
          }
        }

        // No phone: connect to a paired one, or pair a new one.
        Row {
          visible: !root.networkOpen && root.starts.length > 0
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: root.starts

            CursorSurface {
              id: start
              required property var modelData
              required property int index
              readonly property int itemIndex: root.tools.length + index
              width: (parent.width - Style.space(8)) / 2
              implicitHeight: startLabel.implicitHeight + Style.space(18)
              hasCursor: root.isSelected(itemIndex)
              foreground: root.bar.foreground
              fill: root.hoverFill
              bordered: true

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.select(start.itemIndex)
                onClicked: root.activate(start.modelData)
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  text: start.modelData.kind === "connect" ? "󰌘" : "󰐲"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.heading
                }
                Text {
                  id: startLabel
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: start.modelData.kind === "connect" ? strings.t("connect") : strings.t("pair")
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }

        Grid {
          id: grid
          visible: !root.networkOpen
          width: parent.width
          columns: root.columns
          spacing: Style.space(6)

          Repeater {
            model: root.tiles
            Tile {}
          }
        }
      }
    }
  }

  // A tile: the app's icon and name. An open window's tile is filled and
  // marked with a dot. The speaker in the corner says where the window's
  // sound plays, and switches it; an app's other corner takes it off the panel.
  component Tile: CursorSurface {
    id: tile
    required property var modelData
    required property int index

    readonly property string kind: modelData.kind
    readonly property int itemIndex: root.firstTile + index
    readonly property bool isOpen: root.rowIsOpen(modelData)
    readonly property string label: kind === "mirror" ? strings.t("mirror")
      : kind === "all" ? strings.t("allApps")
      : modelData.app.name
    readonly property string glyph: kind === "mirror" ? "󰦉" : kind === "all" ? "󰀻" : "󰀲"
    readonly property string iconPath: kind === "app" ? modelData.app.icon : ""
    readonly property string soundSetting: root.soundOf(modelData)
    readonly property bool hot: tileMouse.containsMouse || hasCursor

    width: (grid.width - grid.spacing * (root.columns - 1)) / root.columns
    implicitHeight: tileColumn.implicitHeight + Style.space(16)
    hasCursor: root.isSelected(itemIndex)
    current: isOpen
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.select(tile.itemIndex)
      onClicked: root.activate(tile.modelData)
    }

    PanelToolTip {
      visible: tileMouse.containsMouse && !badgeMouse.containsMouse && !removeMouse.containsMouse && tileName.truncated
      text: tile.label
      fontFamily: root.bar.fontFamily
    }

    Column {
      id: tileColumn
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(6)

      Item {
        width: parent.width
        height: Style.space(32)

        Text {
          visible: tile.iconPath === "" || appIcon.status === Image.Error
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: tile.glyph
          color: tile.isOpen ? Commons.Color.accent : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
        }

        SizedImage {
          id: appIcon
          visible: tile.iconPath !== "" && status !== Image.Error
          anchors.centerIn: parent
          width: parent.height
          height: parent.height
          url: tile.iconPath !== "" ? Util.fileUrl(tile.iconPath) : ""
        }
      }

      Text {
        id: tileName
        textFormat: Text.PlainText
        text: tile.label
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // An open window.
    Rectangle {
      visible: tile.isOpen
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(3)
      width: Style.space(4)
      height: width
      radius: width / 2
      color: Commons.Color.accent
    }

    // Takes the app off the panel, on the tile under the pointer or cursor.
    Rectangle {
      visible: tile.kind === "app" && tile.hot
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.margins: Style.space(3)
      width: Style.space(18)
      height: width
      radius: Style.cornerRadius
      color: removeMouse.containsMouse ? root.hoverFill : "transparent"

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "󰅙"
        color: removeMouse.containsMouse ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.3)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: removeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.removeApp(tile.modelData)
      }

      PanelToolTip {
        visible: removeMouse.containsMouse
        text: strings.t("removeTip")
        fontFamily: root.bar.fontFamily
      }
    }

    // Where the sound plays: shown on open windows, and on the tile under the
    // pointer or cursor, where it can be switched.
    Rectangle {
      id: badge
      visible: tile.soundSetting !== "" && (tile.isOpen || tile.hot)
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(3)
      width: Style.space(18)
      height: width
      radius: Style.cornerRadius
      color: badgeMouse.containsMouse ? root.hoverFill : "transparent"

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: tile.soundSetting === "pc" ? "󰽟" : "󰥒"
        color: tile.isOpen && tile.soundSetting === "pc" ? Commons.Color.accent : Qt.darker(root.bar.foreground, 1.3)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: badgeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleSound(tile.modelData)
      }

      PanelToolTip {
        visible: badgeMouse.containsMouse
        text: tile.isOpen
          ? (tile.soundSetting === "pc" ? strings.t("soundPcTip") : strings.t("soundPhoneTip"))
          : (tile.soundSetting === "pc" ? strings.t("soundPcNextTip") : strings.t("soundPhoneNextTip"))
        fontFamily: root.bar.fontFamily
      }
    }
  }
}
