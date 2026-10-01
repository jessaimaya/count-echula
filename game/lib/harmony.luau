-- Harmony for musical candy catches. Each disc's beatmap lists its chords, two per
-- bar (estimated from the audio, docs/MUSIC_PROMPT.md). Each catch plays a music-box
-- note from the current chord; the streak walks the arpeggio up and down (ping-pong)
-- so a run of catches sounds like a melody.
local beatmap = require('lib/beatmap')

local M = {}

local ROOTS: { [string]: number } = {
    C = 0, ['C#'] = 1, Db = 1, D = 2, Eb = 3, E = 4, F = 5,
    ['F#'] = 6, Gb = 6, G = 7, Ab = 8, A = 9, Bb = 10, B = 11,
}

M.LOW = 72 -- C5
M.HIGH = 96 -- C7

-- Available samples (assets/audio/notes/note_<midi>.wav): C major from C5 to C7, plus
-- C# and Bb for the D minor disc.
M.NOTES = { 72, 73, 74, 76, 77, 79, 81, 82, 83, 84, 85, 86, 88, 89, 91, 93, 94, 95, 96 }

-- Pitch classes of a major ("C", "Bb") or minor ("Dm") triad.
function M.pitchClasses(chord: string): { number }
    local minor = chord:sub(-1) == 'm'
    local name = if minor then chord:sub(1, -2) else chord
    local root = ROOTS[name] or 0
    local third = if minor then 3 else 4
    return { root, (root + third) % 12, (root + 7) % 12 }
end

function M.chordAt(map: beatmap.Beatmap, beat: number): string
    local i = math.floor(math.max(0, beat) / 2) + 1
    return map.chords[math.min(i, #map.chords)] or 'C'
end

-- Chord tones between LOW and HIGH, ascending.
function M.arpeggio(chord: string): { number }
    local pcs = M.pitchClasses(chord)
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
function M.noteFor(map: beatmap.Beatmap, beat: number, step: number): number
    local arp = M.arpeggio(M.chordAt(map, beat))
    local n = #arp
    local period = 2 * (n - 1)
    local k = (math.max(1, step) - 1) % period
    local i = if k < n then k + 1 else period - k + 1
    return arp[i]
end

-- The next chord tone above `note` (for the PERFECT harmony), or the note itself at the top.
function M.above(map: beatmap.Beatmap, beat: number, note: number): number
    for _, m in M.arpeggio(M.chordAt(map, beat)) do
        if m > note then
            return m
        end
    end
    return note
end

return M
