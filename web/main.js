// Local web harness for signed .riv builds (see scripts/web-dev.sh).
// Query params: ?src=/path/to/file.riv[&sm=State%20Machine%201][&artboard=Name]
(() => {
  const params = new URLSearchParams(location.search);
  const src = params.get("src") || "/game/build/count-echula.riv";
  const stateMachine = params.get("sm") || undefined; // default: the file's first state machine
  const artboard = params.get("artboard") || undefined;

  const canvas = document.getElementById("canvas");
  const hud = document.getElementById("hud");
  const errors = document.getElementById("errors");

  const info = { loaded: "loading…", note: "" };

  // Surface errors on screen: there is no devtools console on a phone.
  function showError(msg) {
    errors.style.display = "block";
    errors.textContent += msg + "\n";
  }
  window.addEventListener("error", (e) => showError(`JS: ${e.message}`));
  window.addEventListener("unhandledrejection", (e) => showError(`Promise: ${e.reason}`));
  // Expected with autoBind on files without a view model (e.g. spikes): a note, not an error.
  const NOTES = [/Could not find a View Model linked to Artboard/];
  for (const level of ["warn", "error"]) {
    const orig = console[level].bind(console);
    console[level] = (...args) => {
      orig(...args);
      const msg = args.join(" ");
      if (NOTES.some((re) => re.test(msg))) info.note = "no view model";
      else showError(`${level}: ${msg}`);
    };
  }

  const r = new rive.Rive({
    src: `${src}?t=${Date.now()}`, // bust cache on every reload
    canvas,
    artboard,
    stateMachine,
    autoplay: true,
    autoBind: true,
    enableGPUCanvas: true,
    useOffscreenRenderer: false,
    layout: new rive.Layout({ fit: rive.Fit.Contain, alignment: rive.Alignment.Center }),
    onLoad: () => {
      r.resizeDrawingSurfaceToCanvas();
      if (!stateMachine && r.stateMachineNames?.length) r.play(r.stateMachineNames[0]);
      info.loaded = `${src.split("/").pop()} ✓`;
    },
    onLoadError: (e) => showError(`Rive load error: ${e?.data ?? e}`),
  });

  const ro = new ResizeObserver(() => r.resizeDrawingSurfaceToCanvas());
  ro.observe(canvas);

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
        `${canvas.width}×${canvas.height} @${devicePixelRatio}x  webgl2 2.44.0`;
      frames = 0; worst = 0; last = now;
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
