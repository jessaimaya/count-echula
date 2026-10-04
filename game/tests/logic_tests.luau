local beatclock = require('lib/beatclock')
local gesture = require('lib/gesture')
local rules = require('lib/rules')
local beatmap = require('lib/beatmap')
local hudtext = require('lib/hudtext')
local harmony = require('lib/harmony')
local discs = require('lib/discs')
local finale = require('lib/finale')
local echula = require('lib/maps/echula')
local funky = require('lib/maps/funky')
local werewolf = require('lib/maps/werewolf')

local function emptyMap(): beatmap.Beatmap
    return {
        bpm = 120,
        firstBeat = 0,
        endBeat = 100,
        sections = {},
        bursts = {},
        heartbeats = {},
        ice = nil,
        chords = { 'C' },
        events = {},
    }
end

return function(): Tests
    return function(test: Tester)
        test.group('beatclock', function()
            local c = beatclock.new(120, 0.34, 0)
            test.case('beat 0 is at firstBeat', function(expect)
                expect(beatclock.beatAt(c, 0.34)).is(0)
                expect(beatclock.timeOf(c, 4)).is(2.34)
            end)
            test.case('judgement windows', function(expect)
                local j1 = beatclock.judge(c, 0.34 + 0.5 * 10 + 0.03)
                expect(j1).is('perfect')
                local j2, n2 = beatclock.judge(c, 0.34 + 0.5 * 10 - 0.08)
                expect(j2).is('good')
                expect(n2).is(10)
                local j3 = beatclock.judge(c, 0.34 + 0.5 * 10 + 0.2)
                expect(j3).is('miss')
            end)
            test.case('offset shifts the grid', function(expect)
                local c2 = beatclock.new(120, 0.34, 0.02)
                local j = beatclock.judge(c2, 0.34 - 0.02 + 0.5 * 3)
                expect(j).is('perfect')
            end)
        end)

        test.group('gesture', function()
            test.case('quick press + release is a tap timed at press', function(expect)
                local g = gesture.new()
                gesture.press(g, 1.0, 100)
                local ev = gesture.release(g, 1.05, 104)
                expect(ev ~= nil).is(true)
                if ev then
                    expect(ev.kind).is('tap')
                    expect(ev.t).is(1.0)
                end
            end)
            test.case('still press fires the tap after HOLD', function(expect)
                local g = gesture.new()
                gesture.press(g, 2.0, 100)
                expect(gesture.tick(g, 2.05) == nil).is(true)
                local ev = gesture.tick(g, 2.1)
                expect(ev ~= nil and ev.kind == 'tap').is(true)
                expect(gesture.release(g, 2.3, 100) == nil).is(true)
            end)
            test.case('drag past the threshold is a swipe and cancels the tap', function(expect)
                local g = gesture.new()
                gesture.press(g, 3.0, 100)
                local ev = gesture.move(g, 3.04, 60)
                expect(ev ~= nil and ev.kind == 'swipe' and ev.dir == -1).is(true)
                expect(gesture.tick(g, 3.2) == nil).is(true)
                expect(gesture.release(g, 3.3, 20) == nil).is(true)
            end)
            test.case('one swipe per press', function(expect)
                local g = gesture.new()
                gesture.press(g, 4.0, 100)
                gesture.move(g, 4.02, 140)
                expect(gesture.move(g, 4.04, 200) == nil).is(true)
            end)
        end)

        test.group('rules', function()
            test.case('multiplier tiers', function(expect)
                expect(rules.multiplier(0)).is(1)
                expect(rules.multiplier(10)).is(2)
                expect(rules.multiplier(25)).is(3)
                expect(rules.multiplier(50)).is(4)
            end)
            test.case('candy is caught on its beat, not before', function(expect)
                local m = emptyMap()
                m.events = { { beat = 4, lane = 0, kind = 'candy' } }
                local s = rules.new(m)
                local early = rules.update(s, 3.9, 0.016)
                expect(#early.collected).is(0)
                local out = rules.update(s, 4, 0.016)
                expect(#out.collected).is(1)
                expect(s.candies).is(1)
                expect(s.combo).is(1)
            end)
            test.case('a missed candy resets the combo', function(expect)
                local m = emptyMap()
                m.events = {
                    { beat = 4, lane = 0, kind = 'candy' },
                    { beat = 6, lane = 1, kind = 'candy' },
                }
                local s = rules.new(m)
                rules.update(s, 4, 0.016)
                local out = rules.update(s, 6.5, 0.016)
                expect(out.missed).is(1)
                expect(s.combo).is(0)
                expect(s.missed).is(1)
            end)
            test.case('swipe timing into the candy lane is judged', function(expect)
                local m = emptyMap()
                m.events = {
                    { beat = 4, lane = 1, kind = 'candy' },
                    { beat = 8, lane = 0, kind = 'candy' },
                }
                local s = rules.new(m)
                rules.update(s, 3.9, 0)
                rules.swipe(s, 1, 3.95) -- 25 ms early at 120 BPM
                rules.update(s, 4, rules.LANE_TIME)
                expect(s.perfect).is(1)
                rules.update(s, 7.5, 0)
                rules.swipe(s, -1, 7.7) -- 150 ms early
                local out = rules.update(s, 8, rules.LANE_TIME)
                expect(s.good).is(1)
                expect(out.collected[1].judgement).is('good')
            end)
            test.case('no judgement when already in the lane', function(expect)
                local m = emptyMap()
                m.events = { { beat = 4, lane = 0, kind = 'candy' } }
                local s = rules.new(m)
                local out = rules.update(s, 4, 0.016)
                expect(out.collected[1].judgement).is('none')
            end)
            test.case('garlic hits cost hp, then invulnerability', function(expect)
                local m = emptyMap()
                m.events = {
                    { beat = 4, lane = 0, kind = 'garlic' },
                    { beat = 5, lane = 0, kind = 'garlic' },
                    { beat = 8, lane = 0, kind = 'garlic' },
                }
                local s = rules.new(m)
                rules.update(s, 4, 0.016)
                expect(s.hp).is(2)
                rules.update(s, 5, 0.016)
                expect(s.hp).is(2)
                rules.update(s, 8, 0.016)
                expect(s.hp).is(1)
            end)
            test.case('missing a candy flies into the garlic left behind', function(expect)
                local m = emptyMap()
                -- the trail moves to lane 1; garlic waits in lane 0, where he stays
                m.events = {
                    { beat = 4, lane = 1, kind = 'candy' },
                    { beat = 4, lane = 0, kind = 'garlic' },
                }
                local s = rules.new(m)
                local out = rules.update(s, 4, 0.016)
                expect(out.hits).is(1)
                expect(s.hp).is(rules.MAX_HP - 1)
                out = rules.update(s, 5, 0.016)
                expect(out.missed).is(1)
            end)
            test.case('three hits is game over', function(expect)
                local m = emptyMap()
                m.events = {
                    { beat = 4, lane = 0, kind = 'garlic' },
                    { beat = 8, lane = 0, kind = 'garlic' },
                    { beat = 12, lane = 0, kind = 'garlic' },
                }
                local s = rules.new(m)
                for b = 4, 12, 4 do
                    rules.update(s, b, 0.016)
                end
                expect(s.over).is(true)
            end)
            test.case('swipe dodges once the tween passes half way', function(expect)
                local m = emptyMap()
                m.events = { { beat = 4, lane = 0, kind = 'garlic' } }
                local s = rules.new(m)
                rules.update(s, 3.5, 0)
                rules.swipe(s, 1, 3.5)
                rules.update(s, 3.6, rules.LANE_TIME * 0.6)
                rules.update(s, 4, 0.016)
                expect(s.hp).is(rules.MAX_HP)
                expect(s.lane).is(1)
            end)
            test.case('lanes clamp at the edges', function(expect)
                local s = rules.new(emptyMap())
                rules.swipe(s, 1, 0)
                rules.swipe(s, 1, 0)
                expect(s.lane).is(1)
            end)
            test.case('grade from the share of candy caught', function(expect)
                local s = rules.new(emptyMap())
                s.totalCandies = 100
                s.candies = 96
                expect(rules.grade(s)).is('S')
                s.hits = 1
                expect(rules.grade(s)).is('A')
                s.candies = 70
                expect(rules.grade(s)).is('B')
            end)
            for _, d in discs.list do
                local map = d.map
                test.case(d.title .. ': candy trail, sorted, garlic never on the trail', function(expect)
                    local sorted = true
                    local clash = false
                    local candyAt: { [number]: number } = {}
                    for i, e in map.events do
                        if i > 1 and e.beat < map.events[i - 1].beat then
                            sorted = false
                        end
                        if e.kind == 'candy' then
                            candyAt[e.beat] = e.lane
                        end
                    end
                    for _, e in map.events do
                        if e.kind == 'garlic' and candyAt[e.beat] == e.lane then
                            clash = true
                        end
                    end
                    expect(sorted).is(true)
                    expect(clash).is(false)
                    expect(#map.events).greaterThan(100)
                    expect(map.events[#map.events].beat < map.endBeat).is(true)
                end)
                test.case(d.title .. ': two chords per bar, a sample for every catch note', function(expect)
                    local have: { [number]: boolean } = {}
                    for _, m in harmony.NOTES do
                        have[m] = true
                    end
                    expect(#map.chords).is(map.endBeat / 2)
                    local ok = true
                    for beat = 0, map.endBeat - 1 do
                        for step = 1, 20 do
                            local n = harmony.noteFor(map, beat, step)
                            if not have[n] or not have[harmony.above(map, beat, n)] then
                                ok = false
                            end
                        end
                    end
                    expect(ok).is(true)
                end)
            end
            test.case('disc lengths match the tracks', function(expect)
                expect(echula.endBeat).is(144)
                expect(funky.endBeat).is(200)
                expect(werewolf.endBeat).is(162)
            end)
        end)

        test.group('beatmap', function()
            test.case('fog, heartbeat and frost follow the map', function(expect)
                expect(beatmap.fogAt(echula, 81)).is(1)
                expect(beatmap.fogAt(echula, 100)).is(0)
                expect(beatmap.heartbeatAt(echula, 82)).is(true)
                expect(beatmap.heartbeatAt(funky, 98)).is(true)
                expect(beatmap.heartbeatAt(funky, 99)).is(false)
                expect(beatmap.heartbeatAt(funky, 40)).is(false)
                expect(beatmap.heartbeatAt(werewolf, 95)).is(true) -- the blackout
                expect(beatmap.heartbeatAt(werewolf, 120)).is(false)
                expect(beatmap.fogAt(werewolf, 95)).is(1)
                expect(beatmap.fogAt(werewolf, 102)).is(0)
                local f0 = beatmap.frostAt(funky, 92)
                local f1, cracks1 = beatmap.frostAt(funky, 100)
                local _, cracks2 = beatmap.frostAt(funky, 115.2)
                local f3, _, since = beatmap.frostAt(funky, 116.5)
                expect(f0).is(0)
                expect(f1).is(1)
                expect(cracks1).is(0)
                expect(cracks2).is(2)
                expect(f3).is(0)
                expect(since).is(0.5)
                expect((beatmap.frostAt(echula, 100))).is(0)
            end)
            test.case('the frozen glide has no garlic', function(expect)
                local ice = funky.ice
                local garlic = 0
                if ice ~= nil then
                    for _, e in funky.events do
                        if e.kind == 'garlic' and e.beat >= ice.freeze and e.beat < ice.shatter then
                            garlic += 1
                        end
                    end
                end
                expect(garlic).is(0)
            end)
            test.case('the street keeps accelerating after the blackout', function(expect)
                local storm = beatmap.bar(26) + 2
                local last = beatmap.bar(41)
                local function speed(b: number): number
                    return (beatmap.distanceAt(werewolf, b + 0.005) - beatmap.distanceAt(werewolf, b - 0.005)) / 0.01
                end
                -- normal speed before (and on the other discs)
                expect(beatmap.distanceAt(werewolf, 10)).is(10)
                expect(beatmap.distanceAt(echula, 100)).is(100)
                expect(math.abs(speed(storm - 1) - 1) < 1e-6).is(true)
                -- the lift to x1.2, then x1.6 on the last hit
                expect(math.abs(speed(beatmap.bar(27)) - 1.2) < 1e-3).is(true)
                expect(math.abs(speed(last + 1) - 1.6) < 1e-6).is(true)
                -- it never stops speeding up, and never jumps
                local rising = true
                local prev = speed(storm)
                local b = storm
                while b < last do
                    b += 0.25
                    local v = speed(b)
                    if v < prev - 1e-6 or v - prev > 0.05 then
                        rising = false
                    end
                    prev = v
                end
                expect(rising).is(true)
                expect(speed(beatmap.bar(34)) > speed(beatmap.bar(30))).is(true)
            end)
            test.case('the blackout has no garlic', function(expect)
                local garlic = 0
                for _, e in werewolf.events do
                    if e.kind == 'garlic' and e.beat > beatmap.bar(24) and e.beat < beatmap.bar(26) + 2 then
                        garlic += 1
                    end
                end
                expect(garlic).is(0)
            end)
            test.case('disc index wraps around the shelf', function(expect)
                expect(discs.wrap(0)).is(#discs.list)
                expect(discs.wrap(#discs.list + 1)).is(1)
            end)
        end)

        test.group('harmony', function()
            test.case('the streak walks the arpeggio up then down', function(expect)
                local a = harmony.noteFor(echula, 16, 1)
                local b = harmony.noteFor(echula, 16, 2)
                local c = harmony.noteFor(echula, 16, 3)
                expect(b).greaterThan(a)
                expect(c).greaterThan(b)
                expect(a).is(72) -- bar 5 is C: starts on C5
            end)
            test.case('perfect harmony note sits above', function(expect)
                expect(harmony.above(echula, 16, 72)).is(76)
            end)
            test.case('minor and flat chords', function(expect)
                expect(harmony.pitchClasses('Dm')[2]).is(5) -- F
                expect(harmony.pitchClasses('Bb')[1]).is(10)
                expect(harmony.pitchClasses('A')[2]).is(1) -- C#
                expect(harmony.noteFor(funky, 4, 1)).is(74) -- bar 2 is Dm: starts on D5
            end)
        end)

        test.group('hudtext', function()
            test.case('the Count counts, laughing every third candy', function(expect)
                expect(hudtext.count(1)).is('One!')
                expect(hudtext.count(3)).is('Three! Ah-ah-ah!')
                expect(hudtext.count(22)).is('22!')
            end)
            test.case('thousands separators', function(expect)
                expect(hudtext.thousands(0)).is('0')
                expect(hudtext.thousands(999)).is('999')
                expect(hudtext.thousands(1000)).is('1,000')
                expect(hudtext.thousands(1234567)).is('1,234,567')
            end)
            test.case('results count up', function(expect)
                local s: hudtext.Summary = { over = false, score = 7340, perfect = 8, good = 42, candies = 105, totalCandies = 105, maxCombo = 105, grade = 'S' }
                expect(hudtext.counting(s, 0).score).is(0)
                expect(hudtext.counting(s, 0).totalCandies).is(105)
                expect(hudtext.counting(s, 0.5).score > 7340 / 2).is(true)
                expect(hudtext.stats(hudtext.counting(s, 1))).is(hudtext.stats(s))
                expect(hudtext.stats(hudtext.counting(s, 2))).is(hudtext.stats(s))
            end)
            test.case('results text', function(expect)
                local s: hudtext.Summary = { over = true, score = 1500, perfect = 1, good = 2, candies = 4, totalCandies = 10, maxCombo = 5, grade = 'fail' }
                expect(hudtext.resultTitle(s)).is('Stake-d!')
                expect(hudtext.gradeText(s)).is('RIP')
                expect(hudtext.again(s)).is('tap to try again')
                s.over = false
                expect(hudtext.again(s)).is('tap for the record shelf')
            end)
        end)
        test.group('finale', function()
            test.case('the street stops before the gate, after the last candy', function(expect)
                for _, map in { echula, funky, werewolf } do
                    local plan = finale.plan(map)
                    local last = map.events[#map.events].beat
                    -- the candy still passes at full speed
                    expect(finale.street(map, plan, last)).is(beatmap.distanceAt(map, last))
                    local prev = -1
                    for b = last, last + 12, 0.25 do
                        local d = finale.street(map, plan, b)
                        expect(d >= prev).is(true)
                        expect(d < plan.stop).is(true)
                        prev = d
                    end
                    expect(plan.stop - prev < 0.01).is(true)
                    expect(plan.gate - plan.stop).is(finale.GAP)
                    expect(plan.results >= map.endBeat).is(true)
                    expect(plan.results > plan.slam).is(true)
                end
            end)
            test.case('he flies in, then the portcullis drops and bounces', function(expect)
                local plan = finale.plan(echula)
                expect(finale.fly(plan, plan.flyFrom)).is(0)
                expect(finale.fly(plan, plan.flyFrom + finale.FLY_BEATS)).is(1)
                expect(plan.doorFrom >= plan.flyFrom + finale.FLY_BEATS).is(true)
                expect(finale.door(plan, plan.doorFrom)).is(0)
                expect(finale.door(plan, plan.slam)).is(1)
                expect(finale.door(plan, plan.slam + finale.BOUNCE_BEATS / 2) < 1).is(true)
                expect(finale.door(plan, plan.slam + 1)).is(1)
            end)
        end)
    end
end
