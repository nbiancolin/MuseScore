//=============================================================================
//  MuseScore Studio
//  Music Composition & Notation
//
//  Implode From JSON Plugin
//
//  Reads a JSON file describing staff ranges, selects each range, runs
//  Tools → Implode, and optionally removes the emptied source staves.
//
//  JSON format (see example.json):
//  {
//    "groups": [
//      {
//        "staves": [2, 3, 4],          // 0-based, contiguous
//        "startTick": 0,               // optional, default 0
//        "endTick": null,              // optional, null = end of score
//        "removeSourceStaves": true    // optional, default true
//      }
//    ]
//  }
//
//  Alternate form for a single group (no "groups" wrapper):
//  { "staves": [0, 1], "removeSourceStaves": true }
//
//  Or use inclusive startStaff / endStaff instead of staves[].
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation.
//=============================================================================

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import MuseScore 3.0
import FileIO 3.0
import Muse.Ui
import Muse.UiComponents

MuseScore {
    version: "1.0"
    title: "Implode From JSON"
    description: "Implode staff groups listed in a JSON file, then optionally remove source staves"
    pluginType: "dialog"
    categoryCode: "composing-arranging-tools"
    requiresScore: true

    width: 520
    height: 220

    property string statusText: ""
    property bool statusIsError: false

    FileIO {
        id: jsonFile
    }

    FileDialog {
        id: openDialog
        title: qsTr("Open implode JSON")
        type: FileDialog.Load
        onAccepted: {
            pathField.text = filePath
            statusText = ""
            statusIsError = false
        }
    }

    function setStatus(message, isError) {
        statusText = message
        statusIsError = !!isError
    }

    function scoreEndTick() {
        var seg = curScore.lastSegment
        if (!seg) {
            return 1
        }
        // endTick is exclusive for selectRange
        return seg.tick + 1
    }

    function normalizeGroup(raw, index) {
        var label = "groups[" + index + "]"
        if (!raw || typeof raw !== "object") {
            throw new Error(label + " must be an object")
        }

        var startStaff
        var endStaffInclusive

        if (raw.staves !== undefined) {
            if (!(raw.staves instanceof Array) || raw.staves.length === 0) {
                throw new Error(label + ".staves must be a non-empty array of 0-based staff indices")
            }
            var sorted = raw.staves.slice().map(function (v) {
                return Number(v)
            }).sort(function (a, b) {
                return a - b
            })
            for (var i = 0; i < sorted.length; i++) {
                if (!isFinite(sorted[i]) || sorted[i] < 0 || sorted[i] !== Math.floor(sorted[i])) {
                    throw new Error(label + ".staves must contain non-negative integers")
                }
                if (i > 0 && sorted[i] !== sorted[i - 1] + 1) {
                    throw new Error(label + ".staves must be a contiguous range (got " + sorted.join(", ") + ")")
                }
            }
            startStaff = sorted[0]
            endStaffInclusive = sorted[sorted.length - 1]
        } else if (raw.startStaff !== undefined && raw.endStaff !== undefined) {
            startStaff = Number(raw.startStaff)
            endStaffInclusive = Number(raw.endStaff)
            if (!isFinite(startStaff) || !isFinite(endStaffInclusive)
                    || startStaff < 0 || endStaffInclusive < startStaff
                    || startStaff !== Math.floor(startStaff)
                    || endStaffInclusive !== Math.floor(endStaffInclusive)) {
                throw new Error(label + " needs valid inclusive startStaff / endStaff")
            }
        } else {
            throw new Error(label + " needs either staves[] or startStaff/endStaff")
        }

        var startTick = (raw.startTick === undefined || raw.startTick === null) ? 0 : Number(raw.startTick)
        var endTick = (raw.endTick === undefined || raw.endTick === null) ? scoreEndTick() : Number(raw.endTick)
        if (!isFinite(startTick) || !isFinite(endTick) || endTick <= startTick) {
            throw new Error(label + " has invalid startTick/endTick")
        }

        var removeSource = (raw.removeSourceStaves === undefined) ? true : !!raw.removeSourceStaves

        return {
            startStaff: startStaff,
            endStaffExclusive: endStaffInclusive + 1,
            startTick: startTick,
            endTick: endTick,
            removeSourceStaves: removeSource
        }
    }

    function parseGroups(data) {
        var list
        if (data.groups instanceof Array) {
            list = data.groups
        } else if (data.staves !== undefined || (data.startStaff !== undefined && data.endStaff !== undefined)) {
            list = [data]
        } else {
            throw new Error("JSON must contain a groups array or a single group object")
        }

        var groups = []
        for (var i = 0; i < list.length; i++) {
            groups.push(normalizeGroup(list[i], i))
        }

        // Highest staves first so removals do not shift later group indices
        groups.sort(function (a, b) {
            return b.startStaff - a.startStaff
        })
        return groups
    }

    function staffAt(index) {
        if (index < 0 || index >= curScore.nstaves) {
            return null
        }
        return curScore.staves[index]
    }

    function implodeGroup(group) {
        if (group.endStaffExclusive > curScore.nstaves) {
            throw new Error("Staff range " + group.startStaff + ".." + (group.endStaffExclusive - 1)
                            + " is outside the score (" + curScore.nstaves + " staves)")
        }

        var toRemove = []
        if (group.removeSourceStaves && group.endStaffExclusive - group.startStaff > 1) {
            for (var s = group.startStaff + 1; s < group.endStaffExclusive; s++) {
                var staff = staffAt(s)
                if (!staff) {
                    throw new Error("Missing staff at index " + s)
                }
                toRemove.push(staff)
            }
        }

        if (!curScore.selection.selectRange(group.startTick, group.endTick,
                                           group.startStaff, group.endStaffExclusive)) {
            throw new Error("Could not select staff range " + group.startStaff
                            + ".." + (group.endStaffExclusive - 1)
                            + " ticks " + group.startTick + ".." + group.endTick)
        }

        cmd("implode")

        if (toRemove.length > 0) {
            curScore.removeStaves(toRemove)
        }
    }

    function runImplode() {
        if (!curScore) {
            setStatus(qsTr("No score is open."), true)
            return
        }

        var path = pathField.text.trim()
        if (!path) {
            setStatus(qsTr("Choose a JSON file first."), true)
            return
        }

        jsonFile.source = path
        if (!jsonFile.exists()) {
            setStatus(qsTr("File not found:\n%1").arg(path), true)
            return
        }

        var text = jsonFile.read()
        if (!text) {
            setStatus(qsTr("Could not read file (empty or unreadable):\n%1").arg(path), true)
            return
        }

        var data
        try {
            data = JSON.parse(text)
        } catch (e) {
            setStatus(qsTr("Invalid JSON: %1").arg(e.toString()), true)
            return
        }

        var groups
        try {
            groups = parseGroups(data)
        } catch (e) {
            setStatus(e.toString(), true)
            return
        }

        if (groups.length === 0) {
            setStatus(qsTr("No groups to implode."), true)
            return
        }

        curScore.startCmd("Implode from JSON")
        try {
            for (var i = 0; i < groups.length; i++) {
                implodeGroup(groups[i])
            }
            curScore.endCmd()
            setStatus(qsTr("Imploded %1 group(s).").arg(groups.length), false)
        } catch (e) {
            curScore.endCmd(true)
            setStatus(e.toString(), true)
        }
    }

    onRun: {
        var pluginDir = jsonFile.pluginDirectoryPath()
        pathField.text = pluginDir + "/example.json"
        openDialog.folder = pluginDir
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        StyledTextLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
            text: qsTr("Select a JSON file that lists contiguous staff groups to implode. See example.json in this plugin folder.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: pathField
                Layout.fillWidth: true
                placeholderText: qsTr("Path to .json file")
            }

            FlatButton {
                text: qsTr("Browse…")
                onClicked: openDialog.open()
            }
        }

        StyledTextLabel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignTop
            color: statusIsError ? ui.theme.accentColor : ui.theme.fontPrimaryColor
            text: statusText
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            FlatButton {
                text: qsTranslate("PrefsDialogBase", "Cancel")
                onClicked: quit()
            }

            FlatButton {
                text: qsTr("Implode")
                accentButton: true
                onClicked: runImplode()
            }
        }
    }
}
