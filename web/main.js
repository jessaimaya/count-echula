// Local web harness for signed .riv builds (see scripts/web-dev.sh).
// Query params: ?src=/path/to/file.riv[&sm=State%20Machine%201][&artboard=Name][&probe=ms]
(() => {
  const params = new URLSearchParams(location.search);
  const src = params.get("src") || "/game/build/count-echula.riv";
  const stateMachine = params.get("sm") || undefined; // default: the file's first state machine
  const artboard = params.get("artboard") || undefined;
  const autoBind = true;

  const canvas = document.getElementById("canvas");
  const hud = document.getElementById("hud");
  // The corner readout: on by default here; the deployed test build sets
  // <body data-hud="0"> (scripts/deploy-railway.sh), and ?hud=1 / ?hud=0 override.
  if ((params.get("hud") ?? document.body.dataset.hud ?? "1") === "0") hud.style.display = "none";
  const errors = document.getElementById("errors");

  const info = { loaded: "loading…", note: "" };

  // Surface errors on screen: there is no devtools console on a phone.
  function showError(msg) {
    errors.style.display = "block";
    errors.textContent += msg + "\n";
  }
  errors.addEventListener("click", () => {
    errors.style.display = "none";
    errors.textContent = "";
  });
  window.addEventListener("error", (e) => showError(`JS: ${e.message}`));
  window.addEventListener("unhandledrejection", (e) => showError(`Promise: ${e.reason}`));
  // Expected messages: notes in the corner readout, not errors.
  const NOTES = [
    [/Could not find a View Model linked to Artboard/, "no view model"],
    // the GPU has no pixel-interlock mode: the renderer falls back to 4x MSAA (fine)
    [/no interlock mode supports this frame/, "MSAA fallback"],
  ];
  for (const level of ["warn", "error"]) {
    const orig = console[level].bind(console);
    console[level] = (...args) => {
      orig(...args);
      const msg = args.join(" ");
      const note = NOTES.find(([re]) => re.test(msg));
      if (note) info.note = note[1];
      else showError(`${level}: ${msg}`);
    };
  }

  // Phones: Rive keeps keyboard focus in a hidden <input> (the World layout takes key
  // events), and focusing it on a tap would raise the on-screen keyboard. inputmode
  // "none" keeps the focus but never shows the keyboard.
  if (matchMedia("(pointer: coarse)").matches) {
    const quiet = (el) => el.setAttribute("inputmode", "none");
    document.querySelectorAll("input").forEach(quiet);
    new MutationObserver((records) => {
      for (const r of records)
        for (const n of r.addedNodes) {
          if (n instanceof HTMLInputElement) quiet(n);
          else if (n.querySelectorAll) n.querySelectorAll("input").forEach(quiet);
        }
    }).observe(document.body, { childList: true, subtree: true });
  }

  // We start the first state machine ourselves (onLoad), so the runtime's notice about
  // defaulting to the first linear animation does not apply.
  if (!stateMachine) rive.Rive.suppressDeprecationWarnings = ["default-state-machine"];

  const r = new rive.Rive({
    src: `${src}?t=${Date.now()}`, // bust cache on every reload
    canvas,
    artboard,
    stateMachine,
    // With no state machine named, autoplay would run the artboard's first *linear
    // animation* (and warn); in the game that is "Show Title", which then fights the
    // Flow machine and keeps the title on screen. onLoad starts the first machine instead.
    autoplay: !!stateMachine,
    autoBind,
    enableGPUCanvas: true,
    useOffscreenRenderer: false,
    // In single-touch mode the runtime locks onto the first finger until its touchend; on
    // iPhone Chrome that release can go missing and every later touch is dropped (no
    // swipes, no pause button). Multi-touch has no lock; the game treats any finger alike.
    enableMultiTouch: true,
    // Keyboard: the file focuses its World layout on every screen (FocusActionTarget);
    // this lets that pull browser focus onto the canvas so keys arrive without a click.
    focusOptions: { allowFocusInterrupt: true },
    layout: new rive.Layout({ fit: rive.Fit.Contain, alignment: rive.Alignment.Center }),
    onLoad: () => {
      r.resizeDrawingSurfaceToCanvas();
      canvas.focus({ preventScroll: true });
      if (!stateMachine && r.stateMachineNames?.length) {
        // Restart the artboard with its first state machine named, as if it had been
        // passed in. A machine started later with play() is never bound to the view
        // model, so its conditions never see GameVM and the title stays up in play.
        r.reset({ artboard, stateMachine: r.stateMachineNames[0], autoplay: true, autoBind });
      }
      info.loaded = `${src.split("/").pop()} ✓`;
    },
    onLoadError: (e) => showError(`Rive load error: ${e?.data ?? e}`),
  });

  // Keyboard play: a click on the letterbox must not take focus off the canvas (a canvas
  // blur clears Rive's focus and the keys go dead until the next click on the game).
  document.addEventListener("mousedown", (e) => {
    if (e.target !== canvas) e.preventDefault();
  });

  // Background (app closed, tab switched, screen locked): silence the audio and stop the
  // frame loop, or the music keeps playing and the GPU keeps drawing. Back in front, the
  // game gets a wake (GameVM.wakeCount): mid-song it opens its pause menu, so the audio
  // comes back a moment later, once the song is paused.
  let asleep = false;
  // Rive makes several; skip the ones it has already closed
  const audio = () => (window.__audioContexts || []).filter((ac) => ac.state !== "closed");
  function sleep() {
    if (asleep) return;
    asleep = true;
    for (const ac of audio()) ac.suspend().catch(() => {});
    r.pause();
  }
  function wake() {
    if (!asleep || document.hidden) return;
    asleep = false;
    r.play(); // resumes what pause() paused (the Flow machine)
    const count = r.viewModelInstance?.number("wakeCount");
    if (count) count.value += 1;
    // a timer, not animation frames: those can stall right after the page comes back
    setTimeout(() => {
      if (!asleep) for (const ac of audio()) ac.resume().catch(() => {});
    }, 120);
  }
  document.addEventListener("visibilitychange", () => (document.hidden ? sleep() : wake()));
  window.addEventListener("pagehide", sleep);
  window.addEventListener("pageshow", wake);

  // iOS only starts audio inside a user gesture. Rive unlocks its own context on some
  // events, but touchstart is default-prevented on the canvas, so make sure: every touch
  // or click resumes whatever is still suspended (unless the page is asleep).
  for (const type of ["touchend", "pointerup", "click", "keydown"])
    document.addEventListener(type, () => {
      if (asleep) return;
      for (const ac of audio()) if (ac.state !== "running") ac.resume().catch(() => {});
    }, { capture: true, passive: true });

  // Debug readout (?hud=1): touches reaching the canvas, audio and page state.
  const touches = { start: 0, end: 0, cancel: 0 };
  for (const k of Object.keys(touches))
    canvas.addEventListener(`touch${k}`, () => touches[k]++, { capture: true, passive: true });
  const pageState = () =>
    `\ntouch ${touches.start}/${touches.end}/${touches.cancel}  audio ${audio().map((ac) => ac.state).join(",") || "-"}` +
    `  ${document.visibilityState}${asleep ? " asleep" : ""}  focus ${document.activeElement?.tagName?.toLowerCase()}`;
  const ro = new ResizeObserver(() => r.resizeDrawingSurfaceToCanvas());
  ro.observe(canvas);

  window.rive_ = r; // for poking at it from devtools

  // What the bound view model instance holds (debug: is the script writing to it?)
  function vmReadout() {
    const vm = r.viewModelInstance;
    if (!vm) return `\nvm: none  sm=${r.playingStateMachineNames?.join(",") || "-"}`;
    const mode = vm.number("mode")?.value;
    const score = vm.string("scoreText")?.value;
    return `\nvm: mode=${mode} score=${score}  sm=${r.playingStateMachineNames?.join(",") || "-"}`;
  }

  // probe=1 (debug, headless runs): tap "Tap to play" after load, then report what the
  // bound view model says into <pre id="probe">, for `chrome --headless --dump-dom`.
  if (params.get("probe")) {
    const out = document.createElement("pre");
    out.id = "probe";
    document.body.appendChild(out);
    const log = (m) => (out.textContent += m + "\n");
    const tap = (fx, fy) => {
      const b = canvas.getBoundingClientRect();
      const o = { clientX: b.left + b.width * fx, clientY: b.top + b.height * fy, bubbles: true,
        pointerId: 1, pointerType: "mouse", isPrimary: true, button: 0 };
      for (const t of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"])
        canvas.dispatchEvent(t.startsWith("pointer") ? new PointerEvent(t, o) : new MouseEvent(t, o));
    };
    const at = (ms, f) => setTimeout(f, ms);
    rive.Rive.suppressDeprecationWarnings = [...(rive.Rive.suppressDeprecationWarnings || []), "state-change-events"];
    r.on(rive.EventType.StateChange, (e) => log(`state change: ${JSON.stringify(e.data)}`));
    const t0 = Number(params.get("probe")) > 1 ? Number(params.get("probe")) : 6000; // ms before the tap
    at(t0, () => { log(`before: ${vmReadout().trim()}`); tap(0.5, 0.76); log("tapped play"); });
    at(t0 + 3000, () => log(`after 3s: ${vmReadout().trim()}`));
  }

  // Frame-time readout (browser frames, not Rive internals) for phone perf checks.
  let frames = 0, last = performance.now(), worst = 0, prev = last;
  function tick(now) {
    frames++;
    worst = Math.max(worst, now - prev);
    prev = now;
    if (now - last >= 1000) {
      const fps = (frames * 1000) / (now - last);
      hud.textContent =
        `${info.loaded}${info.note ? `  (${info.note})` : ""}\n${fps.toFixed(0)} fps  worst ${worst.toFixed(1)} ms\n` +
        `${canvas.width}×${canvas.height} @${devicePixelRatio}x  webgl2 2.44.0` + vmReadout() + pageState();
      frames = 0; worst = 0; last = now;
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
