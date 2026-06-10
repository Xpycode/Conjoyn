// Conjoyn — rename popover: token pattern editor + live preview

const RENAME_DEFAULTS = { pattern: "{name}_{date}_joined", start: 1, pad: 3 };

function cjIsoDate() { return "2026-05-31"; }

function cjApplyPattern(rec, opts, index) {
  const counter = String(opts.start + index).padStart(opts.pad, "0");
  let out = opts.pattern
    .split("{name}").join(rec.name.split(" ")[0])
    .split("{date}").join(cjIsoDate())
    .split("{time}").join(rec.time.split(":").join("."))
    .split("{###}").join(counter);
  out = out.replace(/[\\/:*?"<>|]/g, "-").trim();
  return (out || rec.name.split(" ")[0]) + ".MP4";
}

const RENAME_TOKENS = [
  ["{name}", "First clip name"],
  ["{date}", "Recording date"],
  ["{time}", "Start time"],
  ["{###}", "Counter"],
];

const RENAME_PRESETS = [
  ["Original + date", "{name}_{date}_joined"],
  ["Date + counter", "{date}_flight_{###}"],
  ["Date + time", "{date}_{time}"],
];

function RenameHUD({ opts, setOpts, sampleRecs, onClose }) {
  const inputRef = React.useRef(null);

  function insertToken(tok) {
    const el = inputRef.current;
    if (el && typeof el.selectionStart === "number") {
      const a = el.selectionStart, b = el.selectionEnd;
      const next = opts.pattern.slice(0, a) + tok + opts.pattern.slice(b);
      setOpts(Object.assign({}, opts, { pattern: next }));
      requestAnimationFrame(function () { el.focus(); el.setSelectionRange(a + tok.length, a + tok.length); });
    } else {
      setOpts(Object.assign({}, opts, { pattern: opts.pattern + tok }));
    }
  }

  const usesCounter = opts.pattern.indexOf("{###}") !== -1;

  return (
    <div className="rename-hud" data-screen-label="Rename popover">
      <div className="hud-titlebar">
        <span>Rename Joined Files</span>
        <button className="hud-close" title="Close" onClick={onClose}>
          <CjIcon d={CJ_PATHS.x} size={8} stroke={2} />
        </button>
      </div>

      <div className="hud-form">
        <div className="flabel">Preset:</div>
        <div className="hud-presets">
          {RENAME_PRESETS.map(function (p) {
            return (
              <button key={p[0]}
                className={"hud-chip" + (opts.pattern === p[1] ? " on" : "")}
                onClick={function () { setOpts(Object.assign({}, opts, { pattern: p[1] })); }}>
                {p[0]}
              </button>
            );
          })}
        </div>

        <div className="flabel">Pattern:</div>
        <div>
          <input ref={inputRef} className="hud-input" type="text" value={opts.pattern}
            spellCheck="false"
            onChange={function (e) { setOpts(Object.assign({}, opts, { pattern: e.target.value })); }} />
          <div className="hud-tokens">
            {RENAME_TOKENS.map(function (t) {
              return (
                <button key={t[0]} className="hud-chip mono" title={t[1]}
                  onClick={function () { insertToken(t[0]); }}>{t[0]}</button>
              );
            })}
          </div>
        </div>

        <div className={"flabel" + (usesCounter ? "" : " dim")}>Counter:</div>
        <div className={"hud-counter" + (usesCounter ? " " : " dim")}>
          <label className="hud-field">
            <span>Start at</span>
            <input className="hud-input num" type="number" min="0" max="999" value={opts.start}
              disabled={!usesCounter}
              onChange={function (e) { setOpts(Object.assign({}, opts, { start: Math.max(0, parseInt(e.target.value || "0", 10)) })); }} />
          </label>
          <label className="hud-field">
            <span>Digits</span>
            <div className="seg-group">
              {[2, 3, 4].map(function (n) {
                return (
                  <button key={n} className={"btn" + (opts.pad === n ? " on" : "")} disabled={!usesCounter}
                    onClick={function () { setOpts(Object.assign({}, opts, { pad: n })); }}>{n}</button>
                );
              })}
            </div>
          </label>
        </div>

        <div className="flabel">Preview:</div>
        <div className="hud-preview">
          {sampleRecs.slice(0, 3).map(function (rec, i) {
            return (
              <div className="hud-preview-row" key={rec.id}>
                <span className="from">{rec.name.split(" ")[0]}.MP4</span>
                <span className="arr"> →</span>
                <span className="to">{cjApplyPattern(rec, opts, i)}</span>
              </div>
            );
          })}
          {sampleRecs.length === 0 ? (
            <div className="hud-preview-row"><span className="from">Select recordings to preview</span></div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { RenameHUD, RENAME_DEFAULTS, cjApplyPattern });
