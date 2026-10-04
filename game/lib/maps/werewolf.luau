-- Disc 3, "Werewolf Wipeout" (docs/MUSIC_PROMPT.md, disc 3): monster surf-rock,
-- 115.396 BPM locked, first beat 0.311 s, 41 bars, D minor. Bar 1 is the wolf howl
-- (no beat), bars 2-3 the surf riff without drums; kick on every beat from bar 4.
-- The band stops at bar 24 beat 1 and leaves almost two bars of silence (the
-- "blackout"); the guitar comes back on bar 26 beat 3, quarters in bar 27, and the
-- groove runs from bar 29 to the last hit on bar 41 beat 1.
-- The hardest disc: after the blackout the street lifts to x1.2 and then keeps
-- accelerating, a little every beat, up to x1.6 on the last hit. The music keeps its
-- tempo; only the scroll (reaction time) changes.
local beatmap = require('lib/beatmap')

local bar = beatmap.bar
local c = beatmap.chart()
local trail = beatmap.trail

local BEATS_1_3 = { 0, 2 }
local EVERY = { 0, 1, 2, 3 }
local NONE: { [number]: { number } } = {}

-- Candy follows the onset grid in docs/MUSIC_PROMPT.md: the surf guitar hits every
-- eighth, the kick every beat, so candy sits on the beats and the eighth fills ride
-- the riff's pickups.

-- Riff, bars 2-3 (no drums yet, a heartbeat keeps time): learn to swipe. No garlic.
trail(c, 2, 4, BEATS_1_3, NONE, { 0, -1, 0, 1 }, 1, false, 0)
-- Bars 4-7: the kick comes in; garlic appears.
trail(c, 4, 8, BEATS_1_3, NONE, { 1, 0, -1, -1, 0, 1, 1, 0 }, 1, true, 0)
-- Verse, bars 8-11: every beat, a lane change every two candies.
trail(c, 8, 12, EVERY, NONE, { -1, 0, 1, 0, -1, -1, 1, 0 }, 2, true, 4)
-- Bars 12-17: the off-beats push harder than the downbeats in bars 13 and 15.
trail(c, 12, 18, EVERY, { [13] = { 1.5 }, [15] = { 3.5 }, [17] = { 3.5 } },
    { 0, 1, -1, 0, 1, 0, -1, 1 }, 2, true, 3)
-- Stops, bars 18-19: hits on 1 and 3, then four hits in a row.
trail(c, 18, 19, BEATS_1_3, NONE, { 0, -1 }, 1, true, 0)
trail(c, 19, 20, EVERY, NONE, { -1, 0, 1, 0 }, 1, true, 0)
-- Bars 20-23: full speed, a pickup into every bar.
trail(c, 20, 24, EVERY, { [20] = { 3.5 }, [21] = { 3.5 }, [22] = { 3.5 } },
    { 1, -1, 0, 1, -1, 0, 1, 0 }, 2, true, 3)
-- Blackout, bars 24-26: the band's last hit, then silence. Candy on the heartbeat
-- every two beats, one slow sweep, no garlic.
trail(c, 24, 25, { 0 }, NONE, { 0 }, 1, true, 0)
trail(c, 24, 25, { 2 }, NONE, { -1 }, 1, false, 0)
trail(c, 25, 26, BEATS_1_3, NONE, { 0, 1 }, 1, false, 0)
trail(c, 26, 27, { 0 }, NONE, { 0 }, 1, false, 0)
-- The guitar storms back on bar 26 beat 3; quarters in bar 27, a stop on bar 28's "3-and".
trail(c, 26, 27, { 2, 3 }, { [26] = { 3.5 } }, { -1, 1 }, 1, true, 0)
trail(c, 27, 29, EVERY, NONE, { 0, -1, 0, 1, 1, 0, -1, 0 }, 1, true, 0)
-- Groove, bars 29-36: every beat, a pickup into every other bar.
trail(c, 29, 37, EVERY, { [30] = { 3.5 }, [32] = { 3.5 }, [34] = { 3.5 }, [36] = { 3.5 } },
    { 0, 1, -1, 1, 0, -1, 0, 1 }, 2, true, 3)
