-- Harmony of "Echula theme" for musical candy catches.
-- The song is in C major (chroma analysis, docs/MUSIC_PROMPT.md). One chord per half
-- bar (2 beats), estimated from the audio and cleaned to C-major triads.
-- Each catch plays a music-box note from the current chord; the streak walks the
-- arpeggio up and down (ping-pong) so a run of catches sounds like a melody.

local M = {}

-- pitch classes per chord
local CHORDS: { [string]: { number } } = {
    C = { 0, 4, 7 },
    Dm = { 2, 5, 9 },
    Em = { 4, 7, 11 },
    F = { 5, 9, 0 },
    G = { 7, 11, 2 },
    Am = { 9, 0, 4 },
}

-- bars 1-36, two chords per bar
local PROGRESSION = {
    'Em', 'C', 'G', 'Am', 'Em', 'C', 'F', 'C', -- 1-4
    'C', 'C', 'Dm', 'C', 'C', 'C', 'F', 'G', -- 5-8
    'C', 'C', 'F', 'G', 'G', 'G', 'G', 'G', -- 9-12
    'C', 'G', 'F', 'Em', 'C', 'C', 'G', 'G', -- 13-16
    'Em', 'C', 'F', 'G', 'G', 'G', 'G', 'G', -- 17-20
    'C', 'C', 'Dm', 'Dm', 'Am', 'F', 'G', 'Am', -- 21-24
    'C', 'G', 'F', 'C', 'Em', 'C', 'G', 'G', -- 25-28
    'C', 'C', 'F', 'G', 'G', 'G', 'G', 'G', -- 29-32
    'C', 'C', 'F', 'C', 'F', 'C', 'F', 'C', -- 33-36
}

M.LOW = 72 -- C5
M.HIGH = 96 -- C7

-- Available samples: the C major scale from C5 to C7 (assets/audio/notes/note_<midi>.wav).
M.NOTES = { 72, 74, 76, 77, 79, 81, 83, 84, 86, 88, 89, 91, 93, 95, 96 }

function M.chordAt(beat: number): string
    local i = math.floor(math.max(0, beat) / 2) + 1
    return PROGRESSION[math.min(i, #PROGRESSION)]
end

-- Chord tones between LOW and HIGH, ascending.
function M.arpeggio(chord: string): { number }
    local pcs = CHORDS[chord] or CHORDS.C
    local out: { number } = {}
    for m = M.LOW, M.HIGH do
        for _, pc in pcs do
            if m % 12 == pc then
                table.insert(out, m)
            end
        end
    end
    return out
end

-- Note for the `step`-th candy of a streak (1-based) caught at `beat`.
function M.noteFor(beat: number, step: number): number
    local arp = M.arpeggio(M.chordAt(beat))
    local n = #arp
    local period = 2 * (n - 1)
    local k = (math.max(1, step) - 1) % period
    local i = if k < n then k + 1 else period - k + 1
    return arp[i]
end

-- The next chord tone above `note` (for the PERFECT harmony), or the note itself at the top.
function M.above(beat: number, note: number): number
    for _, m in M.arpeggio(M.chordAt(beat)) do
        if m > note then
            return m
        end
    end
    return note
end

return M
