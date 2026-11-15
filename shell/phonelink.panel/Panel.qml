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

  readonly property string viaLabel: via === "direct" ? strings.t("viaDirect")
    : via === "usb" ? strings.t("viaUsb")
    : via === "wifi" ? strings.t("viaWifi")
    : via === "tailscale" ? (relayed ? strings.t("viaTailscaleRelayed") : strings.t("viaTailscale"))
    : strings.t("notConnected")

  readonly property string statusLabel: !loaded ? strings.t("checking")
    : reconnecting ? strings.t("reconnecting")
    : viaLabel

  readonly property string tooltip: connected || reconnecting
    ? strings.t("tooltipConnected").arg(deviceName || strings.t("phone")).arg(statusLabel)
    : strings.t("tooltipDisconnected")

  // One flat list drives both the mouse and the keyboard cursor. Groups:
  // 0 the mirror, 1 apps, 2 the connection.
  readonly property var rows: {
    var list = [{ kind: "mirror", group: 0 }]
    for (var i = 0; i < apps.length; i++) list.push({ kind: "app", group: 1, app: apps[i] })
    list.push({ kind: "all", group: 1 })
    // The direct link needs the phone nearby, so it's no use over Tailscale.
    list.push({ kind: "network", group: 2 })
    if (directSupported && via !== "tailscale") list.push({ kind: "direct", group: 2 })
    if (connected) {
      list.push({ kind: "disconnect", group: 2 })
    } else {
      list.push({ kind: "connect", group: 2 })
      list.push({ kind: "pair", group: 2 })
    }
    return list
  }

  property int selectedIndex: 0
  property bool cursorActive: false

  // The network map page, and the data it draws.
  property bool networkOpen: false
  property var network: null
  property int laneIndex: -1

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
    if (row.kind === "mirror") run(["mirror"])
    else if (row.kind === "app") run(["open", row.app.package])
    else if (row.kind === "all") run(["apps"])
    else if (row.kind === "disconnect") run(["stop"])
    else if (row.kind === "connect") run(["connect"])
    else if (row.kind === "pair") run(["pair"])
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
      phone: ph ? { name: clean(ph.name, 48), ssid: clean(ph.ssid, 48), mobile: clean(ph.mobile, 20) } : null,
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

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens on the monitor in focus. One copy of the widget handles the
    // call for all of them, so it hands it to the right one.
    function network(): void {
      var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
      var items = root.copies()
      for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i].screenName === focused && typeof items[i].openNetworkHere === "function") {
          items[i].openNetworkHere()
          return
        }
      }
      root.openNetworkHere()
    }
  }

  function moveCursor(dy) {
    if (!cursorActive) {
      cursorActive = true
      return
    }
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + dy))
  }

  onOpenedChanged: {
    if (!opened) {
      closeNetwork()
      return
    }
    cursorActive = false
    selectedIndex = 0
    refresh(false)
  }

  onRowsChanged: if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)

  // --- status ----------------------------------------------------------------

  function refresh(brief) {
    if (statusProcess.running) return
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
        pinned: !!app.pinned
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
      apps: list
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
    apps = status.apps
    loaded = true
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
    }
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
        } else if (dy !== 0) {
          root.moveCursor(dy)
        }
      }
      onActivateRequested: if (!root.networkOpen && root.cursorActive) root.activate(root.rows[root.selectedIndex])
      onCloseRequested: root.networkOpen ? root.closeNetwork() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m" || t === "M") root.activate({ kind: "mirror" })
        else if (t === "n" || t === "N") root.networkOpen ? root.closeNetwork() : root.openNetwork()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // Hero: phone, its name, and how it's connected.
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, moreButton.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰄜"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.connected ? 1.0 : 0.5
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: moreButton.left
            anchors.rightMargin: Style.space(12)
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
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusLabel.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          PanelActionButton {
            id: moreButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.networkOpen ? "󰁍" : "󰒓"
            tooltipText: root.networkOpen ? strings.t("back") : strings.t("moreOptions")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: {
              if (root.networkOpen) {
                root.closeNetwork()
                return
              }
              root.close()
              Quickshell.execDetached(["omarchy-menu", "summon", "phone"])
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
          onLaneHovered: function(index) { root.laneIndex = index }
        }

        Column {
          visible: !root.networkOpen
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.rows

            Column {
              id: delegateRoot
              required property var modelData
              required property int index
              readonly property bool startsGroup: index === 0 || root.rows[index - 1].group !== modelData.group

              width: parent.width
              spacing: Style.space(10)

              PanelSeparator {
                visible: delegateRoot.startsGroup
                height: visible ? implicitHeight : 0
                foreground: root.bar.foreground
              }

              PanelSectionHeader {
                visible: delegateRoot.startsGroup && delegateRoot.modelData.group === 1
                height: visible ? implicitHeight : 0
                text: strings.t("apps").toUpperCase()
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              PhoneRow {
                width: parent.width
                rowData: delegateRoot.modelData
                rowIndex: delegateRoot.index
              }
            }
          }
        }
      }
    }
  }

  // One panel row: an app icon or glyph, a title and a caption. The Direct
  // Wi-Fi row carries a switch; the row itself owns the click.
  component PhoneRow: CursorSurface {
    id: row
    required property var rowData
    required property int rowIndex

    readonly property string kind: rowData.kind
    readonly property bool isOpen: kind === "mirror" ? root.mirrorOpen
      : kind === "app" ? root.appOpen(rowData.app.package)
      : false

    readonly property string glyph: kind === "mirror" ? "󰍹"
      : kind === "app" ? "󰀲"
      : kind === "all" ? "󰀻"
      : kind === "direct" ? "󰖩"
      : kind === "disconnect" ? "󰅙"
      : kind === "connect" ? "󰌘"
      : kind === "network" ? "󰛳"
      : "󰐲"

    readonly property string iconPath: kind === "app" ? rowData.app.icon : ""

    readonly property string title: kind === "mirror" ? strings.t("mirror")
      : kind === "app" ? rowData.app.name
      : kind === "all" ? strings.t("allApps")
      : kind === "direct" ? strings.t("direct")
      : kind === "disconnect" ? strings.t("disconnect")
      : kind === "connect" ? strings.t("connect")
      : kind === "network" ? strings.t("networkMap")
      : strings.t("pair")

    readonly property string caption: {
      if (kind === "mirror") return isOpen ? strings.t("open") : strings.t("mirrorCaption")
      if (kind === "app") return isOpen ? strings.t("open") : (rowData.app.pinned ? strings.t("pinned") : "")
      if (kind === "all") return strings.t("allAppsCaption")
      if (kind === "direct") return root.directBusy ? strings.t("directBusy") : (root.directUp ? strings.t("directOn") : strings.t("directOff"))
      if (kind === "disconnect") return strings.t("disconnectCaption")
      if (kind === "connect") return strings.t("connectCaption")
      if (kind === "network") return strings.t("networkMapCaption")
      return strings.t("pairCaption")
    }

    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    current: isOpen
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.selectedIndex = row.rowIndex
      }
      onClicked: root.activate(row.rowData)
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(iconBox.height, labels.implicitHeight, toggle.visible ? toggle.implicitHeight : 0)

      Item {
        id: iconBox
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(Style.font.heading * 1.5)
        height: width

        Text {
          visible: row.iconPath === "" || appIcon.status === Image.Error
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: row.glyph
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.heading
        }

        SizedImage {
          id: appIcon
          visible: row.iconPath !== "" && status !== Image.Error
          anchors.fill: parent
          url: row.iconPath !== "" ? Util.fileUrl(row.iconPath) : ""
        }
      }

      Column {
        id: labels
        anchors.left: iconBox.right
        anchors.leftMargin: Style.space(10)
        anchors.right: toggle.visible ? toggle.left : parent.right
        anchors.rightMargin: toggle.visible ? Style.space(10) : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          text: row.title
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          visible: row.caption !== ""
          text: row.caption
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      ToggleSwitch {
        id: toggle
        visible: row.kind === "direct"
        interactive: false
        checked: root.directUp
        busy: root.directBusy
        foreground: root.bar.foreground
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
