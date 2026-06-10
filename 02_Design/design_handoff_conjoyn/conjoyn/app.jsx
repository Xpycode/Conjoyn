// Conjoyn — main app: state machine + simulation + tweaks

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": ["#FFB23E", "#F0622A"],
  "density": "comfortable",
  "consoleOpen": false
}/*EDITMODE-END*/;

const SRC_PATH = "/Volumes/DJI_MAVIC4/DCIM/100MEDIA";
const DEST_PATH = "~/Movies/Ingest/2026-05-31";

function defaultSelection(recs) {
  const sel = {};
  recs.forEach(function (r) { sel[r.id] = r.split; });
  return sel;
}

function makeJob(rec, i) {
  return { id: "job-" + rec.id + "-" + i, rec: rec, status: "queued", pct: 0, attempts: 0 };
}

function ConjoynApp() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  const recs = window.CONJOYN_RECORDINGS;
  const [phase, setPhase] = React.useState("empty"); // empty | scanning | loaded
  const [scanFound, setScanFound] = React.useState(0);
  const [selection, setSelection] = React.useState({});
  const [openRows, setOpenRows] = React.useState({});
  const [jobs, setJobs] = React.useState([]);
  const [running, setRunning] = React.useState(false);
  const [consoleLines, setConsoleLines] = React.useState([]);
  const [consoleOpen, setConsoleOpen] = React.useState(t.consoleOpen);
  const [opts, setOpts] = React.useState({ fixDate: true, timecode: true, telemetry: true });

  React.useEffect(function () { setConsoleOpen(t.consoleOpen); }, [t.consoleOpen]);

  // ── Scan simulation ──────────────────────────────
  const scanTimer = React.useRef(null);
  function startScan() {
    setPhase("scanning");
    setScanFound(0);
    let found = 0;
    setConsoleLines([["cmd", "$ conjoyn scan " + SRC_PATH]]);
    clearInterval(scanTimer.current);
    scanTimer.current = setInterval(function () {
      found += 1 + Math.floor(Math.random() * 3);
      if (found >= window.CONJOYN_TOTAL_CLIPS) {
        found = window.CONJOYN_TOTAL_CLIPS;
        clearInterval(scanTimer.current);
        setTimeout(function () {
          setSelection(defaultSelection(recs));
          setOpenRows({});
          setConsoleLines(function (ls) {
            return ls.concat([["info", "scan   " + found + " clips · " + recs.length + " recordings · " + recs.filter(function (r) { return r.split; }).length + " split sets detected"], ["ok", "ready  splits pre-selected"]]);
          });
          setPhase("loaded");
        }, 420);
      }
      setScanFound(found);
    }, 70);
  }

  // ── Queue simulation ─────────────────────────────
  const simRef = React.useRef(null);
  React.useEffect(function () {
    if (!running) { clearInterval(simRef.current); return; }
    simRef.current = setInterval(function () {
      setJobs(function (prev) {
        const next = prev.map(function (j) { return Object.assign({}, j); });
        let active = next.find(function (j) { return j.status === "running"; });
        if (!active) {
          active = next.find(function (j) { return j.status === "queued"; });
          if (!active) { setRunning(false); return prev; }
          active.status = "running";
          active.attempts += 1;
          active.log = conjoynJobLog(active.rec);
          active.emitted = 0;
          setConsoleLines(function (ls) { return ls.concat([active.log[0]]); });
          active.emitted = 1;
        }
        // failure scenario: rec-12 fails at 62% on first attempt
        if (active.rec.id === "rec-12" && active.attempts === 1 && active.pct >= 62) {
          active.status = "failed";
          setConsoleLines(function (ls) {
            return ls.concat([["bad", "fail   " + active.rec.outName + "  — telemetry sidecar DJI_0076.SRT unreadable (retry to skip)"]]);
          });
          return next;
        }
        active.pct = Math.min(100, active.pct + 2.2 + Math.random() * 2.4);
        const shouldEmit = Math.floor((active.pct / 100) * active.log.length);
        while (active.emitted < shouldEmit && active.emitted < active.log.length - 1) {
          const line = active.log[active.emitted];
          setConsoleLines(function (ls) { return ls.concat([line]); });
          active.emitted += 1;
        }
        if (active.pct >= 100) {
          active.pct = 100;
          active.status = "done";
          setConsoleLines(function (ls) { return ls.concat([active.log[active.log.length - 1]]); });
        }
        return next;
      });
    }, 90);
    return function () { clearInterval(simRef.current); };
  }, [running]);

  function addToQueue() {
    const chosen = recs.filter(function (r) { return selection[r.id]; });
    setJobs(function (prev) {
      const queuedIds = {};
      prev.forEach(function (j) { queuedIds[j.rec.id] = true; });
      const fresh = chosen
        .filter(function (r) { return !queuedIds[r.id]; })
        .map(function (r, i) { return makeJob(r, prev.length + i); });
      return prev.concat(fresh);
    });
    setSelection({});
  }

  function retryJob(id) {
    setJobs(function (prev) {
      return prev.map(function (j) {
        return j.id === id ? Object.assign({}, j, { status: "queued", pct: 0 }) : j;
      });
    });
    setRunning(true);
  }

  function removeJob(id) {
    setJobs(function (prev) { return prev.filter(function (j) { return j.id !== id; }); });
  }

  // ── State jumper (prototype-only) ────────────────
  function jump(state) {
    clearInterval(scanTimer.current);
    setRunning(false);
    setOpenRows({});
    if (state === "empty") {
      setPhase("empty"); setJobs([]); setConsoleLines([]); setSelection({});
    } else if (state === "scanning") {
      setJobs([]); setConsoleLines([]); startScan();
    } else if (state === "loaded") {
      setPhase("loaded");
      setSelection(defaultSelection(recs));
      setOpenRows({ "rec-1": true });
      setJobs([]);
      setConsoleLines([["cmd", "$ conjoyn scan " + SRC_PATH], ["info", "scan   42 clips · 14 recordings · 8 split sets detected"], ["ok", "ready  splits pre-selected"]]);
    } else if (state === "running" || state === "done") {
      setPhase("loaded");
      setSelection({});
      const splits = recs.filter(function (r) { return r.split; });
      const js = splits.map(function (r, i) {
        const j = makeJob(r, i);
        j.attempts = 1;
        if (state === "done") { j.status = "done"; j.pct = 100; }
        else if (i < 3) { j.status = "done"; j.pct = 100; }
        else if (i === 3) { j.status = "running"; j.pct = 47; j.log = conjoynJobLog(r); j.emitted = Math.floor(0.47 * j.log.length); }
        return j;
      });
      setJobs(js);
      let lines = [["cmd", "$ conjoyn scan " + SRC_PATH], ["info", "scan   42 clips · 14 recordings · 8 split sets detected"]];
      const upto = state === "done" ? splits.length : 4;
      splits.slice(0, upto).forEach(function (r, i) {
        const log = conjoynJobLog(r);
        if (state === "done" || i < 3) lines = lines.concat(log);
        else lines = lines.concat(log.slice(0, Math.floor(0.47 * log.length)));
      });
      setConsoleLines(lines);
      if (state === "running") { setRunning(true); setConsoleOpen(true); }
    }
  }

  const selCount = recs.filter(function (r) { return selection[r.id]; }).length;
  const accStyle = {
    "--acc1": t.accent[0],
    "--acc2": t.accent[1],
  };

  return (
    <div className="stage">
      <div className={"cj-window" + (t.density === "compact" ? " density-compact" : "")} style={accStyle} data-screen-label={"Conjoyn — " + phase}>
        {/* Titlebar / source bar */}
        <div className="cj-titlebar">
          <MacTrafficLights />
          <div className="cj-apptitle">Conjoyn<small>Split recordings, made whole</small></div>
          <div style={{ flex: 1 }}></div>
          <div className="cj-sourcewell">
            <CjIcon d={CJ_PATHS.card} size={13} style={{ color: "var(--txt-3)", flexShrink: 0 }} />
            {phase === "empty"
              ? <span className="placeholder">No source selected</span>
              : <span className="path">{SRC_PATH}</span>}
            <div style={{ flex: 1 }}></div>
            <button className="btn" style={{ height: 20, padding: "0 9px", fontSize: 11 }}
              onClick={function () { if (phase === "empty") startScan(); }}>Choose…</button>
          </div>
          <button className="btn" disabled={phase === "scanning"} onClick={startScan}>
            <CjIcon d={CJ_PATHS.scan} size={12} />
            {phase === "scanning" ? "Scanning…" : "Scan"}
          </button>
        </div>

        {/* Body */}
        <div className="cj-body">
          {phase === "empty" ? <EmptyState onChoose={startScan} /> : null}
          {phase === "scanning" ? <ScanningState found={scanFound} /> : null}
          {phase === "loaded" ? (
            <React.Fragment>
              <div style={{ flex: 5, minHeight: 0, display: "flex", flexDirection: "column" }}>
                <RecordingsList recs={recs} selection={selection} setSelection={setSelection}
                  openRows={openRows} setOpenRows={setOpenRows} />
              </div>
              <OutputBar dest={DEST_PATH} opts={opts}
                setOpt={function (k, v) { setOpts(Object.assign({}, opts, (function () { const o = {}; o[k] = v; return o; })())); }}
                selCount={selCount} onAdd={addToQueue} disabled={false} />
              <div style={{ flex: 3, minHeight: 0, display: "flex", flexDirection: "column" }}>
                <JobQueue jobs={jobs} onRetry={retryJob} onRemove={removeJob} />
              </div>
            </React.Fragment>
          ) : null}
          {phase === "loaded" ? <ConsolePanel lines={consoleLines} open={consoleOpen} setOpen={setConsoleOpen} /> : null}
        </div>

        <FooterBar jobs={jobs} running={running}
          onStart={function () { setRunning(true); }}
          onStop={function () { setRunning(false); }} />
      </div>

      {/* Prototype state jumper */}
      <div className="jumper">
        <span style={{ marginRight: 4 }}>Jump to state:</span>
        <button onClick={function () { jump("empty"); }}>1 · Empty</button>
        <button onClick={function () { jump("scanning"); }}>2 · Scanning</button>
        <button onClick={function () { jump("loaded"); }}>3 · Groups loaded</button>
        <button onClick={function () { jump("running"); }}>4 · Queue running</button>
        <button onClick={function () { jump("done"); }}>5 · Done</button>
      </div>

      <TweaksPanel>
        <TweakSection label="Accent" />
        <TweakColor label="Accent" value={t.accent}
          options={[["#FFB23E", "#F0622A"], ["#34E0FF", "#2A6CF0"], ["#3FE8B0", "#1F9D6C"], ["#C9A1FF", "#6C4DF0"]]}
          onChange={function (v) { setTweak("accent", v); }} />
        <TweakSection label="Layout" />
        <TweakRadio label="List density" value={t.density} options={["comfortable", "compact"]}
          onChange={function (v) { setTweak("density", v); }} />
        <TweakToggle label="Console open" value={t.consoleOpen}
          onChange={function (v) { setTweak("consoleOpen", v); }} />
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<ConjoynApp />);
