import QtQuick 2.15
import QtQuick.Controls 2.15 as Controls
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import Qt.labs.platform 1.1 as Platform

PlasmoidItem {
    id: root

    // Show the heart in the panel; popup when expanded
    preferredRepresentation: compactRepresentation

    // Heart icon state
    property string iconChar: "\u2665"   // ♥
    property color iconColor: inactiveColor

    property color activeColor: "red"
    property color inactiveColor: "gray"

    // Will be filled from settings_ddnet.cfg
    property var trackedNames: []

    // One entry per tracked player online:
    // { name, serverName, mapName, url }
    property var matchedEntries: []

    // DDNet JSON endpoint
    property string endpointUrl: "https://master1.ddnet.org/ddnet/15/servers.json"

    // Tooltip over the heart
    toolTipMainText: matchedEntries.length > 0
                     ? "Tracked players online"
                     : "DDNet Heart"
    toolTipSubText: matchedEntries.length > 0
                    ? matchedEntries.map(function(e) { return e.name; }).join("\n")
                    : "No tracked players online."

    Component.onCompleted: {
        loadTrackedNames()
        pollTimer.start()
    }

    // Poll every minute: re-read friends, then query DDNet
    Timer {
        id: pollTimer
        interval: 60000    // 1 minute
        repeat: true
        running: false
        onTriggered: loadTrackedNames()
    }

    function loadTrackedNames() {
        // do the master server fetching        
        fetchData()
    }

    // Parse the contents of settings_ddnet.cfg
    // Lines look like:
    //   add_friend "A" "Clan"
    //   add_friend "B" ""
    // We only care about the first quoted string (the player name).
    function parseFriendFile(contents) {
        var result = []
        if (!contents)
            return result

        var lines = contents.split(/\r?\n/)
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim()
            if (line.indexOf("add_friend ") !== 0)
                continue

            // First quoted string after add_friend
            var m = line.match(/add_friend\s+"([^"]*)"/)
            if (m && m[1] !== undefined && m[1].length > 0) {
                result.push(m[1])
            }
        }
        return result
    }

    function setNoMatches(reason) {
        matchedEntries = []
        iconColor = inactiveColor
        if (reason) {
            console.log("DDNetHeart: " + reason)
        }
        // tooltip bound to matchedEntries
    }

    // Build ddnet:// URL from server addresses
    function buildDdnetUrl(addresses) {
        if (!addresses || addresses.length === 0)
            return ""

        var ip = ""
        var port = ""

        // Prefer a tw-0.6+udp entry
        for (var i = 0; i < addresses.length; ++i) {
            var addr = String(addresses[i])
            if (addr.indexOf("tw-0.6+udp://") === 0) {
                var hostPort = addr.split("://")[1] // "IP:PORT"
                var parts = hostPort.split(":")
                if (parts.length === 2) {
                    ip = parts[0]
                    port = parts[1]
                }
                break
            }
        }

        // Fallback: try first entry if we didn't find tw-0.6+udp
        if (!port) {
            var first = String(addresses[0])
            var hp = first.split("://")
            if (hp.length === 2) {
                var hpParts = hp[1].split(":")
                if (hpParts.length === 2) {
                    if (!ip)
                        ip = hpParts[0]
                    port = hpParts[1]
                }
            }
        }

        if (!port)
            return ""

        // Adjust this format if your DDNet client expects something else
        return "ddnet://" + ip + ":" + port
    }

    // Fetch JSON from DDNet master server
    function fetchData() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", endpointUrl)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        handleResponse(data)
                    } catch (e) {
                        setNoMatches("JSON parse error: " + e)
                    }
                } else {
                    setNoMatches("HTTP error: " + xhr.status + " " + xhr.statusText)
                }
            }
        }
        xhr.send()
    }

    // Parse JSON and detect tracked players + their server URLs
    function handleResponse(data) {
        if (!data || !data.servers) {
            setNoMatches("Malformed JSON (no servers)")
            return
        }

        var trackedLower = []
        for (var i = 0; i < trackedNames.length; ++i) {
            if (trackedNames[i])
                trackedLower.push(String(trackedNames[i]).toLowerCase())
        }

        var matchMap = {}   // name -> entry

        for (var s = 0; s < data.servers.length; ++s) {
            var server = data.servers[s]
            if (!server || !server.info || !server.info.clients)
                continue

            var serverName = server.info.name ? String(server.info.name) : "Unknown server"
            var mapName = (server.info.map && server.info.map.name) ? String(server.info.map.name) : "Unknown map"
            var url = buildDdnetUrl(server.addresses)

            var clients = server.info.clients
            for (var c = 0; c < clients.length; ++c) {
                var client = clients[c]
                if (!client || !client.name)
                    continue

                var name = String(client.name)
                var nameLower = name.toLowerCase()

                if (trackedLower.indexOf(nameLower) !== -1) {
                    matchMap[name] = {
                        name: name,
                        serverName: serverName,
                        mapName: mapName,
                        url: url
                    }
                }
            }
        }

        var matches = []
        for (var key in matchMap) {
            if (matchMap.hasOwnProperty(key))
                matches.push(matchMap[key])
        }

        matchedEntries = matches
        iconColor = matches.length > 0 ? activeColor : inactiveColor
        // tooltip bound to matchedEntries
    }

    // Compact representation: the heart in the panel, clickable to open popup
    compactRepresentation: Item {
        id: compactRoot
        anchors.fill: parent

        Text {
            anchors.fill: parent
            anchors.margins: 2

            text: root.iconChar
            color: root.iconColor

            font.pixelSize: Math.min(width, height) * 0.9
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    // Full representation: popup with aligned columns + "Join" button
    fullRepresentation: Item {
        id: fullRoot
        implicitWidth: 320
        implicitHeight: 260

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.2)
            radius: 6
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Text {
                id: statusLabel
                text: matchedEntries.length > 0
                      ? "Tracked players online:"
                      : "No tracked players online."
                font.bold: true
                wrapMode: Text.Wrap
                // Use application palette so it's readable on dark/light themes
                color: Qt.rgba(255, 255, 255, 1)
                Layout.fillWidth: true
            }

            // Header row for the "grid"
            RowLayout {
                id: headerRow
                visible: matchedEntries.length > 0
                Layout.fillWidth: true
                spacing: 8

                Controls.Label {
                    id: playerHeader
                    text: "Player"
                    font.bold: true
                    Layout.fillWidth: true
                    Layout.preferredWidth: implicitWidth
                }

                Controls.Label {
                    id: serverHeader
                    text: "Server"
                    font.bold: true
                    Layout.fillWidth: true
                    Layout.preferredWidth: implicitWidth
                }

                Controls.Label {
                    id: joinHeader
                    text: "Action"
                    font.bold: true
                }
            }

            // One row per matched entry: Player | Server | Join
            Repeater {
                model: matchedEntries

                delegate: RowLayout {
                    id: row
                    Layout.fillWidth: true
                    spacing: 8
                    property var entry: modelData

                    Controls.Label {
                        text: entry.name

                        // Player: higher priority
                        Layout.fillWidth: true
                        Layout.preferredWidth: playerHeader.implicitWidth
                        elide: Text.ElideRight
                    }

                    Controls.Label {
                        text: entry.serverName

                        // Server: still gets some, but less
                        Layout.fillWidth: true
                        Layout.preferredWidth: serverHeader.implicitWidth
                        elide: Text.ElideRight
                    }

                    Controls.Button {
                        text: "Join"
                        onClicked: {
                            if (entry.url && entry.url.length > 0)
                                Qt.openUrlExternally(entry.url)
                            else
                                console.log("No URL for " + entry.name)
                        }
                        Layout.preferredWidth: joinHeader.implicitWidth
                    }
                }
            }

            Item { Layout.fillHeight: true }

             // Bottom row: Refresh (left) and Close (right)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Controls.Button {
                    text: "Refresh"
                    onClicked: loadTrackedNames()
                }

                // Flexible spacer to push Close to the right
                Item {
                    Layout.fillWidth: true
                }

                Controls.Button {
                    text: "Close"
                    onClicked: root.expanded = false
                }
            }
        }
    }
}
