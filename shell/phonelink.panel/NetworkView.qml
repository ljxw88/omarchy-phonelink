import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// The network map: every way this computer has to the phone, drawn as lanes
// between the two, with the addresses at both ends and where they came from.
// Video travels from the phone to this computer, so traffic on the lane in
// use flows right to left.
Column {
  id: view

  required property var network
  required property QtObject catalog
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  // The lane the keyboard or mouse is on; -1 shows the one in use.
  property int laneIndex: -1
  signal laneHovered(int index)

  spacing: Style.space(12)

  readonly property var paths: network && network.paths ? network.paths : []
  readonly property var computer: network && network.computer ? network.computer : ({})
  readonly property var phone: network && network.phone ? network.phone : null
  readonly property var streams: network && network.windows ? network.windows : []
  readonly property color dim: Qt.darker(foreground, 1.5)

  readonly property int busyLane: {
    var best = -1
    for (var i = 0; i < paths.length; i++) {
      if (paths[i].state === "active") return i
      if (best < 0 && paths[i].state === "connected") best = i
    }
    return best
  }
  readonly property int shownLane: laneIndex >= 0 ? laneIndex : busyLane

  // One shared clock for the traffic on the lane in use.
  property real phase: 0
  readonly property bool flowing: visible && busyLane >= 0 && paths[busyLane].state === "active" && Style.duration(1000) > 0
  NumberAnimation on phase {
    from: 0
    to: 1
    loops: Animation.Infinite
    duration: Style.duration(1600)
    running: view.flowing
  }

  function pathName(kind) {
    return kind === "usb" ? catalog.t("pathUsb")
      : kind === "direct" ? catalog.t("pathDirect")
      : kind === "wifi" ? catalog.t("pathWifi")
      : catalog.t("pathTailscale")
  }

  function stateText(path) {
    var text = path.state === "active" ? catalog.t("stateActive")
      : path.state === "connected" ? catalog.t("stateConnected")
      : path.state === "available" ? catalog.t("stateAvailable")
      : path.state === "unsupported" ? catalog.t("stateUnsupported")
      : catalog.t("stateOff")
    var link = path.link
    if (link) {
      text += " · " + catalog.t("rtt").arg(Commons.I18n.formatNumber(link.rttMs, 0))
      if (link.mbps !== null) text += " · " + catalog.t("rate").arg(Commons.I18n.formatNumber(link.mbps, 1))
      if (link.queueMs > 20) text += " · " + catalog.t("backlog").arg(Commons.I18n.formatNumber(link.queueMs, 0))
    }
    return text
  }

  // Where the addresses on a lane came from, in a sentence or three.
  function whereText(path) {
    var parts = []
    if (path.kind === "usb") {
      parts.push(path.state === "off" ? catalog.t("whereUsbOff") : catalog.t("whereUsb"))
    } else if (path.kind === "direct") {
      if (path.state === "unsupported") parts.push(catalog.t("whereDirectUnsupported"))
      else if (!path.phone) parts.push(catalog.t("whereDirectOff"))
      else {
        parts.push(catalog.t("whereDirect").arg(path.computer || catalog.t("thisComputer")))
        if (path.otherChannel) parts.push(catalog.t("whereDirectChannel"))
      }
    } else if (path.kind === "wifi") {
      if (!path.phone) parts.push(catalog.t("whereWifiOff"))
      else {
        parts.push(catalog.t("whereWifi").arg(network.router ? network.router.ip : catalog.t("yourRouter")))
        if (path.found === "mdns") parts.push(catalog.t("whereWifiMdns"))
        else if (path.found === "tcpip") parts.push(catalog.t("whereWifiTcpip"))
        else if (path.found === "phone") parts.push(catalog.t("whereWifiPhone"))
      }
    } else {
      if (!path.phone) parts.push(catalog.t("whereTailscaleOff"))
      else {
        parts.push(catalog.t("whereTailscale"))
        if (path.found === "learned") parts.push(catalog.t("whereTailscaleLearned"))
        else if (path.found === "setting") parts.push(catalog.t("whereTailscaleSetting"))
        else if (path.found === "only-android") parts.push(catalog.t("whereTailscaleOnly"))
        var peer = path.peer
        if (peer && peer.online === false) parts.push(catalog.t("tailscaleOffline"))
        else if (peer && peer.direct) parts.push(catalog.t("tailscaleDirect").arg(peer.direct))
        else if (peer && peer.active && peer.relay) parts.push(catalog.t("tailscaleRelayed").arg(peer.relay))
      }
    }
    return parts.join(" ")
  }

  // The node in the middle of a lane, if it passes through one.
  function middleText(path) {
    if (path.kind === "wifi" && network.router) return catalog.t("router").arg(network.router.ip)
    if (path.kind === "tailscale" && path.peer) {
      if (path.peer.direct) return catalog.t("tailscaleDirectShort")
      if (path.peer.active && path.peer.relay) return catalog.t("tailscaleRelayShort").arg(path.peer.relay)
    }
    return ""
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: view.foreground
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component Caption: Label {
    color: view.dim
    font.pixelSize: Style.font.caption
  }

  // The two ends: this computer on the left, the phone on the right.
  Item {
    width: view.width
    implicitHeight: Math.max(leftEnd.implicitHeight, rightEnd.implicitHeight)

    Column {
      id: leftEnd
      anchors.left: parent.left
      width: parent.width / 2 - Style.space(8)
      spacing: Style.space(1)
      Caption { text: view.catalog.t("thisComputer").toUpperCase(); font.bold: true; font.letterSpacing: 1.2; width: parent.width }
      Label { text: view.computer.name || ""; font.bold: true; width: parent.width }
      Caption { text: view.computer.ssid || ""; visible: text !== ""; width: parent.width }
    }

    Column {
      id: rightEnd
      anchors.right: parent.right
      width: parent.width / 2 - Style.space(8)
      spacing: Style.space(1)
      Caption { text: view.catalog.t("phone").toUpperCase(); font.bold: true; font.letterSpacing: 1.2; width: parent.width; horizontalAlignment: Text.AlignRight }
      Label { text: view.phone ? view.phone.name : view.catalog.t("notReachable"); font.bold: true; width: parent.width; horizontalAlignment: Text.AlignRight }
      Caption { text: view.phone && view.phone.ssid ? view.phone.ssid : ""; visible: text !== ""; width: parent.width; horizontalAlignment: Text.AlignRight }
    }
  }

  Repeater {
    model: view.paths

    CursorSurface {
      id: lane
      required property var modelData
      required property int index
      readonly property bool live: modelData.state === "active"
      readonly property bool linked: live || modelData.state === "connected"
      readonly property bool possible: linked || modelData.state === "available"
      readonly property bool expanded: view.shownLane === index
      readonly property color wireColor: live ? view.accent : view.foreground
      readonly property string middle: view.middleText(modelData)

      width: view.width
      implicitHeight: laneContent.implicitHeight + Style.space(12)
      hasCursor: view.laneIndex === index
      current: live
      foreground: view.foreground
      opacity: possible ? 1 : 0.55

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: if (containsMouse) view.laneHovered(lane.index)
      }

      Column {
        id: laneContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(4)

        Item {
          width: parent.width
          implicitHeight: Math.max(name.implicitHeight, status.implicitHeight)
          Label {
            id: name
            text: view.pathName(lane.modelData.kind)
            font.bold: lane.live
            color: lane.live ? view.accent : view.foreground
          }
          Caption {
            id: status
            anchors.right: parent.right
            anchors.left: name.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: name.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: view.stateText(lane.modelData)
          }
        }

        // The wire between the two ends.
        Item {
          id: wire
          width: parent.width
          height: Style.space(14)
          readonly property real dot: Style.space(8)
          readonly property real start: dot
          readonly property real length: width - 2 * dot

          Rectangle {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: wire.dot
            height: wire.dot
            radius: width / 2
            color: lane.possible ? lane.wireColor : "transparent"
            border.width: 1
            border.color: lane.wireColor
          }
          Rectangle {
            x: wire.width - wire.dot
            anchors.verticalCenter: parent.verticalCenter
            width: wire.dot
            height: wire.dot
            radius: width / 2
            color: lane.possible ? lane.wireColor : "transparent"
            border.width: 1
            border.color: lane.wireColor
          }

          // Solid while connected, dashed while only possible.
          Rectangle {
            visible: lane.linked
            x: wire.start
            width: wire.length
            anchors.verticalCenter: parent.verticalCenter
            height: lane.live ? 2 : 1
            color: lane.wireColor
            opacity: lane.live ? 1 : 0.7
          }
          Repeater {
            model: lane.modelData.state === "available" ? Math.max(0, Math.floor(wire.length / Style.space(8))) : 0
            Rectangle {
              required property int index
              x: wire.start + index * Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(4)
              height: 1
              color: view.foreground
              opacity: 0.5
            }
          }

          // Traffic on the lane in use, from the phone to this computer.
          Repeater {
            model: lane.live && view.flowing ? 3 : 0
            Rectangle {
              required property int index
              readonly property real t: (view.phase + index / 3) % 1
              width: Style.space(5)
              height: width
              radius: width / 2
              color: view.accent
              x: wire.start + (1 - t) * (wire.length - width)
              anchors.verticalCenter: parent.verticalCenter
              opacity: Math.min(1, Math.min(t, 1 - t) * 6)
            }
          }

          // A node the lane passes through: the router, or Tailscale's path.
          Rectangle {
            visible: lane.middle !== ""
            anchors.centerIn: parent
            width: middleText.implicitWidth + Style.space(12)
            height: middleText.implicitHeight + Style.space(4)
            radius: Style.cornerRadius
            color: Commons.Color.popups.background
            border.width: 1
            border.color: lane.wireColor
            Caption {
              id: middleText
              anchors.centerIn: parent
              text: lane.middle
              color: lane.live ? view.accent : view.foreground
            }
          }
        }

        // The addresses at both ends.
        Item {
          visible: leftAddress.text !== "" || rightAddress.text !== ""
          width: parent.width
          implicitHeight: Math.max(leftAddress.implicitHeight, rightAddress.implicitHeight)
          Caption {
            id: leftAddress
            width: parent.width / 2 - Style.space(4)
            text: lane.modelData.computer || ""
            color: lane.linked ? view.foreground : view.dim
          }
          Caption {
            id: rightAddress
            anchors.right: parent.right
            width: parent.width / 2 - Style.space(4)
            horizontalAlignment: Text.AlignRight
            text: lane.modelData.phone || ""
            color: lane.linked ? view.foreground : view.dim
          }
        }

        Caption {
          visible: lane.expanded
          width: parent.width
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          text: view.whereText(lane.modelData)
        }
      }
    }
  }

  PanelSeparator {
    foreground: view.foreground
  }

  // The rest of the picture: the router, the debugging port, the phone's
  // mobile data, and what's streaming.
  Column {
    width: view.width
    spacing: Style.space(3)

    Caption {
      width: parent.width
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      visible: view.network && view.network.router
      text: !view.network || !view.network.router ? ""
        : view.catalog.t("routerLine").arg(view.network.router.ip)
          + (view.network.router.sameAccessPoint === false ? " · " + view.catalog.t("differentAp") : "")
    }
    Caption {
      width: parent.width
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      visible: text !== ""
      text: !view.network || !view.network.port || !view.network.port.found ? ""
        : view.network.port.found === "mdns" ? view.catalog.t("portMdns")
        : view.network.port.found === "tcpip" ? view.catalog.t("portTcpip")
        : view.catalog.t("portRemembered")
    }
    Caption {
      width: parent.width
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      visible: !!(view.phone && view.phone.mobile)
      text: view.phone && view.phone.mobile ? view.catalog.t("mobileData").arg(view.phone.mobile) : ""
    }

    Item { width: 1; height: Style.space(6); visible: view.streams.length > 0 }

    PanelSectionHeader {
      visible: view.streams.length > 0
      text: view.catalog.t("streams").toUpperCase()
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Repeater {
      model: view.streams
      Label {
        required property var modelData
        width: view.width
        font.pixelSize: Style.font.bodySmall
        text: modelData.sound
          ? view.catalog.t("streamSound").arg(view.pathName(modelData.path))
          : view.catalog.t("streamLine").arg(modelData.title).arg(view.pathName(modelData.path)).arg(modelData.bitRate).arg(modelData.codec.toUpperCase())
      }
    }
  }
}
