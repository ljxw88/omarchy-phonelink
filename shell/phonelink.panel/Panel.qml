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
    : strings.t("notConnected")

  readonly property string statusLabel: !loaded ? strings.t("checking") : viaLabel

  readonly property string tooltip: connected
    ? strings.t("tooltipConnected").arg(deviceName || strings.t("phone")).arg(viaLabel)
    : strings.t("tooltipDisconnected")

  // One flat list drives both the mouse and the keyboard cursor. Groups:
  // 0 the mirror, 1 apps, 2 the connection.
  readonly property var rows: {
    var list = [{ kind: "mirror", group: 0 }]
    for (var i = 0; i < apps.length; i++) list.push({ kind: "app", group: 1, app: apps[i] })
    list.push({ kind: "all", group: 1 })
    if (directSupported) list.push({ kind: "direct", group: 2 })
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

  function moveCursor(dy) {
    if (!cursorActive) {
      cursorActive = true
      return
    }
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + dy))
  }

  onOpenedChanged: {
    if (!opened) return
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
      via: ["direct", "wifi", "usb"].indexOf(data.via) >= 0 ? data.via : "none",
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activate(root.rows[root.selectedIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "m" || t === "M") root.activate({ kind: "mirror" }) }

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
              text: root.deviceName || strings.t("phone")
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
            iconText: "󰒓"
            tooltipText: strings.t("moreOptions")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: {
              root.close()
              Quickshell.execDetached(["omarchy-menu", "summon", "phone"])
            }
          }
        }

        Column {
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
      : "󰐲"

    readonly property string iconPath: kind === "app" ? rowData.app.icon : ""

    readonly property string title: kind === "mirror" ? strings.t("mirror")
      : kind === "app" ? rowData.app.name
      : kind === "all" ? strings.t("allApps")
      : kind === "direct" ? strings.t("direct")
      : kind === "disconnect" ? strings.t("disconnect")
      : kind === "connect" ? strings.t("connect")
      : strings.t("pair")

    readonly property string caption: {
      if (kind === "mirror") return isOpen ? strings.t("open") : strings.t("mirrorCaption")
      if (kind === "app") return isOpen ? strings.t("open") : (rowData.app.pinned ? strings.t("pinned") : "")
      if (kind === "all") return strings.t("allAppsCaption")
      if (kind === "direct") return root.directBusy ? strings.t("directBusy") : (root.directUp ? strings.t("directOn") : strings.t("directOff"))
      if (kind === "disconnect") return strings.t("disconnectCaption")
      if (kind === "connect") return strings.t("connectCaption")
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
