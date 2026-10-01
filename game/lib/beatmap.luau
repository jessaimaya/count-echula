-- Beatmap for "Echula theme" (docs/MUSIC_PROMPT.md, take 1): 120 BPM, first beat 0.340 s,
-- 36 bars of 4 beats. Beat 0 = bar 1 beat 1. Bar b starts at beat (b - 1) * 4.
--
-- The level is a CANDY TRAIL on the beat: catching candy fires the sonar, so the
-- pulses land on the music. Where the trail changes lane, garlic waits in the lane
-- being left (not swiping = a hit). Candy sits where the song actually hits (see the
-- rhythm grid in docs/MUSIC_PROMPT.md).

export type Event = {
    beat: number,
    lane: number, -- -1, 0, 1
    kind: 'candy' | 'garlic',
}

export type Section = { from: number, name: string }

-- A color burst when the music changes (sonar.wgsl "burst"). power 0..1.
export type Burst = { beat: number, power: number }

export type Beatmap = {
    bpm: number,
    firstBeat: number,
    endBeat: number,
    tutorialEnd: number, -- no damage and no echo drain before this beat
    swipeTutorial: number, -- beat the swipe prompt starts
    tapTutorial: number, -- beat the ping prompt starts
    sections: { Section },
    bursts: { Burst },
    events: { Event },
}

local function bar(b: number): number
    return (b - 1) * 4
end

local events: { Event } = {}
local lastLane = 0

local function candy(beat: number, lane: number)
    local e: Event = { beat = beat, lane = lane, kind = 'candy' }
    table.insert(events, e)
end

local function garlic(beat: number, lane: number)
    local e: Event = { beat = beat, lane = lane, kind = 'garlic' }
    table.insert(events, e)
end

-- One candy position: `stay` candies are fills that keep the current lane.
type Slot = { beat: number, stay: boolean }

-- Candy on the given beat offsets (0-3.5) of every bar in [fromBar, toBar), plus
-- `fills` (bar -> extra offsets that stay in lane). Lanes cycle through `lanes`,
-- each held for `hold` candies. `hazards`: garlic in the lane left behind on a
-- change, plus (every `extra` candies, 0 = never) garlic in the third lane.
local function trail(fromBar: number, toBar: number, offsets: { number }, fills: { [number]: { number } },
    lanes: { number }, hold: number, hazards: boolean, extra: number)
    local slots: { Slot } = {}
    for b = fromBar, toBar - 1 do
        for _, o in offsets do
            table.insert(slots, { beat = bar(b) + o, stay = false })
        end
        local f = fills[b]
        if f ~= nil then
            for _, o in f do
                table.insert(slots, { beat = bar(b) + o, stay = true })
            end
        end
    end
    table.sort(slots, function(x: Slot, y: Slot): boolean
        return x.beat < y.beat
    end)
    local k = 0
    for _, slot in slots do
        if slot.stay then
            candy(slot.beat, lastLane)
        else
            local lane = lanes[(math.floor(k / hold) % #lanes) + 1]
            candy(slot.beat, lane)
            if hazards then
                if lane ~= lastLane then
                    garlic(slot.beat, lastLane)
                elseif extra > 0 and k % extra == extra - 1 then
                    local third = if lane == 0 then (if k % 2 == 0 then 1 else -1) else -lane
                    garlic(slot.beat, third)
                end
            end
            lastLane = lane
            k += 1
        end
    end
end

-- Candy positions follow the song's onsets (docs/MUSIC_PROMPT.md, rhythm grid):
-- intro, bridge and outro hit hardest on beats 2 and 4 (claps); bars 5-20 and 25-32
-- hit on every beat; real off-beat fills only at bars 16, 17, 28 and 29.
local BEATS_1_3 = { 0, 2 }
local BEATS_2_4 = { 1, 3 }
local EVERY = { 0, 1, 2, 3 }
local NONE: { [number]: { number } } = {}

-- Intro, bars 2-4: learn to swipe after the candy, on the claps. No garlic yet.
trail(2, 5, BEATS_2_4, NONE, { 0, 0, -1, -1, 0, 1 }, 1, false, 0)
-- Bars 5-8: the kick arrives; garlic appears (no damage until bar 9).
trail(5, 9, BEATS_1_3, NONE, { 1, 1, 0, -1, -1, 0, 1, 0 }, 1, true, 0)
-- Verse, bars 9-12: candy on beats 1 and 3.
trail(9, 13, BEATS_1_3, NONE, { -1, -1, 0, 1, 1, 0, -1, 0 }, 1, true, 3)
-- Chorus, bars 13-20: every beat; lane changes every 2 beats; fills where the song has them.
trail(13, 21, EVERY, { [16] = { 2.5 }, [17] = { 3.5 } }, { 0, 1, -1, 0, 1, 1, -1, 0 }, 2, true, 4)
-- Bridge, bars 21-24: fog; candy on the claps (2 and 4), a new lane each time.
trail(21, 25, BEATS_2_4, NONE, { 1, -1, 0, 1, -1, 0, 1, 0 }, 1, true, 0)
-- Finale, bars 25-32: every beat; the drum fill in bar 28 becomes a candy run.
trail(25, 33, EVERY, { [28] = { 2.5, 3.5 }, [29] = { 3.5 } }, { -1, 0, 1, 0, -1, 1, 0, -1 }, 2, true, 4)
-- Outro, bars 33-35: a candy parade on the claps to the castle gate.
trail(33, 36, BEATS_2_4, NONE, { 0 }, 1, false, 0)

table.sort(events, function(a: Event, b: Event): boolean
    if a.beat == b.beat then
        return a.kind < b.kind
    end
    return a.beat < b.beat
end)

local map: Beatmap = {
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
        { from = bar(21), name = 'bridge' },
        { from = bar(25), name = 'finale' },
        { from = bar(33), name = 'outro' },
    },
    -- energy jumps measured in docs/MUSIC_PROMPT.md (take 1 analysis)
    bursts = {
        { beat = bar(5), power = 0.6 }, -- the kick comes in
        { beat = bar(13), power = 1.0 }, -- chorus
        { beat = bar(25), power = 1.0 }, -- back from the fog bridge
    },
    events = events,
}

return map
