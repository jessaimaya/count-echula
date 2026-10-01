-- World: the playfield. Owns the song clock, input, rules and the GPU renderer
-- (3D street + sonar post pass). HUD text/menus will live in RML; the shapes
-- drawn at the end of draw() are temporary grey-box HUD.
local beatclock = require('lib/beatclock')
local gesture = require('lib/gesture')
local rules = require('lib/rules')
local beatmap = require('lib/beatmap')
local hudtext = require('lib/hudtext')
local harmony = require('lib/harmony')
local discs = require('lib/discs')

local NEAR = 0.1
local FAR = 60
local STRIDE = 40 -- vec3 center, vec2 size, vec4 color, f32 kind
local MAX_INST = 128
local LANE = 1.2 -- world units between lanes
local TILE = 2.0 -- world units per beat
local BAT_Z = -3.0 -- world z of the bat / catch line (further from the camera keeps side lanes on screen)
local LOOKAHEAD = 14 -- beats of entities drawn ahead of the bat
local AUDIO_OFFSET = 0 -- seconds; output-latency compensation (tune on device)
local START_DELAY = 0.15 -- seconds between the start tap and the song
local POST_SIZE = 224

-- Streak trail from the bat (combo = candies in a row without a miss or hit).
local TRAIL_T1 = 10 -- light trail (matches the x2 multiplier)
local TRAIL_T2 = 25 -- wing trails (matches x3)
local TRAIL_SEG = 14 -- segments per ribbon
local TRAIL_BEATS = 1.2 -- ribbon length in beats of flight
local WING = 0.34 -- world units from the bat's center to each wingtip
local SPARKLES = 10
local SHARDS = 30 -- trail pieces when a streak breaks
local SHARD_LIFE = 0.8 -- seconds
local SHARD_GRAVITY = 900 -- artboard units / s^2

-- Atmosphere (sonar.wgsl). Tweak these to taste.
local FOG_TOP = 1.7 -- world height where the ground fog ends; rooftops (1.7-2.8) poke out
local FOG_DENSITY = 0.92 -- 0..1 at street level
local CLASS_TINT = 0.22 -- 0 = pure grey outlines, 1 = full class colors
local CHROMA = 0.5 -- chromatic fringe on the perfect wavefront, 0 = off
local RESTART_GUARD = 1.0 -- seconds after the results appear before a tap restarts
local PING_STRENGTH = 0.18 -- manual ping reach (fraction of a full candy pulse)
local PING_BEATS = 0.6
local CANDY_STRENGTH = 0.9 -- sonar reach when a candy is caught
local CANDY_BEATS = 1.6 -- how long that reveal lasts

-- Record shelf (title screen) and pause. Hit areas are fractions of the layout size
-- and match the RML in scene.rml (Title > Shelf, Hud > Pause Button, Pause).
local PREVIEW_LEN = 16 -- seconds of chorus the menu plays before looping (8 bars)
local PREVIEW_FADE = 0.8
local PREVIEW_VOLUME = 0.8
local ARROW_W = 0.24 -- side strips of the shelf that flip records
local SHELF_TOP = 0.28
local SHELF_BOTTOM = 0.62
local PAUSE_SIZE = 84 -- top-right square of the pause button
local RESUME_Y = 0.5 -- pause menu buttons: centre y and half height
local MENU_Y = 0.6
local BUTTON_H = 0.045
local BUTTON_W = 0.3 -- half width
local COUNTDOWN_BEATS = 3 -- after Resume, the song waits this many beats

-- Keyboard (GLFW key codes, as KeyboardEvent.key reports them). Needs the
-- <FocusData/> on the World layout in scene.rml, and focus set by the "Flow" machine.
local KEY_SPACE = 32
local KEY_A = 65
local KEY_D = 68
local KEY_M = 77
local KEY_P = 80
local KEY_ESCAPE = 256
local KEY_ENTER = 257
local KEY_BACKSPACE = 259
local KEY_RIGHT = 262
local KEY_LEFT = 263
local KEY_KP_ENTER = 335

type Pulse = { start: number, strength: number, kind: number, life: number }

type Mode = 'ready' | 'playing' | 'over' | 'done'

-- An effect sound scheduled ahead on the audio clock; stopped if the song pauses.
type Pending = { sound: AudioSound, at: number }

-- GameVM.mode values, read by the "Screens" state machine layer.
local MODE_NUM: { [Mode]: number } = { ready = 0, playing = 1, over = 2, done = 3 }

type Shard = { x: number, y: number, vx: number, vy: number, spin: number, size: number, color: Color, born: number }

type Sfx = {
    streakBreak: AudioSource?,
    heartbeat: AudioSource?,
    pingPerfect: AudioSource?,
    pingGood: AudioSource?,
    pingGlitch: AudioSource?,
    candy: AudioSource?,
    hit: AudioSource?,
}

type World = {
    context: Context?,
    size: Vector,
    scale: number,
    -- GPU
    scene: GPUCanvas?,
    final: GPUCanvas?,
    depthView: GPUTextureView?,
    scenePipe: GPUPipeline?,
    postPipe: GPUPipeline?,
    sceneBG: GPUBindGroup?,
    postBG: GPUBindGroup?,
    camUBO: GPUBuffer?,
    postUBO: GPUBuffer?,
    instBuf: GPUBuffer?,
    camData: buffer,
    postData: buffer,
    instData: buffer,
    viewProj: Mat4,
    invViewProj: Mat4,
    sampler: ImageSampler,
    -- disc + song clock
    disc: number, -- index into discs.list
    map: beatmap.Beatmap,
    sources: { [number]: AudioSource },
    preview: AudioSound?,
    previewStart: number, -- local time the menu preview started
    pending: { Pending },
    menuGest: gesture.Gesture,
    menuPress: Vector,
    paused: boolean,
    pausedSong: number, -- song time when paused
    resumeAt: number, -- local time the countdown ends (0 = none)
    clock: beatclock.Clock,
    source: AudioSource?,
    sound: AudioSound?,
    audioStart: number, -- audio engine time the song was scheduled at
    songStart: number, -- local time the song started (fallback clock)
    lastAudio: number,
    audioIdle: number, -- seconds the audio clock has not moved
    useAudioClock: boolean,
    -- game
    mode: Mode,
    time: number, -- local seconds since init
    songTime: number,
    beat: number,
    beatIdx: number,
    gest: gesture.Gesture,
    state: rules.State,
    pulses: { Pulse },
    pulseNext: number,
    hitAt: number,
    endAt: number,
    -- view model (GameVM) + sound effects
    vm: ViewModel?,
    strings: { [string]: Property<string> },
    lastStrings: { [string]: string },
    modeProp: Property<number>?,
    discProp: Property<number>?,
    discColor: Property<Color>?,
    pausedProp: Property<boolean>?,
    discFire: PropertyTrigger?,
    autopilot: Property<boolean>?,
    autopilotUntil: Property<number>?,
    judgeFire: PropertyTrigger?,
    candyFire: PropertyTrigger?,
    sfx: Sfx,
    notes: { [number]: AudioSource },
    -- temporary HUD
    paint: Paint,
    paths: { Path },
    -- effects
    burstAt: number,
    burstPower: number,
    burstIdx: number,
    trailLevel: number, -- smoothed 0..2
    histBeat: { number },
    histX: { number },
    trailPaths: { Path },
    trailPaint: Paint,
    prevCombo: number,
    breakAt: number,
    breakPower: number,
    shards: { Shard },
    shardPaths: { Path },
}

