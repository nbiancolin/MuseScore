//=============================================================================
//  MuseScore Studio
//  Music Composition & Notation
//
//  Ensure Transposed Pitch Plugin
//
//  Forces the score into transposed (written) pitch view — not concert pitch.
//  Toggles concert pitch a couple of times so the UI refreshes, then leaves
//  the score in transposed pitch if it was still in concert pitch.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation.
//=============================================================================

import QtQuick
import MuseScore 3.0

MuseScore {
    version: "1.0"
    title: "Ensure Transposed Pitch"
    description: "Toggle concert pitch twice to refresh the UI, then ensure the score is not in concert pitch"
    categoryCode: "composing-arranging-tools"
    requiresScore: true

    function inConcertPitch() {
        return !!curScore.style.value("concertPitch")
    }

    onRun: {
        if (!curScore) {
            quit()
            return
        }

        // Cycle concert pitch twice so the status-bar / notation view refresh.
        // An even number of toggles restores the previous mode; then force
        // transposed pitch if we are still in concert pitch.
        cmd("concert-pitch")
        cmd("concert-pitch")

        if (inConcertPitch()) {
            cmd("concert-pitch")
        }

        quit()
    }
}
