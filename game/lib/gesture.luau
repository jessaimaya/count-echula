-- Pointer gesture classifier: tap = sonar pulse, horizontal swipe = lane change.
-- A tap is timed at press time. A press that becomes a swipe before the tap
-- fires (release or HOLD seconds) cancels the pulse, so one gesture never does both.

export type Gesture = {
    down: boolean,
    t0: number,
    x0: number,
    fired: boolean, -- this press already produced its event
}

export type GestureEvent = {
    kind: 'tap' | 'swipe',
    t: number, -- tap: press time; swipe: time the threshold was crossed
    dir: number, -- swipe: -1 left, +1 right; tap: 0
}

local M = {}

M.SWIPE = 30 -- artboard units of horizontal travel
M.HOLD = 0.09 -- seconds before a still press counts as a tap

function M.new(): Gesture
    return { down = false, t0 = 0, x0 = 0, fired = false }
end

local function tap(g: Gesture): GestureEvent
    g.fired = true
    return { kind = 'tap', t = g.t0, dir = 0 }
end

local function swipe(g: Gesture, t: number, dx: number): GestureEvent
    g.fired = true
    return { kind = 'swipe', t = t, dir = if dx > 0 then 1 else -1 }
end

function M.press(g: Gesture, t: number, x: number)
    g.down = true
    g.t0 = t
    g.x0 = x
    g.fired = false
end

function M.move(g: Gesture, t: number, x: number): GestureEvent?
    if not g.down or g.fired then
        return nil
    end
    local dx = x - g.x0
    if math.abs(dx) >= M.SWIPE then
        return swipe(g, t, dx)
    end
    return nil
end

function M.release(g: Gesture, t: number, x: number): GestureEvent?
    local ev: GestureEvent? = nil
    if g.down and not g.fired then
        local dx = x - g.x0
        if math.abs(dx) >= M.SWIPE then
            ev = swipe(g, t, dx)
        else
            ev = tap(g)
        end
    end
    g.down = false
    return ev
end

-- Call every frame: fires the tap once the press has been still for HOLD.
function M.tick(g: Gesture, t: number): GestureEvent?
    if g.down and not g.fired and t - g.t0 >= M.HOLD then
        return tap(g)
    end
    return nil
end

return M
