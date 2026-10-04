-- The finale: after the last candy the street slows to a stop with the castle gate
-- ahead, Echula flies in through the arch, the portcullis drops behind him, then the
-- results. Pure functions, unit tested. Distances are in beats at normal speed
-- (beatmap.distanceAt), times in beats.
local beatmap = require('lib/beatmap')

local M = {}

M.EASE = 1 -- the street eases to a stop over about this much distance
M.GAP = 3.5 -- where it stops, the gate is this far ahead of the bat
M.FLY_FROM = 1 -- beats after the last candy he leaves for the gate
M.FLY_BEATS = 1.5
M.DOOR_FROM = 2.75 -- beats after the last candy the portcullis starts to fall
M.DOOR_BEATS = 0.5 -- its fall
M.BOUNCE_BEATS = 0.3 -- and its bounce when it lands
M.BOUNCE = 0.06 -- how high it bounces, a fraction of its drop
M.RESULTS = 4.5 -- beats after the last candy the results show (not before the song ends)

export type Plan = {
    stop: number, -- distance the street stops at
    gate: number, -- distance of the gate (the castle's front)
    flyFrom: number,
    doorFrom: number,
    slam: number, -- beat the portcullis lands
    results: number,
}

function M.plan(map: beatmap.Beatmap): Plan
    local last = 0
    for _, e in map.events do
        last = math.max(last, e.beat)
    end
    -- the ease starts a quarter beat after the last candy is passed
    local stop = beatmap.distanceAt(map, last + 0.25) + M.EASE
    return {
        stop = stop,
        gate = stop + M.GAP,
        flyFrom = last + M.FLY_FROM,
        doorFrom = last + M.DOOR_FROM,
        slam = last + M.DOOR_FROM + M.DOOR_BEATS,
        results = math.max(map.endBeat, last + M.RESULTS),
    }
end

-- Distance the street has scrolled at `beat`: beatmap.distanceAt until the ease,
-- then it closes in on `stop` exponentially (same position and speed where it starts).
function M.street(map: beatmap.Beatmap, plan: Plan, beat: number): number
    local d = beatmap.distanceAt(map, beat)
    local from = plan.stop - M.EASE
    if d <= from then
        return d
    end
    return plan.stop - M.EASE * math.exp(-(d - from) / M.EASE)
end

-- Echula's flight into the gate: 0 in his lane, 1 through the arch (eased).
function M.fly(plan: Plan, beat: number): number
    local t = math.clamp((beat - plan.flyFrom) / M.FLY_BEATS, 0, 1)
    return t * t * (3 - 2 * t)
end

-- The portcullis: 0 raised, 1 shut. It falls like a weight and bounces once.
function M.door(plan: Plan, beat: number): number
    if beat < plan.doorFrom then
        return 0
    elseif beat < plan.slam then
        local u = (beat - plan.doorFrom) / M.DOOR_BEATS
        return u * u
    end
    local v = (beat - plan.slam) / M.BOUNCE_BEATS
    if v < 1 then
        return 1 - M.BOUNCE * math.sin(math.pi * v)
    end
    return 1
end

return M
