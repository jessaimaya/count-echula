-- Disc 2, "Funky counting" (docs/MUSIC_PROMPT.md, disc 2): 120 BPM locked, first beat
-- 0.314 s, 50 bars, D minor. Bar 1 is the spoken count-in; four-on-the-floor kick from
-- bar 2. The band "stops" (one hit, then silence) at bars 9, 16-17, 24, 33 and 40-41,
-- and a beatless breakdown (bars 25-29) drops into the "Cold Moon" freeze until the
-- pickups of bar 29 crack the ice and bar 30 shatters it.
local beatmap = require('lib/beatmap')

local bar = beatmap.bar
local c = beatmap.chart()
local trail = beatmap.trail

local BEATS_1_3 = { 0, 2 }
local EVERY = { 0, 1, 2, 3 }
local NONE: { [number]: { number } } = {}

-- Candy follows the onset grid in docs/MUSIC_PROMPT.md: every beat is a kick; the
-- strong off-beat is the "3-and" (offset 2.5) of every other bar in the choruses.

-- Groove, bars 2-5: learn to swipe on beats 1 and 3. No garlic yet.
trail(c, 2, 6, BEATS_1_3, NONE, { 0, 0, -1, -1, 0, 1, 1, 0 }, 1, false, 0)
-- Bars 6-8: garlic appears (no damage until bar 10).
trail(c, 6, 9, BEATS_1_3, NONE, { 1, 1, 0, -1, -1, 0 }, 1, true, 0)
-- Stop, bar 9: the hit, then the band's "and-four" pickup.
trail(c, 9, 10, { 0 }, { [9] = { 2.5, 3 } }, { 1 }, 1, true, 0)
-- Verse, bars 10-15: beats 1 and 3, a new lane each time.
trail(c, 10, 16, BEATS_1_3, NONE, { -1, -1, 0, 1, 1, 0, -1, 0 }, 1, true, 3)
-- Stop, bars 16-17: the hit, silence, the snare pickup on beat 4.
trail(c, 16, 17, { 0 }, NONE, { 1 }, 1, true, 0)
trail(c, 17, 18, { 3 }, NONE, { 0 }, 1, true, 0)
-- Chorus, bars 18-23: every beat, the "3-and" syncopation as a stay-in-lane fill.
trail(c, 18, 24, EVERY, { [19] = { 2.5 }, [21] = { 2.5 }, [23] = { 2.5 } },
    { 0, 1, -1, 0, 1, 1, -1, 0 }, 2, true, 4)
-- Stop, bar 24: the last hit before the freeze, back to the middle lane.
trail(c, 24, 25, { 0 }, NONE, { 0 }, 1, true, 0)
-- Frozen glide, bars 25-29: frost candy on the chord changes (every 2 beats), one
-- slow lane sweep per bar, no garlic. The bar 29 pickups crack the ice.
trail(c, 25, 26, { 2 }, NONE, { -1 }, 1, false, 0)
trail(c, 26, 29, BEATS_1_3, NONE, { 0, 1, 0 }, 2, false, 0)
trail(c, 29, 30, { 0 }, { [29] = { 2.5, 3 } }, { -1 }, 1, false, 0)
-- Thaw, bars 30-32: the ice shatters; every beat again.
trail(c, 30, 33, EVERY, { [31] = { 2.5 }, [32] = { 3.5 } }, { 0, -1, 1, 0, -1, 1 }, 2, true, 4)
-- Stop, bar 33.
trail(c, 33, 34, BEATS_1_3, NONE, { 0, 1 }, 1, true, 0)
-- Chorus, bars 34-39.
trail(c, 34, 40, EVERY, { [35] = { 2.5 }, [37] = { 2.5 }, [39] = { 2.5 } },
    { -1, 0, 1, 1, 0, -1, -1, 1 }, 2, true, 3)
-- Stop, bars 40-41: the hit and the beat-4 pickup, then a bar of silence.
trail(c, 40, 41, { 0, 3 }, NONE, { 0, 1 }, 1, true, 0)
-- Final chorus, bars 42-48, with the eighth-note pickup into bar 49.
trail(c, 42, 49, EVERY, { [43] = { 2.5 }, [45] = { 2.5 }, [47] = { 2.5 }, [48] = { 3.5 } },
    { 0, 1, -1, 1, 0, -1, 0, 1 }, 2, true, 3)
-- Ending, bars 49-50: the last two hits and the final chord.
trail(c, 49, 50, { 0, 3 }, NONE, { -1, 0 }, 1, true, 0)
trail(c, 50, 51, { 0 }, NONE, { 0 }, 1, false, 0)

local map: beatmap.Beatmap = {
    bpm = 120,
    firstBeat = 0.314,
    endBeat = bar(51),
    tutorialEnd = bar(10),
    swipeTutorial = bar(1),
    tapTutorial = bar(6),
    sections = {
        { from = bar(1), name = 'count-in' },
        { from = bar(2), name = 'groove' },
        { from = bar(10), name = 'verse' },
        { from = bar(18), name = 'chorus' },
        { from = bar(24) + 1, name = 'freeze', prompt = 'Brrr... the night froze.\nGlide with the moon...', promptBeats = 12 },
        { from = bar(30), name = 'thaw' },
        { from = bar(34), name = 'chorus' },
        { from = bar(42), name = 'finale' },
    },
    bursts = {
        { beat = bar(2), power = 0.6 }, -- the groove kicks in
        { beat = bar(18), power = 1.0 }, -- chorus
        { beat = bar(30), power = 1.0 }, -- the ice shatters
        { beat = bar(34), power = 0.8 }, -- chorus
        { beat = bar(42), power = 1.0 }, -- final chorus
        { beat = bar(50), power = 1.0 }, -- the last hit
    },
    -- the breakdown has no drums: a slow heartbeat on the frost candy
    heartbeats = {
        { from = bar(25) + 2, to = bar(29) + 2, every = 2 },
    },
    ice = {
        freeze = bar(24) + 1,
        rampBeats = 5,
        cracks = { bar(29) + 2.5, bar(29) + 3 },
        shatter = bar(30),
    },
    -- D minor: Dm Gm C F Bb Gm A A per 8 bars (chroma per half bar, cleaned; the
    -- breakdown's E is read as Em so every tone has a music-box sample)
    chords = {
        'Dm', 'Dm', 'Dm', 'Dm', 'Gm', 'Gm', 'C', 'C', -- 1-4
        'F', 'F', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A', -- 5-8
        'A', 'A', 'Dm', 'Dm', 'Gm', 'Gm', 'C', 'C', -- 9-12
        'F', 'F', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A', -- 13-16
        'A', 'A', 'Dm', 'Dm', 'Gm', 'Gm', 'C', 'C', -- 17-20
        'F', 'F', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A', -- 21-24
        'A', 'A', 'Dm', 'F', 'C', 'Bb', 'Em', 'Em', -- 25-28
        'Gm', 'A', 'Bb', 'Bb', 'Dm', 'Gm', 'A', 'A', -- 29-32
        'A', 'A', 'Dm', 'Dm', 'Gm', 'Gm', 'C', 'C', -- 33-36
        'F', 'F', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A', -- 37-40
        'A', 'A', 'Dm', 'Dm', 'Gm', 'Gm', 'C', 'C', -- 41-44
        'F', 'F', 'Dm', 'F', 'Gm', 'Gm', 'A', 'A', -- 45-48
        'A', 'A', 'Dm', 'Dm', -- 49-50
    },
    events = beatmap.events(c),
}

return map
