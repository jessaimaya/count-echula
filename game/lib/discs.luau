-- The record shelf: every playable song. The title screen flips between these.
local beatmap = require('lib/beatmap')
local echula = require('lib/maps/echula')
local funky = require('lib/maps/funky')

export type Disc = {
    title: string,
    sleeve: string, -- second line on the menu: length and difficulty
    audio: string, -- AudioAsset name
    preview: number, -- song time (s) the menu preview starts at: the first chorus
    color: Color, -- record label
    map: beatmap.Beatmap,
}

local M = {}

M.list = {
    {
        title = 'Echula Theme',
        sleeve = 'Side A  ·  1:13  ·  Easy',
        audio = 'echula_theme',
        preview = 0.340 + beatmap.bar(13) * 0.5,
        color = Color.rgb(255, 138, 61),
        map = echula,
    },
    {
        title = 'Funky Counting',
        sleeve = 'Side B  ·  1:41  ·  Groovy',
        audio = 'funky_counting',
        preview = 0.314 + beatmap.bar(18) * 0.5,
        color = Color.rgb(255, 79, 182),
        map = funky,
    },
} :: { Disc }

-- Index `i` wrapped into 1..#list.
function M.wrap(i: number): number
    return (i - 1) % #M.list + 1
end

return M