local function newPulses(): { Pulse }
    local p: { Pulse } = {}
    for i = 1, 4 do
        p[i] = { start = -100, strength = 0, kind = 0, life = 1 }
    end
    return p
end

local function addPulse(self: World, strength: number, kind: number, beats: number)
    local p = self.pulses[self.pulseNext]
    p.start = self.time
    p.strength = strength
    p.kind = kind
    p.life = beats * beatclock.beatLen(self.clock)
    self.pulseNext = self.pulseNext % 4 + 1
end

-- ------------------------------------------------------ view model + sound fx

local function setString(self: World, name: string, value: string)
    if self.lastStrings[name] == value then
        return
    end
    local p = self.strings[name]
    if p ~= nil then
        p.value = value
        self.lastStrings[name] = value
    end
end

local function setMode(self: World, mode: Mode)
    self.mode = mode
    local p = self.modeProp
    if p ~= nil then
        p.value = MODE_NUM[mode]
    end
end

local function fire(t: PropertyTrigger?)
    if t ~= nil then
        t:fire()
    end
end

local function playSfx(src: AudioSource?, volume: number)
    if src == nil then
        return
    end
    local s = Audio.play(src)
    if s ~= nil then
        s.volume = volume
    end
end

-- ---------------------------------------------------------------- song clock

local function songNow(self: World): number
    if self.useAudioClock then
        return Audio.time() - self.audioStart
    end
    return self.time - self.songStart
end

-- Play `src` at audio-engine time `at` (or now if that has passed or the audio clock
-- is off). Future sounds are remembered so a pause can silence them.
local function playAt(self: World, src: AudioSource, at: number?, volume: number)
    local s: AudioSound? = nil
    if at ~= nil and self.useAudioClock and at > Audio.time() then
        s = Audio.playAtTime(src, at)
        if s ~= nil then
            table.insert(self.pending, { sound = s, at = at })
        end
    end
    if s == nil then
        s = Audio.play(src)
    end
    if s ~= nil then
        s.volume = volume
    end
end

local function stopPending(self: World)
    for _, p in self.pending do
        p.sound:stop()
    end
    self.pending = {}
end

local function prunePending(self: World)
    local now = Audio.time()
    local keep: { Pending } = {}
    for _, p in self.pending do
        if p.at > now then
            table.insert(keep, p)
        end
    end
    self.pending = keep
end

local function stopSong(self: World)
    local s = self.sound
    if s ~= nil then
        s:stop()
    end
    self.sound = nil
    stopPending(self)
end

-- ------------------------------------------------------------- record shelf

local function stopPreview(self: World)
    local s = self.preview
    if s ~= nil then
        s:stop()
    end
    self.preview = nil
end

-- The selected disc's first chorus, faded in; advance() fades it out and loops it.
local function startPreview(self: World)
    stopPreview(self)
    self.previewStart = self.time
    local src = self.sources[self.disc]
    if src == nil then
        return
    end
    local s = Audio.play(src)
    if s ~= nil then
        s:seek(discs.list[self.disc].preview)
        s.volume = 0
    end
    self.preview = s
end

local function previewTick(self: World)
    local el = self.time - self.previewStart
    if el >= PREVIEW_LEN then
        startPreview(self)
        return
    end
    local s = self.preview
    if s ~= nil then
        local fadeIn = math.clamp(el / PREVIEW_FADE, 0, 1)
        local fadeOut = math.clamp((PREVIEW_LEN - el) / PREVIEW_FADE, 0, 1)
        s.volume = PREVIEW_VOLUME * math.min(fadeIn, fadeOut)
    end
end

