// Conjoyn — recordings list (the hero region) + empty/scanning states

function RecRow({ rec, checked, onCheck, open, onToggleOpen }) {
  return (
    <React.Fragment>
      <div className={"rec-row" + (checked ? " checked" : "")} onClick={function () { onCheck(!checked); }}>
        <MacCheck on={checked} onChange={onCheck} title={checked ? "Deselect" : "Select"} />
        <button
          className={"disclose" + (open ? " open" : "") + (rec.split ? "" : " hidden-slot")}
          onClick={function (e) { e.stopPropagation(); onToggleOpen(); }}
          title="Show segments">
          <CjIcon d={CJ_PATHS.chevR} size={11} stroke={2} />
        </button>
        <CjThumb />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="rec-name">{rec.name}</div>
          <div className="rec-sub">
            <span>{rec.date}</span>
            <span className="dim">{rec.time}</span>
            {rec.split ? <span className="dim">+ {rec.segments.length} telemetry .SRT</span> : null}
          </div>
        </div>
        <CjBadge split={rec.split} count={rec.segments.length} />
        <div className="rec-meta">
          <span><b>{rec.segments.length}</b> {rec.segments.length === 1 ? "file" : "files"}</span>
          <span style={{ width: 52, textAlign: "right" }}><b>{rec.durLabel}</b></span>
          <span style={{ width: 64, textAlign: "right" }}>{rec.sizeLabel}</span>
        </div>
      </div>
      {open && rec.split ? (
        <div className="seg-sublist">
          {rec.segments.map(function (s, i) {
            return (
              <div className="seg-line" key={s.file}>
                <span className="tick">{i === rec.segments.length - 1 ? "└" : "├"}</span>
                <span className="fname">{s.file}</span>
                <span className="srt">+ {s.srt}</span>
                <span className="right">
                  <span>{fmtDur(s.seconds)}</span>
                  <span style={{ width: 60, textAlign: "right" }}>{fmtGB(s.gb)}</span>
                </span>
              </div>
            );
          })}
        </div>
      ) : null}
    </React.Fragment>
  );
}

function RecordingsList({ recs, selection, setSelection, openRows, setOpenRows }) {
  const selCount = recs.filter(function (r) { return selection[r.id]; }).length;

  function selectWhere(pred) {
    const next = {};
    recs.forEach(function (r) { next[r.id] = pred(r); });
    setSelection(next);
  }

  return (
    <React.Fragment>
      <div className="section-head">
        <span>Discovered recordings</span>
        <span className="count">{selCount} of {recs.length} selected · {window.CONJOYN_TOTAL_CLIPS} clips on card</span>
        <div style={{ flex: 1 }}></div>
        <div className="seg-group">
          <button className="btn" onClick={function () { selectWhere(function () { return true; }); }}>All</button>
          <button className="btn" onClick={function () { selectWhere(function () { return false; }); }}>None</button>
          <button className="btn" onClick={function () { selectWhere(function (r) { return r.split; }); }}>Splits</button>
        </div>
      </div>
      <div className="list-scroll">
        {recs.map(function (rec) {
          return (
            <RecRow
              key={rec.id}
              rec={rec}
              checked={!!selection[rec.id]}
              onCheck={function (v) {
                const next = Object.assign({}, selection);
                next[rec.id] = v;
                setSelection(next);
              }}
              open={!!openRows[rec.id]}
              onToggleOpen={function () {
                const next = Object.assign({}, openRows);
                next[rec.id] = !next[rec.id];
                setOpenRows(next);
              }}
            />
          );
        })}
      </div>
    </React.Fragment>
  );
}

function EmptyState({ onChoose }) {
  return (
    <div className="hero-empty">
      <div className="drop">
        <CjIcon d={CJ_PATHS.card} size={34} stroke={1.1} style={{ color: "#555555" }} />
        <h2>Choose a folder or drop a card to begin</h2>
        <p>Conjoyn will scan it, find recordings that were split at the 4 GB card limit, and join them back into whole files — losslessly.</p>
        <button className="btn btn-primary btn-lg" onClick={onChoose} style={{ marginTop: 6 }}>Choose Folder…</button>
      </div>
    </div>
  );
}

function ScanningState({ found }) {
  return (
    <div className="hero-empty">
      <div className="spinner"></div>
      <h2 style={{ margin: 0, fontSize: 14, fontWeight: 600, color: "var(--txt)" }}>Scanning card…</h2>
      <p style={{ margin: 0, fontSize: 12, color: "var(--txt-2)", fontVariantNumeric: "tabular-nums" }}>
        {found} clips found · grouping by timecode & metadata
      </p>
    </div>
  );
}

Object.assign(window, { RecRow, RecordingsList, EmptyState, ScanningState });
