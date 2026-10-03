-- Beatmap format and the chart builder shared by every disc (lib/maps/*).
-- Beat 0 = bar 1 beat 1 of the song. Bar b starts at beat (b - 1) * 4.
--
-- A level is a CANDY TRAIL on the beat: catching candy fires the sonar, so the
-- pulses land on the music. Where the trail changes lane, garlic waits in the lane
-- being left (not swiping = a hit). Candy sits where the song actually hits (see the
-- rhythm grids in docs/MUSIC_PROMPT.md).

export type Event = {
    beat: number,
    lane: number, -- -1, 0, 1
    kind: 'candy' | 'garlic',
}

-- A stretch of the song. `fog` (0..1) thickens the street fog (sonar.wgsl cfg.y);
-- `prompt` shows for `promptBeats` beats from `from`. `speed` multiplies how fast the
-- street scrolls (1 = normal) from this section on, until a later section sets another.
-- It ramps linearly over `ramp` beats (default SPEED_RAMP), so nothing on the street
-- jumps; a long ramp is a continuous acceleration.
export type Section = {
    from: number,
    name: string,
    fog: number?,
    prompt: string?,
    promptBeats: number?,
    speed: number?,
    ramp: number?,
}

-- A color burst when the music changes (sonar.wgsl "burst"). power 0..1.
export type Burst = { beat: number, power: number }

-- Heartbeat SFX on every `every` beats in [from, to): where the song has no kick.
export type Span = { from: number, to: number, every: number }

-- The "Cold Moon" freeze (sonar.wgsl frost): frost creeps in from `freeze` over
-- `rampBeats`, cracks on each beat of `cracks`, shatters on `shatter`.
export type Ice = { freeze: number, rampBeats: number, cracks: { number }, shatter: number }

export type Beatmap = {
    bpm: number,
    firstBeat: number,
    endBeat: number,
    tutorialEnd: number, -- no damage before this beat
    swipeTutorial: number, -- beat the swipe prompt starts
    sonarTutorial: number, -- beat the "candy sends your sonar" prompt starts
    sections: { Section },
    bursts: { Burst },
    heartbeats: { Span },
    ice: Ice?,
    chords: { string }, -- two per bar from bar 1 (lib/harmony.luau), cleaned from the audio
    events: { Event },
}

local M = {}

function M.bar(b: number): number
    return (b - 1) * 4
end

export type Chart = { events: { Event }, lastLane: number }

function M.chart(): Chart
    return { events = {}, lastLane = 0 }
end

function M.candy(c: Chart, beat: number, lane: number)
    local e: Event = { beat = beat, lane = lane, kind = 'candy' }
    table.insert(c.events, e)
end

function M.garlic(c: Chart, beat: number, lane: number)
    local e: Event = { beat = beat, lane = lane, kind = 'garlic' }
    table.insert(c.events, e)
end

-- One candy position: `stay` candies are fills that keep the current lane.
type Slot = { beat: number, stay: boolean }

-- Candy on the given beat offsets (0-3.5) of every bar in [fromBar, toBar), plus
-- `fills` (bar -> extra offsets that stay in lane). Lanes cycle through `lanes`,
-- each held for `hold` candies. `hazards`: garlic in the lane left behind on a
-- change, plus (every `extra` candies, 0 = never) garlic in the third lane.
function M.trail(c: Chart, fromBar: number, toBar: number, offsets: { number }, fills: { [number]: { number } },
    lanes: { number }, hold: number, hazards: boolean, extra: number)
    local slots: { Slot } = {}
    for b = fromBar, toBar - 1 do
        for _, o in offsets do
            table.insert(slots, { beat = M.bar(b) + o, stay = false })
        end
        local f = fills[b]
        if f ~= nil then
            for _, o in f do
                table.insert(slots, { beat = M.bar(b) + o, stay = true })
            end
        end
    end
    table.sort(slots, function(x: Slot, y: Slot): boolean
        return x.beat < y.beat
    end)
    local k = 0
    for _, slot in slots do
        if slot.stay then
            M.candy(c, slot.beat, c.lastLane)
        else
            local lane = lanes[(math.floor(k / hold) % #lanes) + 1]
            M.candy(c, slot.beat, lane)
            if hazards then
                if lane ~= c.lastLane then
                    M.garlic(c, slot.beat, c.lastLane)
                elseif extra > 0 and k % extra == extra - 1 then
                    local third = if lane == 0 then (if k % 2 == 0 then 1 else -1) else -lane
                    M.garlic(c, slot.beat, third)
                end
            end
            c.lastLane = lane
            k += 1
        end
    end
end

-- The chart's events, sorted by beat (candy before garlic on the same beat).
function M.events(c: Chart): { Event }
    table.sort(c.events, function(a: Event, b: Event): boolean
        if a.beat == b.beat then
            return a.kind < b.kind
        end
        return a.beat < b.beat
    end)
    return c.events
end

-- Fog level of `map` at `beat` (the latest section's, 0 when unset).
function M.fogAt(map: Beatmap, beat: number): number
    local fog = 0
    for _, s in map.sections do
        if beat >= s.from then
            fog = s.fog or 0
        end
    end
    return fog
end

M.SPEED_RAMP = 2 -- beats a speed change takes by default

-- Distance the street has scrolled at `beat`, in beats at normal speed: the integral
-- of the sections' speeds, each change ramping linearly over its `ramp`. Things on the
-- street sit at distanceAt(their beat) - distanceAt(now) ahead of the bat. A speed
-- change must not start before the previous one's ramp has finished.
function M.distanceAt(map: Beatmap, beat: number): number
    local dist = 0
    local pos = 0
    local cur = 1
    for _, s in map.sections do
        local sp = s.speed
        if sp ~= nil and sp ~= cur then
            local a = s.from
            if beat <= a then
                break
            end
            local ramp = s.ramp or M.SPEED_RAMP
            dist += (a - pos) * cur
            local t = beat - a
            if t < ramp then
                return dist + cur * t + (sp - cur) * t * t / (2 * ramp)
            end
            dist += ramp * (cur + sp) / 2
            pos = a + ramp
            cur = sp
        end
    end
    return dist + (beat - pos) * cur
end

-- Whether a heartbeat belongs on integer beat `beat`.
function M.heartbeatAt(map: Beatmap, beat: number): boolean
    for _, s in map.heartbeats do
        if beat >= s.from and beat < s.to and (beat - s.from) % s.every == 0 then
            return true
        end
    end
    return false
end

-- Frost look at fractional `beat`: amount 0..1, cracks so far (0..#cracks), and
-- beats since the shatter (negative before it). Frost is 0 again from the shatter.
function M.frostAt(map: Beatmap, beat: number): (number, number, number)
    local ice = map.ice
    if ice == nil then
        return 0, 0, -1
    end
    local since = beat - ice.shatter
    if beat < ice.freeze or since >= 0 then
        return 0, 0, since
    end
    local t = math.clamp((beat - ice.freeze) / ice.rampBeats, 0, 1)
    local amount = t * t * (3 - 2 * t)
    local cracks = 0
    for _, cb in ice.cracks do
        if beat >= cb then
            cracks += 1
        end
    end
    return amount, cracks, since
end

return M
