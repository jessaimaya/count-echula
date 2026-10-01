-- Disc 1, "Echula theme" (docs/MUSIC_PROMPT.md, take 1): 120 BPM, first beat 0.340 s,
-- 36 bars, C major.
local beatmap = require('lib/beatmap')

local bar = beatmap.bar
local c = beatmap.chart()

-- Candy positions follow the song's onsets (docs/MUSIC_PROMPT.md, rhythm grid):
-- intro, bridge and outro hit hardest on beats 2 and 4 (claps); bars 5-20 and 25-32
-- hit on every beat; real off-beat fills only at bars 16, 17, 28 and 29.
local BEATS_1_3 = { 0, 2 }
local BEATS_2_4 = { 1, 3 }
local EVERY = { 0, 1, 2, 3 }
local NONE: { [number]: { number } } = {}

-- Intro, bars 2-4: learn to swipe after the candy, on the claps. No garlic yet.
beatmap.trail(c, 2, 5, BEATS_2_4, NONE, { 0, 0, -1, -1, 0, 1 }, 1, false, 0)
-- Bars 5-8: the kick arrives; garlic appears (no damage until bar 9).
beatmap.trail(c, 5, 9, BEATS_1_3, NONE, { 1, 1, 0, -1, -1, 0, 1, 0 }, 1, true, 0)
-- Verse, bars 9-12: candy on beats 1 and 3.
beatmap.trail(c, 9, 13, BEATS_1_3, NONE, { -1, -1, 0, 1, 1, 0, -1, 0 }, 1, true, 3)
-- Chorus, bars 13-20: every beat; lane changes every 2 beats; fills where the song has them.
beatmap.trail(c, 13, 21, EVERY, { [16] = { 2.5 }, [17] = { 3.5 } }, { 0, 1, -1, 0, 1, 1, -1, 0 }, 2, true, 4)
-- Bridge, bars 21-24: fog; candy on the claps (2 and 4), a new lane each time.
beatmap.trail(c, 21, 25, BEATS_2_4, NONE, { 1, -1, 0, 1, -1, 0, 1, 0 }, 1, true, 0)
-- Finale, bars 25-32: every beat; the drum fill in bar 28 becomes a candy run.
beatmap.trail(c, 25, 33, EVERY, { [28] = { 2.5, 3.5 }, [29] = { 3.5 } }, { -1, 0, 1, 0, -1, 1, 0, -1 }, 2, true, 4)
-- Outro, bars 33-35: a candy parade on the claps to the castle gate.
beatmap.trail(c, 33, 36, BEATS_2_4, NONE, { 0 }, 1, false, 0)

local map: beatmap.Beatmap = {
    bpm = 120,
    firstBeat = 0.340,
    endBeat = bar(37),
    tutorialEnd = bar(9),
    swipeTutorial = bar(1),
    tapTutorial = bar(5),
    sections = {
        { from = bar(1), name = 'intro' },
        { from = bar(5), name = 'tutorial' },
        { from = bar(9), name = 'verse' },
        { from = bar(13), name = 'chorus' },
        { from = bar(21), name = 'bridge', fog = 1, prompt = 'The fog is rolling in...\nremember the trail!', promptBeats = 8 },
        { from = bar(25), name = 'finale' },
        { from = bar(33), name = 'outro' },
    },
    -- energy jumps measured in docs/MUSIC_PROMPT.md (take 1 analysis)
    bursts = {
        { beat = bar(5), power = 0.6 }, -- the kick comes in
        { beat = bar(13), power = 1.0 }, -- chorus
        { beat = bar(25), power = 1.0 }, -- back from the fog bridge
    },
    -- the intro (until the kick settles) and the bridge have no kick drum
    heartbeats = {
        { from = 0, to = bar(7), every = 1 },
        { from = bar(21), to = bar(25), every = 1 },
    },
    ice = nil,
    -- C major, estimated per half bar and cleaned to C-major triads
    chords = {
        'Em', 'C', 'G', 'Am', 'Em', 'C', 'F', 'C', -- 1-4
        'C', 'C', 'Dm', 'C', 'C', 'C', 'F', 'G', -- 5-8
        'C', 'C', 'F', 'G', 'G', 'G', 'G', 'G', -- 9-12
        'C', 'G', 'F', 'Em', 'C', 'C', 'G', 'G', -- 13-16
        'Em', 'C', 'F', 'G', 'G', 'G', 'G', 'G', -- 17-20
        'C', 'C', 'Dm', 'Dm', 'Am', 'F', 'G', 'Am', -- 21-24
        'C', 'G', 'F', 'C', 'Em', 'C', 'G', 'G', -- 25-28
        'C', 'C', 'F', 'G', 'G', 'G', 'G', 'G', -- 29-32
        'C', 'C', 'F', 'C', 'F', 'C', 'F', 'C', -- 33-36
    },
    events = beatmap.events(c),
}

return map
