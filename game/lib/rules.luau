-- Game rules: lanes, the candy trail, collisions, scoring, health.
-- Pure logic, no rendering. Beats are fractional beat indices (see beatclock).
--
-- Core loop: candy sits on the beat. Catching one fires the sonar automatically
-- (world.luau reads Outcome.collected), so pulses land on the music. It is the only
-- way the sonar fires: there is no manual ping.
local beatmap = require('lib/beatmap')

export type Entity = {
    beat: number,
    lane: number,
    kind: 'candy' | 'garlic',
    state: number, -- 0 pending, 1 resolved (collected / hit), 2 passed
}

export type SwipeJudgement = 'perfect' | 'good' | 'none'

export type Catch = {
    beat: number,
    judgement: SwipeJudgement,
}

export type Outcome = {
    collected: { Catch },
    missed: number, -- candies that passed this update
    hits: number, -- obstacles hit this update
}

export type State = {
    entities: { Entity },
    first: number, -- index of the first entity that may still be pending
    beatLen: number, -- seconds per beat
    hp: number,
    score: number,
    combo: number,
    maxCombo: number,
    candies: number,
    totalCandies: number,
    missed: number,
    perfect: number,
    good: number,
    hits: number,
    lane: number,
    laneFrom: number,
    laneT: number, -- 0..1 lane-change tween progress
    swipeBeat: number, -- beat of the last lane change (for swipe timing)
    swipeLane: number,
    invulnUntil: number, -- beat
    over: boolean,
    finished: boolean,
    endBeat: number,
    tutorialEnd: number,
}

local M = {}

M.MAX_HP = 3
M.LANE_TIME = 0.12 -- seconds for a lane change
M.EARLY = 0.02 -- beats before a candy's beat it can be collected (keeps pulses on the beat)
M.LATE = 0.2 -- beats after its beat a candy / garlic can still be touched
M.INVULN = 2 -- beats of invulnerability after a hit

M.PERFECT = 0.09 -- seconds between swipe and the candy's beat
M.GOOD = 0.2
M.SWIPE_MEMORY = 1.0 -- beats: a swipe counts for the next candy within this

M.SCORE_CANDY = 10
M.SCORE_PERFECT = 50
M.SCORE_GOOD = 20

function M.multiplier(combo: number): number
    if combo >= 50 then
        return 4
    elseif combo >= 25 then
        return 3
    elseif combo >= 10 then
        return 2
    end
    return 1
end

function M.new(map: beatmap.Beatmap): State
    local entities: { Entity } = {}
    local total = 0
    for _, e in map.events do
        table.insert(entities, { beat = e.beat, lane = e.lane, kind = e.kind, state = 0 })
        if e.kind == 'candy' then
            total += 1
        end
    end
    return {
        entities = entities,
        first = 1,
        beatLen = 60 / map.bpm,
        hp = M.MAX_HP,
        score = 0,
        combo = 0,
        maxCombo = 0,
        candies = 0,
        totalCandies = total,
        missed = 0,
        perfect = 0,
        good = 0,
        hits = 0,
        lane = 0,
        laneFrom = 0,
        laneT = 1,
        swipeBeat = -math.huge,
        swipeLane = 0,
        invulnUntil = -math.huge,
        over = false,
        finished = false,
        endBeat = map.endBeat,
        tutorialEnd = map.tutorialEnd,
    }
end

-- Lane the bat collides in: it switches once the tween is half way.
function M.effectiveLane(s: State): number
    return if s.laneT >= 0.5 then s.lane else s.laneFrom
end

-- Visual lane position (eased), for rendering.
function M.laneX(s: State): number
    local t = s.laneT
    local e = 1 - (1 - t) * (1 - t)
    return s.laneFrom + (s.lane - s.laneFrom) * e
end

function M.swipe(s: State, dir: number, beat: number)
    if s.over or s.finished then
        return
    end
    local target = math.clamp(s.lane + dir, -1, 1)
    if target == s.lane then
        return
    end
    s.laneFrom = M.laneX(s)
    s.lane = target
    s.laneT = 0
    s.swipeBeat = beat
    s.swipeLane = target
end

local function bump(s: State)
    s.combo += 1
    if s.combo > s.maxCombo then
        s.maxCombo = s.combo
    end
end

-- Swipe timing against a candy's beat, in seconds.
function M.judgeError(s: State, swipeBeat: number, candyBeat: number): SwipeJudgement
    local err = math.abs(swipeBeat - candyBeat) * s.beatLen
    if err <= M.PERFECT then
        return 'perfect'
    elseif err <= M.GOOD then
        return 'good'
    end
    return 'none'
end

local function collect(s: State, e: Entity): Catch
    e.state = 1
    local j: SwipeJudgement = 'none'
    if s.swipeLane == e.lane and s.swipeBeat >= e.beat - M.SWIPE_MEMORY then
        j = M.judgeError(s, s.swipeBeat, e.beat)
        s.swipeBeat = -math.huge -- one judgement per swipe
    end
    local mult = M.multiplier(s.combo)
    s.candies += 1
    s.score += M.SCORE_CANDY * mult
    if j == 'perfect' then
        s.perfect += 1
        s.score += M.SCORE_PERFECT * mult
    elseif j == 'good' then
        s.good += 1
        s.score += M.SCORE_GOOD * mult
    end
    bump(s)
    return { beat = e.beat, judgement = j }
end

-- Advance to fractional beat `beat` after `dt` seconds. Resolves collisions.
function M.update(s: State, beat: number, dt: number): Outcome
    local out: Outcome = { collected = {}, missed = 0, hits = 0 }
    if s.laneT < 1 then
        s.laneT = math.min(1, s.laneT + dt / M.LANE_TIME)
    end
    if s.over or s.finished then
        return out
    end

    local lane = M.effectiveLane(s)
    local i = s.first
    while i <= #s.entities do
        local e = s.entities[i]
        if e.beat - M.EARLY > beat and e.beat - M.LATE > beat then
            break
        end
        if e.state == 0 then
            if beat > e.beat + M.LATE then
                e.state = 2
                if e.kind == 'candy' then
                    s.missed += 1
                    s.combo = 0
                    out.missed += 1
                end
            elseif e.lane == lane then
                if e.kind == 'candy' then
                    if beat >= e.beat - M.EARLY then
                        table.insert(out.collected, collect(s, e))
                    end
                elseif beat >= e.beat - M.LATE and beat >= s.tutorialEnd and beat >= s.invulnUntil then
                    e.state = 1
                    s.hp -= 1
                    s.hits += 1
                    s.combo = 0
                    s.invulnUntil = beat + M.INVULN
                    out.hits += 1
                    if s.hp <= 0 then
                        s.over = true
                    end
                end
            end
        end
        i += 1
    end
    while s.first <= #s.entities and s.entities[s.first].state ~= 0 do
        s.first += 1
    end
    if beat >= s.endBeat then
        s.finished = true
    end
    return out
end

-- Final grade: share of candies caught; S also needs no hits.
function M.grade(s: State): string
    if s.over then
        return 'fail'
    end
    local ratio = s.candies / math.max(1, s.totalCandies)
    if ratio >= 0.95 and s.hits == 0 then
        return 'S'
    elseif ratio >= 0.85 then
        return 'A'
    elseif ratio >= 0.7 then
        return 'B'
    end
    return 'C'
end

return M