-- Song time the menu is "at" (drives the idle pulses on the preview's beat).
local function previewSongTime(self: World): number
    return discs.list[self.disc].preview + (self.time - self.previewStart)
end

local function selectDisc(self: World, index: number, preview: boolean)
    self.disc = discs.wrap(index)
    local d = discs.list[self.disc]
    self.map = d.map
    self.source = self.sources[self.disc]
    self.clock = beatclock.new(d.map.bpm, d.map.firstBeat, AUDIO_OFFSET)
    self.state = rules.new(d.map)
    setString(self, 'discTitle', d.title)
    setString(self, 'discSleeve', d.sleeve)
    local p = self.discProp
    if p ~= nil then
        p.value = self.disc
    end
    local c = self.discColor
    if c ~= nil then
        c.value = d.color
    end
    if preview then
        startPreview(self)
    end
end

local function flipDisc(self: World, dir: number)
    selectDisc(self, self.disc + dir, true)
    fire(self.discFire)
end

local function setPaused(self: World, paused: boolean)
    self.paused = paused
    local p = self.pausedProp
    if p ~= nil then
        p.value = paused
    end
end

local function startSong(self: World)
    stopPreview(self)
    setPaused(self, false)
    self.resumeAt = 0
    self.state = rules.new(self.map)
    self.gest = gesture.new()
    self.pulses = newPulses()
    setMode(self, 'playing')
    self.beatIdx = -1
    setString(self, 'scoreText', '0')
    setString(self, 'multText', 'x1')
    setString(self, 'promptText', '')
    self.burstAt = -100
    self.burstIdx = 1
    self.trailLevel = 0
    self.prevCombo = 0
    self.breakAt = -100
    self.shards = {}
    self.histBeat = {}
    self.histX = {}
    self.hitAt = -100
    stopSong(self)
    self.useAudioClock = false
    self.songStart = self.time + START_DELAY
    local src = self.source
    if src ~= nil then
        self.audioStart = Audio.time() + START_DELAY
        self.sound = Audio.playAtTime(src, self.audioStart)
        self.useAudioClock = self.sound ~= nil
        self.lastAudio = Audio.time()
        self.audioIdle = 0
    end
    print(string.format('song start: disc %d (%s)  audio=%s', self.disc, discs.list[self.disc].title, tostring(self.useAudioClock)))
end

local function endSong(self: World, mode: Mode)
    local s = self.sound
    if s ~= nil and mode == 'over' then
        s:stop(0.3)
    end
    local st = self.state
    local summary: hudtext.Summary = {
        over = mode == 'over',
        score = st.score,
        perfect = st.perfect,
        good = st.good,
        candies = st.candies,
        totalCandies = st.totalCandies,
        maxCombo = st.maxCombo,
        grade = rules.grade(st),
    }
    setString(self, 'resultTitle', hudtext.resultTitle(summary))
    setString(self, 'gradeText', hudtext.gradeText(summary))
    setString(self, 'statsText', hudtext.stats(summary))
    setString(self, 'againText', hudtext.again(summary))
    setString(self, 'promptText', '')
    self.endAt = self.time
    setMode(self, mode)
    if mode == 'over' then
        playSfx(self.sfx.hit, 1)
    end
    print(string.format('%s: score %d  grade %s  candy %d/%d  perfect %d good %d  hits %d  pings %d  max combo %d',
        mode, st.score, summary.grade, st.candies, st.totalCandies, st.perfect, st.good, st.hits, st.pings, st.maxCombo))
end

-- Back to the record shelf (from the pause menu or a finished song).
local function toMenu(self: World)
    stopSong(self)
    setPaused(self, false)
    self.resumeAt = 0
    setString(self, 'promptText', '')
    selectDisc(self, self.disc, false)
    setMode(self, 'ready')
    self.menuGest = gesture.new()
    startPreview(self)
end

local function pauseSong(self: World)
    self.pausedSong = songNow(self)
    self.resumeAt = 0
    local s = self.sound
    if s ~= nil then
        s:pause()
    end
    stopPending(self)
    self.gest = gesture.new()
    setString(self, 'promptText', '')
    setPaused(self, true)
end

-- Resume: the overlay closes, a short count-in, then the song continues.
local function resumeSong(self: World)
    setPaused(self, false)
    self.resumeAt = self.time + COUNTDOWN_BEATS * beatclock.beatLen(self.clock)
end

local function countdownTick(self: World)
    local left = self.resumeAt - self.time
    if left > 0 then
        setString(self, 'promptText', tostring(math.ceil(left / beatclock.beatLen(self.clock))))
        return
    end
    self.resumeAt = 0
    setString(self, 'promptText', '')
    local s = self.sound
    if s ~= nil then
        s:resume()
    end
    self.audioStart = Audio.time() - self.pausedSong
    self.songStart = self.time - self.pausedSong
    self.lastAudio = Audio.time()
    self.audioIdle = 0
end

-- --------------------------------------------------------------------- input

local function showJudge(self: World, text: string)
    setString(self, 'judgeText', text)
    fire(self.judgeFire)
end

local function handle(self: World, ev: gesture.GestureEvent)
    local st = self.state
    if ev.kind == 'swipe' then
        rules.swipe(st, ev.dir, beatclock.beatAt(self.clock, ev.t))
        return
    end
    -- tap = manual ping: a small reveal around the bat
    if rules.ping(st) then
        addPulse(self, PING_STRENGTH, 1, PING_BEATS)
        playSfx(self.sfx.pingGood, 0.45)
    end
end

-- Play a music-box note exactly on `beat` when the audio clock allows, else now.
local function playNote(self: World, midi: number, beat: number, volume: number)
    local src = self.notes[midi]
    if src ~= nil then
        playAt(self, src, self.audioStart + beatclock.timeOf(self.clock, beat), volume)
    end
end

-- Candy caught: the sonar fires on its beat, and the candy sings a note of the
-- chord playing at that moment (the streak walks the arpeggio). In the frost the
-- reveal lingers and the note rings an octave up, softer.
local function onCatch(self: World, c: rules.Catch)
    local st = self.state
    local map = self.map
    local frost = beatmap.frostAt(map, c.beat)
    local strength = CANDY_STRENGTH
    local beats = CANDY_BEATS * (1 + frost)
    local note = harmony.noteFor(map, c.beat, st.combo)
    local gain = 1 - 0.35 * frost
    if frost > 0.5 and self.notes[note + 12] ~= nil then
        note += 12
    end
    if c.judgement == 'perfect' then
        addPulse(self, strength, 0, beats)
        playNote(self, note, c.beat, 0.9 * gain)
        playNote(self, harmony.above(map, c.beat, note), c.beat, 0.5 * gain)
        showJudge(self, hudtext.judge('perfect'))
    else
        addPulse(self, strength, 1, beats)
        playNote(self, note, c.beat, 0.8 * gain)
        if c.judgement == 'good' then
            showJudge(self, hudtext.judge('good'))
        end
    end
    setString(self, 'countText', hudtext.count(st.candies))
    fire(self.candyFire)
end

local function inPauseButton(self: World, p: Vector): boolean
    return p.x >= self.size.x - PAUSE_SIZE and p.y <= PAUSE_SIZE
end

local function inButton(self: World, p: Vector, cy: number): boolean
    return math.abs(p.x - self.size.x * 0.5) <= self.size.x * BUTTON_W
        and math.abs(p.y - self.size.y * cy) <= self.size.y * BUTTON_H
end

-- Title screen tap: the side strips of the shelf flip records, anywhere else plays.
local function menuTap(self: World)
    local p = self.menuPress
    local onShelf = p.y >= self.size.y * SHELF_TOP and p.y <= self.size.y * SHELF_BOTTOM
    if onShelf and p.x < self.size.x * ARROW_W then
        flipDisc(self, -1)
    elseif onShelf and p.x > self.size.x * (1 - ARROW_W) then
        flipDisc(self, 1)
    else
        startSong(self)
    end
end

-- Swipe left = the next record (the shelf slides left).
local function menuGesture(self: World, ev: gesture.GestureEvent?)
    if ev == nil then
        return
    end
    if ev.kind == 'swipe' then
        flipDisc(self, -ev.dir)
    else
        menuTap(self)
    end
end

local function pointerDown(self: World, event: PointerEvent)
    event:hit()
    if self.mode == 'ready' then
        self.menuPress = event.position
        gesture.press(self.menuGest, self.time, event.position.x)
        return
    end
    if self.mode ~= 'playing' then
        -- results: a lost run retries the disc, a finished one goes back to the shelf
        if self.time - self.endAt >= RESTART_GUARD then
            if self.mode == 'over' then
                startSong(self)
            else
                toMenu(self)
            end
        end
        return
    end
    if self.paused then
        if inButton(self, event.position, RESUME_Y) then
            resumeSong(self)
        elseif inButton(self, event.position, MENU_Y) then
            toMenu(self)
        end
        return
    end
    if inPauseButton(self, event.position) then
        if self.resumeAt == 0 then
            pauseSong(self)
        end
        return
    end
    if self.resumeAt > 0 then
        return
    end
    gesture.press(self.gest, songNow(self), event.position.x)
end

local function pointerMove(self: World, event: PointerEvent)
    if self.mode == 'ready' then
        event:hit()
        menuGesture(self, gesture.move(self.menuGest, self.time, event.position.x))
        return
    end
    if self.mode ~= 'playing' or self.paused or self.resumeAt > 0 then
        return
    end
    event:hit()
    local ev = gesture.move(self.gest, songNow(self), event.position.x)
    if ev ~= nil then
        handle(self, ev)
    end
end

local function pointerUp(self: World, event: PointerEvent)
    if self.mode == 'ready' then
        event:hit()
        menuGesture(self, gesture.release(self.menuGest, self.time, event.position.x))
        return
    end
    if self.mode ~= 'playing' or self.paused or self.resumeAt > 0 then
        return
    end
    event:hit()
    local ev = gesture.release(self.gest, songNow(self), event.position.x)
    if ev ~= nil then
        handle(self, ev)
    end
end

-- Keyboard: the same actions as touch.
--   shelf:   Left/Right (A/D) flip records, Enter/Space play
--   play:    Left/Right (A/D) swipe, Space pings, Esc/P pause
--   paused:  Esc/P/Enter/Space resume, M/Backspace main menu
--   results: Enter/Space as a tap (retry after RIP, shelf after a finish), Esc to the shelf
local function keyboardEvent(self: World, event: KeyboardEvent): boolean
    if event.phase ~= 'down' then
        return false -- no auto-repeat: one press, one lane
    end
    local k = event.key
    local dir = if k == KEY_LEFT or k == KEY_A then -1 elseif k == KEY_RIGHT or k == KEY_D then 1 else 0
    local confirm = k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE
    local pauseKey = k == KEY_ESCAPE or k == KEY_P

    if self.mode == 'ready' then
        if dir ~= 0 then
            flipDisc(self, dir)
        elseif confirm then
            startSong(self)
        else
            return false
        end
        return true
    end
    if self.mode ~= 'playing' then
        if not (confirm or k == KEY_ESCAPE) then
            return false
        end
        if self.time - self.endAt >= RESTART_GUARD then
            if self.mode == 'over' and confirm then
                startSong(self)
            else
                toMenu(self)
            end
        end
        return true
    end
    if self.paused then
        if pauseKey or confirm then
            resumeSong(self)
        elseif k == KEY_M or k == KEY_BACKSPACE then
            toMenu(self)
        else
            return false
        end
        return true
    end
    if self.resumeAt > 0 then
        return dir ~= 0 or confirm or pauseKey -- swallow keys during the count-in
    end
    if pauseKey then
        pauseSong(self)
    elseif dir ~= 0 then
        handle(self, { kind = 'swipe', t = songNow(self), dir = dir })
    elseif k == KEY_SPACE then
        handle(self, { kind = 'tap', t = songNow(self), dir = 0 })
    else
        return false
    end
    return true
end

-- ------------------------------------------------------------------- advance

-- Heartbeat where the song has no kick (beatmap.heartbeats), scheduled one beat
-- ahead on the audio clock.
local function scheduleHeartbeat(self: World, beat: number)
    local src = self.sfx.heartbeat
    if src == nil or not beatmap.heartbeatAt(self.map, beat) then
        return
    end
    if self.useAudioClock then
        playAt(self, src, self.audioStart + beatclock.timeOf(self.clock, beat), 0.9)
    elseif beat == math.floor(self.beat) then
        playSfx(src, 0.9)
    end
end

local onStreakBreak: (self: World, lost: number, byHit: boolean) -> ()

-- QA / demo: follow the candy trail, swiping ~0.3 beats before each candy.
-- Enabled by the private GameVM._autopilot flag (e.g. --data=_autopilot=true);
-- _autopilotUntil (beats, 0 = forever) hands control back, for testing streak breaks.
local function autopilot(self: World)
    local ap = self.autopilot
    if ap == nil or not ap.value then
        return
    end
    local untilProp = self.autopilotUntil
    if untilProp ~= nil and untilProp.value > 0 and self.beat >= untilProp.value then
        return
    end
    local st = self.state
    for i = st.first, #st.entities do
        local e = st.entities[i]
        if e.state == 0 and e.kind == 'candy' and e.beat >= self.beat - 0.1 then
            if e.lane ~= st.lane and self.beat >= e.beat - 0.3 and st.laneT >= 1 then
                rules.swipe(st, if e.lane > st.lane then 1 else -1, self.beat)
            end
            return
        end
    end
end

local function advance(self: World, seconds: number): boolean
    self.time += seconds
    if self.mode ~= 'playing' then
        -- idle: the street breathes on the beat (of the menu preview on the shelf)
        local idx = math.floor(self.time / beatclock.beatLen(self.clock))
        if self.mode == 'ready' then
            previewTick(self)
            idx = math.floor(beatclock.beatAt(self.clock, previewSongTime(self)))
        end
        if idx ~= self.beatIdx then
            self.beatIdx = idx
            addPulse(self, 0.8, 1, 1.5)
        end
        self.beat = 0
        return true
    end
    if self.paused then
        return true
    end
    if self.resumeAt > 0 then
        countdownTick(self)
        if self.resumeAt > 0 then
            return true
        end
    end
    prunePending(self)

    -- the audio clock must actually move; headless runs are silent
    if self.useAudioClock then
        local now = Audio.time()
        if now == self.lastAudio then
            self.audioIdle += seconds
            if self.audioIdle > 0.3 then
                print('audio clock stalled; using the frame clock')
                self.useAudioClock = false -- songStart already holds the frame-clock start
            end
        else
            self.audioIdle = 0
        end
        self.lastAudio = now
    end

    self.songTime = songNow(self)
    self.beat = beatclock.beatAt(self.clock, self.songTime)

    local ev = gesture.tick(self.gest, self.songTime)
    if ev ~= nil then
        handle(self, ev)
    end

    autopilot(self)
    local st = self.state
    local out = rules.update(st, self.beat, seconds)
    if out.hits > 0 then
        self.hitAt = self.time
        print(string.format('hit: %.3f s (beat %.2f), hp %d', self.time, self.beat, st.hp))
        playSfx(self.sfx.hit, 0.9)
    end
    for _, c in out.collected do
        onCatch(self, c)
    end
    if out.missed > 0 then
        showJudge(self, hudtext.judge('miss'))
    end
    -- streak broken while a trail was showing: shatter it (see onStreakBreak)
    if self.prevCombo >= TRAIL_T1 and st.combo == 0 then
        print(string.format('streak lost: x%d at %.3f s (beat %.2f)%s', self.prevCombo, self.time, self.beat, if out.hits > 0 then ' by a hit' else ''))
        onStreakBreak(self, self.prevCombo, out.hits > 0)
    end
    self.prevCombo = st.combo

    -- effects: bat history for the trail, color bursts on the music, streak level
    table.insert(self.histBeat, self.beat)
    table.insert(self.histX, rules.laneX(st))
    while #self.histBeat > 2 and self.histBeat[2] < self.beat - TRAIL_BEATS - 0.2 do
        table.remove(self.histBeat, 1)
        table.remove(self.histX, 1)
    end
    local bursts = self.map.bursts
    while self.burstIdx <= #bursts and self.beat >= bursts[self.burstIdx].beat do
        self.burstAt = self.time
        self.burstPower = bursts[self.burstIdx].power
        self.burstIdx += 1
    end
    local target = if st.combo >= TRAIL_T2 then 2 elseif st.combo >= TRAIL_T1 then 1 else 0
    local rate = if target < self.trailLevel then 8 else 3
    self.trailLevel += (target - self.trailLevel) * math.min(1, seconds * rate)

    setString(self, 'scoreText', hudtext.thousands(st.score))
    setString(self, 'multText', hudtext.mult(rules.multiplier(st.combo), st.combo))
    setString(self, 'promptText', hudtext.prompt(self.map, self.beat))

    local idx = math.floor(self.beat)
    if idx ~= self.beatIdx then
        if self.beatIdx == -1 then
            scheduleHeartbeat(self, idx) -- first beat of the song
        end
        self.beatIdx = idx
        scheduleHeartbeat(self, idx + 1)
        -- S3: compare the audio clock with the frame clock every 4 bars
        if idx >= 0 and idx % 16 == 0 then
            local frameClock = self.time - self.songStart
            local snd = self.sound
            print(string.format('S3 beat %3d  song %.3f  frame %.3f  diff %+.1f ms  sound %s  audioClock %s',
                idx, self.songTime, frameClock, (self.songTime - frameClock) * 1000,
                if snd ~= nil then string.format('%.3f', snd:time()) else '-', tostring(self.useAudioClock)))
        end
    end

    if st.over then
        endSong(self, 'over')
    elseif st.finished then
        endSong(self, 'done')
    end
    return true
end

-- ----------------------------------------------------------------- rendering

local function writeInst(b: buffer, i: number, x: number, y: number, z: number,
    w: number, h: number, r: number, g: number, bl: number, kind: number)
    local o = i * STRIDE
    buffer.writef32(b, o + 0, x)
    buffer.writef32(b, o + 4, y)
    buffer.writef32(b, o + 8, z)
    buffer.writef32(b, o + 12, w)
    buffer.writef32(b, o + 16, h)
    buffer.writef32(b, o + 20, r)
    buffer.writef32(b, o + 24, g)
    buffer.writef32(b, o + 28, bl)
    buffer.writef32(b, o + 32, 1)
    buffer.writef32(b, o + 36, kind)
end

local function fillWorld(self: World): number
    local b = self.instData
    local beat = self.beat
    local scroll = beat * TILE
    local n = 0
    writeInst(b, n, 0, 0, -25, 3 * LANE + 2.4, 60, 0.16, 0.13, 0.3, 1)
    n += 1
    for k = 0, 13 do
        local z = -(k * 4) + (scroll % 4)
        local tint = (k % 3) * 0.08
        writeInst(b, n, -3.6, 0, z, 2.4, 2.8, 0.45 + tint, 0.3, 0.6, 0)
        n += 1
        writeInst(b, n, 3.6, 0, z - 2, 2.4, 2.8, 0.35, 0.3 + tint, 0.55, 0)
        n += 1
    end
    local ents = self.state.entities
    local i = math.max(1, self.state.first - 8)
    while i <= #ents and n < MAX_INST do
        local e = ents[i]
        if e.beat > beat + LOOKAHEAD then
            break
        end
        if e.state == 0 or (e.state == 2 and e.beat > beat - 1) then
            local z = BAT_Z - (e.beat - beat) * TILE
            if e.kind == 'candy' then
                writeInst(b, n, e.lane * LANE, 0.35, z, 0.5, 0.5, 1.0, 0.55, 0.2, 2)
            else
                writeInst(b, n, e.lane * LANE, 0, z, 0.9, 1.0, 0.4, 0.8, 0.35, 3)
            end
            n += 1
        end
        i += 1
    end
    return n
end

local function build(self: World, context: Context)
    local W = math.max(1, math.floor(self.size.x * self.scale))
    local H = math.max(1, math.floor(self.size.y * self.scale))

    local scene = context:gpuCanvas({ width = W, height = H })
    local final = context:gpuCanvas({ width = W, height = H })
    local depth = GPUTexture.new({ width = W, height = H, format = 'depth32float', renderTarget = true, label = 'depth' })
    self.scene = scene
    self.final = final
    self.depthView = depth:view()

    local sceneShader = context:shader('shaders/scene')
    local sonarShader = context:shader('shaders/sonar')
    if sceneShader == nil or sonarShader == nil then
        print('world: shader missing')
        return
    end

    local scenePipe = GPUPipeline.new({
        vertex = sceneShader,
        fragment = sceneShader,
        vertexLayout = {
            {
                stride = STRIDE,
                stepMode = 'instance',
                attributes = {
                    { format = 'float32x3', slot = 0, offset = 0 },
                    { format = 'float32x2', slot = 1, offset = 12 },
                    { format = 'float32x4', slot = 2, offset = 20 },
                    { format = 'float32', slot = 3, offset = 36 },
                },
            },
        },
        colorTargets = { { format = scene.format } },
        depthStencil = { format = 'depth32float', compare = 'less', write = true },
    })
    local postPipe = GPUPipeline.new({
        vertex = sonarShader,
        fragment = sonarShader,
        vertexLayout = {},
        colorTargets = { { format = final.format } },
    })
    self.scenePipe = scenePipe
    self.postPipe = postPipe

    local camUBO = GPUBuffer.new({ size = 80, usage = 'uniform', label = 'cam' })
    local postUBO = GPUBuffer.new({ size = POST_SIZE, usage = 'uniform', label = 'post' })
    local instBuf = GPUBuffer.new({ size = MAX_INST * STRIDE, usage = 'vertex', label = 'inst' })
    self.camUBO = camUBO
    self.postUBO = postUBO
    self.instBuf = instBuf

    self.sceneBG = GPUBindGroup.new({
        layout = scenePipe:getBindGroupLayout(0),
        ubos = { { slot = 0, buffer = camUBO } },
    })
    self.postBG = GPUBindGroup.new({
        layout = postPipe:getBindGroupLayout(0),
        ubos = { { slot = 0, buffer = postUBO } },
        textures = {
            { slot = 1, view = scene:colorView() },
            { slot = 2, view = depth:view({ aspect = 'depth-only' }) },
        },
    })

    local proj = Mat4.perspective(math.rad(50), self.size.x / self.size.y, NEAR, FAR)
    local view = Mat4.lookAt(Vector.xyz(0, 3.4, 4.2), Vector.xyz(0, 0, -7), Vector.xyz(0, 1, 0))
    self.viewProj = proj * view
    self.invViewProj = self.viewProj:invert() or Mat4.identity()
end

local K = 0.5522847498
local function circle(p: Path, cx: number, cy: number, r: number)
    local k = r * K
    p:moveTo(Vector.xy(cx + r, cy))
    p:cubicTo(Vector.xy(cx + r, cy + k), Vector.xy(cx + k, cy + r), Vector.xy(cx, cy + r))
    p:cubicTo(Vector.xy(cx - k, cy + r), Vector.xy(cx - r, cy + k), Vector.xy(cx - r, cy))
    p:cubicTo(Vector.xy(cx - r, cy - k), Vector.xy(cx - k, cy - r), Vector.xy(cx, cy - r))
    p:cubicTo(Vector.xy(cx + k, cy - r), Vector.xy(cx + r, cy - k), Vector.xy(cx + r, cy))
    p:close()
end

-- Bat lane position `age` beats ago, from the recorded history.
local function laneAt(self: World, beat: number): number
    local hb = self.histBeat
    local hx = self.histX
    local n = #hb
    if n == 0 then
        return rules.laneX(self.state)
    end
    if beat <= hb[1] then
        return hx[1]
    end
    for i = n, 2, -1 do
        if hb[i - 1] <= beat then
            local span = hb[i] - hb[i - 1]
            local t = if span > 0 then (beat - hb[i - 1]) / span else 1
            return hx[i - 1] + (hx[i] - hx[i - 1]) * math.clamp(t, 0, 1)
        end
    end
    return hx[n]
end

local function project(self: World, x: number, y: number, z: number): Vector
    local ndc = self.viewProj:transformPoint(x, y, z)
    return Vector.xy((ndc.x * 0.5 + 0.5) * self.size.x, (1 - (ndc.y * 0.5 + 0.5)) * self.size.y)
end

-- One ribbon: segments streaming from the bat toward the camera, fading out.
local function ribbon(self: World, renderer: Renderer, first: number, offset: number, alpha: number,
    width: number, wave: number, palette: { Color })
    if alpha <= 0.01 then
        return
    end
    local paint = self.trailPaint
    local prev: Vector? = nil
    for k = 0, TRAIL_SEG do
        local age = k / TRAIL_SEG * TRAIL_BEATS
        local x = laneAt(self, self.beat - age) * LANE + offset
        local y = 0.62 + wave * math.sin(self.time * 11 - age * 7) * (age / TRAIL_BEATS)
        local z = BAT_Z + age * TILE
        local pt = project(self, x, y, z)
        if prev ~= nil and k >= 1 then
            local f = (k - 1) / TRAIL_SEG
            local path = self.trailPaths[first + k - 1]
            path:moveTo(prev)
            path:lineTo(pt)
            local c = palette[math.min(#palette, 1 + math.floor(f * #palette))]
            local a = alpha * (1 - f) ^ 1.1
            paint.color = Color.rgba(Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number, math.floor(255 * a))
            paint.thickness = width * (1 - f * 0.7)
            paint.feather = 2 + width * 0.6
            renderer:drawPath(path, paint)
        end
        prev = pt
    end
end

local LIGHT: { Color } = { Color.rgb(200, 240, 255), Color.rgb(159, 232, 255), Color.rgb(120, 160, 255) }
local WINGS: { Color } = { Color.rgb(255, 180, 90), Color.rgb(255, 111, 181), Color.rgb(190, 110, 255), Color.rgb(120, 140, 255) }

local function drawTrail(self: World, renderer: Renderer)
    for _, p in self.trailPaths do
        p:reset()
    end
    if self.mode ~= 'playing' then
        return
    end
    local lvl = self.trailLevel
    local light = math.clamp(lvl, 0, 1)
    local wings = math.clamp(lvl - 1, 0, 1)
    -- in the Cold Moon freeze the wing trails turn to ice too
    local palette = if beatmap.frostAt(self.map, self.beat) > 0.5 then LIGHT else WINGS
    ribbon(self, renderer, 1, 0, light * (1 - wings * 0.4), 7, 0.02, LIGHT)
    ribbon(self, renderer, 1 + TRAIL_SEG, -WING, wings, 12, 0.12, palette)
    ribbon(self, renderer, 1 + TRAIL_SEG * 2, WING, wings, 12, 0.12, palette)
    -- sparkles along the wing trails
    if wings > 0.05 then
        local paint = self.paint
        for i = 1, SPARKLES do
            local seed = i * 1.7
            local age = ((self.time * 0.9 + seed * 0.37) % 1) * TRAIL_BEATS
            local side = if i % 2 == 0 then WING else -WING
            local x = laneAt(self, self.beat - age) * LANE + side + math.sin(seed * 3.1) * 0.15
            local pt = project(self, x, 0.66 + math.sin(seed) * 0.12, BAT_Z + age * TILE)
            local tw = 0.5 + 0.5 * math.sin(self.time * 9 + seed * 5)
            local path = self.trailPaths[TRAIL_SEG * 3 + i]
            circle(path, pt.x, pt.y, 1.5 + 1.5 * tw)
            paint.color = Color.rgba(255, 245, 220, math.floor(255 * wings * tw * (1 - age / TRAIL_BEATS)))
            renderer:drawPath(path, paint)
        end
    end
end

-- The streak breaks: the trail shatters into falling shards, the screen goes cold
-- with a refracting shockwave (sonar.wgsl fx2), a power-down sound plays and the top
-- pop-up shows the streak that was lost. After a garlic hit the cold drain and the
-- sound wait BREAK_AFTER_HIT so the red hit flash reads first.
local BREAK_AFTER_HIT = 0.3

function onStreakBreak(self: World, lost: number, byHit: boolean)
    local power = if lost >= TRAIL_T2 then 1.0 else 0.6
    local delay = if byHit then BREAK_AFTER_HIT else 0
    self.breakAt = self.time + delay
    self.breakPower = power
    local snd = self.sfx.streakBreak
    if snd ~= nil then
        local s = if delay > 0 then Audio.playInTime(snd, delay) else Audio.play(snd)
        if s ~= nil then
            s.volume = 0.8
        end
    end
    setString(self, 'countText', 'x' .. tostring(lost) .. ' streak lost!')
    fire(self.candyFire)

    local shards: { Shard } = {}
    local wings = self.trailLevel > 1.2
    local count = if wings then SHARDS else math.floor(SHARDS / 2)
    for i = 1, count do
        local seed = i * 12.9898 + self.time
        local r1 = (math.sin(seed) * 43758.5453) % 1
        local r2 = (math.sin(seed * 1.7) * 24634.6345) % 1
        local age = (i - 1) / count * TRAIL_BEATS
        local side = 0
        local palette = LIGHT
        if wings then
            side = if i % 3 == 0 then 0 elseif i % 3 == 1 then -WING else WING
            palette = if side == 0 then LIGHT else WINGS
        end
        local x = laneAt(self, self.beat - age) * LANE + side
        local pt = project(self, x, 0.62, BAT_Z + age * TILE)
        local c = palette[1 + (i % #palette)]
        table.insert(shards, {
            x = pt.x,
            y = pt.y,
            vx = (r1 - 0.5) * 340,
            vy = -120 - r2 * 160,
            spin = (r2 - 0.5) * 14,
            size = 5 + r1 * 6 * power,
            color = c,
            born = self.time,
        })
    end
    self.shards = shards
end

local function drawShards(self: World, renderer: Renderer)
    local paint = self.paint
    for i, sh in self.shards do
        local path = self.shardPaths[i]
        path:reset()
        local t = self.time - sh.born
        if t >= 0 and t < SHARD_LIFE and i <= SHARDS then
            local x = sh.x + sh.vx * t
            local y = sh.y + sh.vy * t + 0.5 * SHARD_GRAVITY * t * t
            local a = sh.spin * t
            local r = sh.size * (1 - t / SHARD_LIFE * 0.4)
            local cx = math.cos(a) * r
            local sx = math.sin(a) * r
            path:moveTo(Vector.xy(x + cx, y + sx))
            path:lineTo(Vector.xy(x - sx * 0.5, y + cx * 0.5))
            path:lineTo(Vector.xy(x - cx, y - sx))
            path:lineTo(Vector.xy(x + sx * 0.5, y - cx * 0.5))
            path:close()
            local alpha = 1 - t / SHARD_LIFE
            paint.color = Color.rgba(Color.red(sh.color) :: number, Color.green(sh.color) :: number,
                Color.blue(sh.color) :: number, math.floor(255 * alpha))
            renderer:drawPath(path, paint)
        end
    end
end

local function drawHud(self: World, renderer: Renderer, bx: number, by: number)
    local w = self.size.x
    local paths = self.paths
    for _, p in paths do
        p:reset()
    end

    -- bat placeholder (blinks while invulnerable)
    local st = self.state
    local blink = self.mode == 'playing' and self.beat < st.invulnUntil and math.floor(self.time * 12) % 2 == 0
    local onResults = self.mode == 'over' or self.mode == 'done'
    if not blink and not onResults then
        local p = paths[1]
        p:moveTo(Vector.xy(bx - 26, by))
        p:lineTo(Vector.xy(bx - 10, by - 10))
        p:lineTo(Vector.xy(bx, by - 4))
        p:lineTo(Vector.xy(bx + 10, by - 10))
        p:lineTo(Vector.xy(bx + 26, by))
        p:lineTo(Vector.xy(bx, by + 12))
        p:close()
        self.paint.color = if self.time - self.hitAt < 0.3 then Color.rgb(255, 255, 255) else Color.rgb(255, 77, 109)
        renderer:drawPath(p, self.paint)
    end

    -- hp pips, top right beside the pause button (in game only)
    for i = 1, if self.mode == 'playing' then rules.MAX_HP else 0 do
        local p = paths[1 + i]
        circle(p, w - PAUSE_SIZE - 14 - (i - 1) * 26, 38, 9)
        self.paint.color = if i <= st.hp then Color.rgb(255, 77, 109) else Color.rgb(60, 50, 90)
        renderer:drawPath(p, self.paint)
    end
end

local function draw(self: World, renderer: Renderer)
    local scene = self.scene
    local final = self.final
    local scenePipe = self.scenePipe
    local postPipe = self.postPipe
    local sceneBG = self.sceneBG
    local postBG = self.postBG
    local camUBO = self.camUBO
    local postUBO = self.postUBO
    local instBuf = self.instBuf
    local depthView = self.depthView
    if scene == nil or final == nil or scenePipe == nil or postPipe == nil or sceneBG == nil
        or postBG == nil or camUBO == nil or postUBO == nil or instBuf == nil or depthView == nil then
        return
    end

    self.viewProj:writeToBuffer(self.camData, 0)
    buffer.writef32(self.camData, 64, self.beat * TILE)
    buffer.writef32(self.camData, 68, self.time)
    camUBO:write(self.camData)

    local n = fillWorld(self)
    instBuf:write(self.instData, 0, 0, n * STRIDE)

    local laneX = rules.laneX(self.state)
    local ndc = self.viewProj:transformPoint(laneX * LANE, 0.6, BAT_Z)
    local W = scene.width
    local H = scene.height
    local bx = (ndc.x * 0.5 + 0.5) * W
    local by = (1 - (ndc.y * 0.5 + 0.5)) * H

    local pd = self.postData
    local playing = self.mode == 'playing'
    -- Cold Moon frost (disc 2's breakdown), in seconds for the shader
    local frost, crackCount, sinceShatter = 0, 0, -1
    local shatterAge, crackAge = -1, 10
    local ice = self.map.ice
    if playing and ice ~= nil then
        frost, crackCount, sinceShatter = beatmap.frostAt(self.map, self.beat)
        local bl = beatclock.beatLen(self.clock)
        if sinceShatter >= 0 and sinceShatter * bl < 1.5 then
            shatterAge = sinceShatter * bl
            frost = 1
        end
        for _, cb in ice.cracks do
            if self.beat >= cb then
                crackAge = (self.beat - cb) * bl
            end
        end
    end
    buffer.writef32(pd, 0, W)
    buffer.writef32(pd, 4, H)
    buffer.writef32(pd, 8, self.time)
    buffer.writef32(pd, 12, if playing then self.beat * TILE else self.time * 2)
    buffer.writef32(pd, 16, bx)
    buffer.writef32(pd, 20, by)
    buffer.writef32(pd, 24, NEAR)
    buffer.writef32(pd, 28, FAR)
    buffer.writef32(pd, 32, H * 1.6)
    buffer.writef32(pd, 36, if playing then beatmap.fogAt(self.map, self.beat) else 0)
    buffer.writef32(pd, 40, 0)
    buffer.writef32(pd, 44, CLASS_TINT)
    buffer.writef32(pd, 48, FOG_TOP)
    buffer.writef32(pd, 52, FOG_DENSITY)
    buffer.writef32(pd, 56, CHROMA)
    buffer.writef32(pd, 60, frost)
    for i, p in self.pulses do
        local o = 64 + (i - 1) * 16
        buffer.writef32(pd, o + 0, p.start)
        buffer.writef32(pd, o + 4, p.strength)
        buffer.writef32(pd, o + 8, p.kind)
        buffer.writef32(pd, o + 12, p.life)
    end
    self.invViewProj:writeToBuffer(pd, 128)
    buffer.writef32(pd, 192, self.time - self.hitAt)
    buffer.writef32(pd, 196, self.time - self.burstAt)
    buffer.writef32(pd, 200, self.burstPower)
    buffer.writef32(pd, 204, crackCount)
    buffer.writef32(pd, 208, self.time - self.breakAt)
    buffer.writef32(pd, 212, self.breakPower)
    buffer.writef32(pd, 216, shatterAge)
    buffer.writef32(pd, 220, crackAge)
    postUBO:write(pd)

    local pass = scene:beginRenderPass({
        color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
        depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'store', depthClearValue = 1 },
    })
    pass:setPipeline(scenePipe)
    pass:setBindGroup(0, sceneBG)
    pass:setVertexBuffer(0, instBuf)
    pass:draw(6, n)
    pass:finish()

    local post = final:beginRenderPass({
        color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } },
    })
    post:setPipeline(postPipe)
    post:setBindGroup(0, postBG)
    post:draw(3)
    post:finish()

    -- camera shake when a life is lost
    local shake = 0
    local sinceHit = self.time - self.hitAt
    if sinceHit < 0.5 then
        shake = 12 * math.exp(-sinceHit * 9)
    end
    local jx = math.sin(self.time * 97.3) * shake
    local jy = math.cos(self.time * 83.1) * shake

    renderer:save()
    renderer:transform(Mat2D.withTranslation(jx, jy))
    renderer:save()
    renderer:transform(Mat2D.withScale(1 / self.scale))
    renderer:drawImage(final.image, self.sampler, 'srcOver', 1)
    renderer:restore()
    drawTrail(self, renderer)
    drawShards(self, renderer)
    drawHud(self, renderer, bx / self.scale, by / self.scale)
    renderer:restore()
end

-- ------------------------------------------------------------------ lifecycle

local STRING_PROPS = {
    'scoreText', 'multText', 'judgeText', 'countText', 'promptText',
    'resultTitle', 'gradeText', 'statsText', 'againText', 'discTitle', 'discSleeve',
}

local function init(self: World, context: Context): boolean
    self.context = context
    for i, d in discs.list do
        local src = context:audio(d.audio)
        if src ~= nil then
            self.sources[i] = src
        else
            print('world: audio asset ' .. d.audio .. ' not found')
        end
    end
    self.source = self.sources[self.disc]
    self.sfx = {
        streakBreak = context:audio('streak_break'),
        heartbeat = context:audio('heartbeat'),
        pingPerfect = context:audio('ping_perfect'),
        pingGood = context:audio('ping_good'),
        pingGlitch = context:audio('ping_glitch'),
        candy = context:audio('candy'),
        hit = context:audio('hit'),
    }
    for _, m in harmony.NOTES do
        local src = context:audio('note_' .. tostring(m))
        if src ~= nil then
            self.notes[m] = src
        else
            print('world: note_' .. tostring(m) .. ' missing')
        end
    end
    -- init runs twice; the view model is only present the second time
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.vm = vm
    for _, name in STRING_PROPS do
        local p = vm:getString(name)
        if p ~= nil then
            self.strings[name] = p
        else
            print('world: GameVM.' .. name .. ' missing')
        end
    end
    self.modeProp = vm:getNumber('mode')
    self.discProp = vm:getNumber('disc')
    self.discColor = vm:getColor('discColor')
    self.pausedProp = vm:getBoolean('paused')
    self.discFire = vm:getTrigger('discFire')
    self.autopilot = vm:getBoolean('_autopilot')
    self.autopilotUntil = vm:getNumber('_autopilotUntil')
    self.judgeFire = vm:getTrigger('judgeFire')
    self.candyFire = vm:getTrigger('candyFire')
    setMode(self, self.mode)
    selectDisc(self, self.disc, true)
    return true
end

local function resize(self: World, size: Vector, scale: number)
    self.size = size
    self.scale = scale
    local ctx = self.context
    if ctx ~= nil and size.x > 0 and size.y > 0 then
        build(self, ctx)
    end
end

return function(context: Context): Layout<World>
    local paths: { Path } = {}
    for i = 1, 6 do
        paths[i] = Path.new()
    end
    local shardPaths: { Path } = {}
    for i = 1, SHARDS do
        shardPaths[i] = Path.new()
    end
    local trailPaths: { Path } = {}
    for i = 1, TRAIL_SEG * 3 + SPARKLES do
        trailPaths[i] = Path.new()
    end
    return {
        burstAt = -100,
        burstPower = 0,
        burstIdx = 1,
        trailLevel = 0,
        histBeat = {},
        histX = {},
        trailPaths = trailPaths,
        prevCombo = 0,
        breakAt = -100,
        breakPower = 0,
        shards = {},
        shardPaths = shardPaths,
        trailPaint = Paint.with({ style = 'stroke', cap = 'round', join = 'round', thickness = 4, feather = 3, blendMode = 'screen' }),
        context = nil,
        size = Vector.xy(0, 0),
        scale = 1,
        scene = nil,
        final = nil,
        depthView = nil,
        scenePipe = nil,
        postPipe = nil,
        sceneBG = nil,
        postBG = nil,
        camUBO = nil,
        postUBO = nil,
        instBuf = nil,
        camData = buffer.create(80),
        postData = buffer.create(POST_SIZE),
        instData = buffer.create(MAX_INST * STRIDE),
        viewProj = Mat4.identity(),
        invViewProj = Mat4.identity(),
        sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
        disc = 1,
        map = discs.list[1].map,
        sources = {},
        preview = nil,
        previewStart = 0,
        pending = {},
        menuGest = gesture.new(),
        menuPress = Vector.xy(0, 0),
        paused = false,
        pausedSong = 0,
        resumeAt = 0,
        clock = beatclock.new(discs.list[1].map.bpm, discs.list[1].map.firstBeat, AUDIO_OFFSET),
        source = nil,
        sound = nil,
        audioStart = 0,
        songStart = 0,
        lastAudio = 0,
        audioIdle = 0,
        useAudioClock = false,
        mode = 'ready',
        time = 0,
        songTime = 0,
        beat = 0,
        beatIdx = -1,
        gest = gesture.new(),
        state = rules.new(discs.list[1].map),
        pulses = newPulses(),
        pulseNext = 1,
        hitAt = -100,
        endAt = -100,
        vm = nil,
        strings = {},
        lastStrings = {},
        modeProp = nil,
        discProp = nil,
        discColor = nil,
        pausedProp = nil,
        discFire = nil,
        autopilot = nil,
        autopilotUntil = nil,
        judgeFire = nil,
        candyFire = nil,
        sfx = {},
        notes = {},
        paint = Paint.with({ color = Color.rgb(255, 77, 109) }),
        paths = paths,
        init = init,
        resize = resize,
        advance = advance,
        draw = draw,
        pointerDown = pointerDown,
        pointerMove = pointerMove,
        pointerUp = pointerUp,
        keyboardEvent = keyboardEvent,
    }
end
