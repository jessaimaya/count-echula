// Anonymous play stats for the hosted build (deploy/api.py stores them, /stats shows
// them). Only on with <body data-analytics="1"> (scripts/deploy-railway.sh sets it), so
// the local harness sends nothing. No cookies: a random visitor id in localStorage
// (counts returning players), a random session id per tab. Reads the game's view model
// (mode, disc, score, grade) the same way the corner readout does.
(() => {
  if (document.body.dataset.analytics !== "1") return;
  const ENDPOINT = "/api/event";
  const HEARTBEAT_MS = 15000;
  const MODE = { 0: "ready", 1: "playing", 2: "over", 3: "done" };

  const rand = () => Math.random().toString(36).slice(2, 12);
  let vid = null;
  try {
    vid = localStorage.getItem("echula.vid");
    if (!vid) localStorage.setItem("echula.vid", (vid = rand()));
  } catch {}
  let sid = null;
  try {
    sid = sessionStorage.getItem("echula.sid");
    if (!sid) sessionStorage.setItem("echula.sid", (sid = rand()));
  } catch {}
  sid = sid || rand();

  function send(type, data = {}) {
    const body = JSON.stringify({ type, sid, vid, t: Date.now(), data });
    // sendBeacon survives the page closing; fetch keepalive is the fallback
    if (navigator.sendBeacon?.(ENDPOINT, new Blob([body], { type: "application/json" }))) return;
    fetch(ENDPOINT, { method: "POST", body, keepalive: true, headers: { "Content-Type": "application/json" } }).catch(() => {});
  }

  send("session_start", {
    ref: document.referrer ? new URL(document.referrer).hostname : "",
    w: screen.width, h: screen.height, dpr: devicePixelRatio,
    touch: matchMedia("(pointer: coarse)").matches,
    lang: navigator.language,
  });

  // Heartbeats while the page is visible: session length and active time.
  setInterval(() => {
    if (document.visibilityState === "visible") send("heartbeat");
  }, HEARTBEAT_MS);

  // Song lifecycle from the view model's mode: ready -> playing -> over/done (or back to
  // ready when the player quits from the pause menu).
  const vm = () => window.rive_?.viewModelInstance;
  const read = (kind, name) => { try { return vm()?.[kind](name)?.value; } catch { return undefined; } };
  let mode = null;
  let song = null; // { disc, start, pausedMs, pausedAt }
  let pending = null; // an ended song waiting for its grade

  function flushEnded() {
    if (!pending) return;
    pending.grade = read("string", "gradeText") || "";
    send("song_end", pending);
    pending = null;
  }
  function endSong(result) {
    if (!song) return;
    const now = performance.now();
    if (song.pausedAt) song.pausedMs += now - song.pausedAt;
    flushEnded();
    pending = {
      disc: song.disc, result,
      secs: Math.round((now - song.start - song.pausedMs) / 1000),
      score: Number(String(read("string", "scoreText") || "0").replace(/\D/g, "")) || 0,
    };
    song = null;
    if (result === "left") return flushEnded();
    // the grade stamps in after the results count up
    setTimeout(flushEnded, 4000);
  }

  setInterval(() => {
    const m = MODE[read("number", "mode")];
    if (!m) return;
    if (song) {
      const paused = !!read("boolean", "paused") || document.visibilityState !== "visible";
      if (paused && !song.pausedAt) song.pausedAt = performance.now();
      if (!paused && song.pausedAt) { song.pausedMs += performance.now() - song.pausedAt; song.pausedAt = 0; }
    }
    if (m === mode) return;
    const was = mode;
    mode = m;
    if (m === "playing") {
      flushEnded();
      song = { disc: read("string", "discTitle") || "?", start: performance.now(), pausedMs: 0, pausedAt: 0 };
      send("song_start", { disc: song.disc, retry: was === "over" || was === "done" });
    } else if (was === "playing") {
      endSong(m === "ready" ? "quit" : m);
    }
  }, 250);

  // Closing the tab mid-song or on the results still reports the song.
  window.addEventListener("pagehide", () => {
    if (song) endSong("left");
    else flushEnded();
    send("session_end");
  });
})();