-- Wipeout, bars 37-40: eighth-note runs on the "2-and" and "4-and" of every bar.
trail(c, 37, 41, EVERY, { [37] = { 1.5, 3.5 }, [38] = { 1.5, 3.5 }, [39] = { 1.5, 3.5 }, [40] = { 1.5, 3.5 } },
    { -1, 0, 1, 0, -1, 1, 0, -1 }, 2, true, 3)
-- The last hit, bar 41.
trail(c, 41, 42, { 0 }, NONE, { 0 }, 1, false, 0)

local map: beatmap.Beatmap = {
    bpm = 115.396,
    firstBeat = 0.311,
    endBeat = bar(41) + 2, -- the last hit rings out to the end of the file (84.9 s)
    sections = {
        { from = bar(1), name = 'howl' },
        { from = bar(2), name = 'riff' },
        { from = bar(4), name = 'groove' },
        { from = bar(8), name = 'verse' },
        { from = bar(12), name = 'chase' },
        { from = bar(20), name = 'full speed' },
        { from = bar(24) + 1, name = 'blackout', fog = 1 },
        { from = bar(26) + 2, name = 'storm back', speed = 1.2 },
        { from = bar(27), name = 'accelerate', speed = 1.6, ramp = bar(41) - bar(27) },
        { from = bar(29), name = 'groove' },
        { from = bar(37), name = 'wipeout' },
    },
    bursts = {
        { beat = bar(4), power = 0.6 }, -- the drums kick in
        { beat = bar(20), power = 0.8 }, -- full speed
        { beat = bar(26) + 2, power = 1.0 }, -- back from the blackout
        { beat = bar(29), power = 0.8 }, -- groove
        { beat = bar(37), power = 1.0 }, -- the wipeout run
        { beat = bar(41), power = 1.0 }, -- the last hit
    },
    -- no kick in the howl and the riff, and nothing at all in the blackout
    heartbeats = {
        { from = 0, to = bar(4), every = 1 },
        { from = bar(24) + 1, to = bar(26) + 2, every = 1 },
    },
    ice = nil,
    -- D minor: Dm F | Bb Am per two bars in the verse (chroma per half bar, cleaned;
    -- the blackout's noise reads as Dm)
    chords = {
        'Dm', 'Gm', 'Dm', 'Dm', 'Dm', 'Am', 'Dm', 'F', -- 1-4
        'Bb', 'Am', 'Dm', 'Dm', 'Bb', 'Am', 'Dm', 'Dm', -- 5-8
        'Bb', 'Am', 'Dm', 'Dm', 'Bb', 'Am', 'Dm', 'Am', -- 9-12
        'Dm', 'F', 'Dm', 'Am', 'Dm', 'Am', 'Dm', 'Am', -- 13-16
        'Dm', 'F', 'Dm', 'Dm', 'Em', 'F', 'Dm', 'Dm', -- 17-20
        'Dm', 'Dm', 'G', 'Dm', 'Em', 'Dm', 'Dm', 'Dm', -- 21-24
        'Dm', 'Dm', 'Dm', 'Dm', 'F', 'F', 'F', 'F', -- 25-28
        'Dm', 'Dm', 'F', 'Dm', 'Dm', 'Dm', 'Dm', 'F', -- 29-32
        'Dm', 'Dm', 'Bb', 'F', 'Am', 'Dm', 'Bb', 'Am', -- 33-36
        'Dm', 'Dm', 'Bb', 'F', 'Dm', 'Dm', 'Bb', 'F', -- 37-40
        'Dm', -- 41
    },
    events = beatmap.events(c),
}

return map
