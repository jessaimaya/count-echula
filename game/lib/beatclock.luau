-- Beat clock: converts song time (seconds) to beats and judges taps.
-- Song time comes from the audio engine clock when music plays (see world.luau).

export type Clock = {
    bpm: number,
    firstBeat: number, -- song time of beat 0, seconds
    offset: number, -- output-latency compensation, seconds (added to song time)
}

export type Judgement = 'perfect' | 'good' | 'miss'

local M = {}

M.PERFECT = 0.050
M.GOOD = 0.110

function M.new(bpm: number, firstBeat: number, offset: number): Clock
    return { bpm = bpm, firstBeat = firstBeat, offset = offset }
end

function M.beatLen(c: Clock): number
    return 60 / c.bpm
end

-- Fractional beat index at song time t.
function M.beatAt(c: Clock, t: number): number
    return (t + c.offset - c.firstBeat) / M.beatLen(c)
end

-- Song time of beat n.
function M.timeOf(c: Clock, n: number): number
    return c.firstBeat - c.offset + n * M.beatLen(c)
end

-- Judge a tap at song time t against the nearest beat.
-- Returns the judgement, the nearest beat index and the signed error in seconds.
function M.judge(c: Clock, t: number): (Judgement, number, number)
    local b = M.beatAt(c, t)
    local n = math.floor(b + 0.5)
    local delta = (b - n) * M.beatLen(c)
    local a = math.abs(delta)
    if a <= M.PERFECT then
        return 'perfect', n, delta
    elseif a <= M.GOOD then
        return 'good', n, delta
    end
    return 'miss', n, delta
end

return M
