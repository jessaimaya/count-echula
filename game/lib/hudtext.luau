-- HUD strings written into GameVM. Pure functions, unit tested.
local beatmap = require('lib/beatmap')

local M = {}

local WORDS = {
    'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
    'Eighteen', 'Nineteen', 'Twenty',
}

-- "Three! Ah-ah-ah!" — the Count counts every candy; every third one he laughs.
function M.count(n: number): string
    local word = WORDS[n] or tostring(n)
    if n % 3 == 0 then
        return word .. '! Ah-ah-ah!'
    end
    return word .. '!'
end

-- 12345 -> "12,345"
function M.thousands(n: number): string
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then
        out = out:sub(2)
    end
    return out
end

function M.judge(j: string): string
    if j == 'perfect' then
        return 'PERFECT!'
    elseif j == 'good' then
        return 'GOOD'
    end
    return 'miss...'
end

function M.mult(multiplier: number, combo: number): string
    if combo <= 0 then
        return 'x' .. tostring(multiplier)
    end
    return 'x' .. tostring(multiplier) .. '   combo ' .. tostring(combo)
end

-- Tutorial / section prompt for fractional beat `beat` of `map`.
function M.prompt(map: beatmap.Beatmap, beat: number): string
    if beat < 0 then
        return ''
    elseif beat < map.sonarTutorial then
        return 'Swipe (or arrow keys) to catch\nthe candy on the beat!'
    elseif beat < map.tutorialEnd then
        return 'Catch candy to send your sonar:\nit is your only light in the dark!'
    end
    for _, s in map.sections do
        local text = s.prompt
        if text ~= nil and beat >= s.from and beat < s.from + (s.promptBeats or 8) then
            return text
        end
    end
    return ''
end

export type Summary = {
    over: boolean,
    score: number,
    perfect: number, -- swipe timing
    good: number,
    candies: number,
    totalCandies: number,
    maxCombo: number,
    grade: string,
}

function M.resultTitle(s: Summary): string
    return if s.over then 'Stake-d!' else 'Happy Halloween!'
end

function M.gradeText(s: Summary): string
    return if s.over then 'RIP' else s.grade
end

-- Results footer: a lost run retries the disc, a finished one returns to the shelf.
function M.again(s: Summary): string
    return if s.over then 'tap to try again' else 'tap for the record shelf'
end

function M.stats(s: Summary): string
    return string.format('Score  %s\nCandy %d / %d   Max combo %d\nPerfect swipes %d   Good %d',
        M.thousands(s.score), s.candies, s.totalCandies, s.maxCombo, s.perfect, s.good)
end

return M
