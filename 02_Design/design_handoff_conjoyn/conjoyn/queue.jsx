// Conjoyn — output settings bar, job queue, console, footer

function OutputBar({ dest, opts, setOpt, selCount, onAdd, disabled }) {
  return (
    <div className="out-bar">
      <div className="out-opt" style={{ gap: 8 }}>
        <span style={{ color: "var(--txt-3)", fontWeight: 600 }}>Output</span>
        <div className="cj-sourcewell" style={{ minWidth: 230, height: 26 }}>
          <CjIcon d={CJ_PATHS.folder} size={12} style={{ color: "var(--txt-3)", flexShrink: 0 }} />
          <span className="path">{dest}</span>
          <div style={{ flex: 1 }}></div>
          <button className="btn" style={{ height: 18, padding: "0 8px", fontSize: 11 }}>Choose…</button>
        </div>
      </div>
      <div style={{ flex: 1 }}></div>
      <label className="out-opt"><MacSwitch on={opts.fixDate} onChange={function (v) { setOpt("fixDate", v); }} /><span>Fix recording date</span></label>
      <label className="out-opt"><MacSwitch on={opts.timecode} onChange={function (v) { setOpt("timecode", v); }} /><span>Preserve timecode</span></label>
      <label className="out-opt"><MacSwitch on={opts.telemetry} onChange={function (v) { setOpt("telemetry", v); }} /><span>Stitch telemetry</span></label>
      <button className="btn btn-primary" disabled={disabled || selCount === 0} onClick={onAdd}>
        {selCount > 0 ? "Add " + selCount + " to Queue" : "Add to Queue"}
      </button>
    </div>
  );
}

const JOB_STATUS_LABEL = { queued: "Queued", running: "Joining…", done: "Done", failed: "Failed" };

function QueueRow({ job, onRetry, onRemove }) {
  const cls = job.status === "done" ? "qstatus ok" : job.status === "failed" ? "qstatus bad" : job.status === "running" ? "qstatus run" : "qstatus";
  return (
    <div className="queue-row">
      <div className="qname" title={job.rec.outName}>{job.rec.outName}</div>
      <CjProgress pct={job.pct} state={job.status} />
      <div className={cls}>{JOB_STATUS_LABEL[job.status]}</div>
      <div className="qactions">
        {job.status === "failed" ? (
          <button className="icon-btn" title="Retry" onClick={onRetry}><CjIcon d={CJ_PATHS.retry} size={12} /></button>
        ) : null}
        {job.status === "done" ? (
          <button className="icon-btn" title="Reveal in Finder"><CjIcon d={CJ_PATHS.finder} size={12} /></button>
        ) : null}
        {job.status === "queued" || job.status === "failed" ? (
          <button className="icon-btn" title="Remove from queue" onClick={onRemove}><CjIcon d={CJ_PATHS.x} size={11} /></button>
        ) : null}
      </div>
    </div>
  );
}

function JobQueue({ jobs, onRetry, onRemove }) {
  return (
    <React.Fragment>
      <div className="section-head" style={{ borderTop: "1px solid var(--line)" }}>
        <span>Queue</span>
        {jobs.length > 0 ? <span className="count">{jobs.length} {jobs.length === 1 ? "job" : "jobs"}</span> : null}
      </div>
      <div className="list-scroll" style={{ flex: 1 }}>
        {jobs.length === 0 ? (
          <div style={{ padding: "18px 16px", fontSize: 12, color: "var(--txt-3)" }}>
            No jobs yet — select recordings above and press “Add to Queue”.
          </div>
        ) : (
          jobs.map(function (j) {
            return <QueueRow key={j.id} job={j}
              onRetry={function () { onRetry(j.id); }}
              onRemove={function () { onRemove(j.id); }} />;
          })
        )}
      </div>
    </React.Fragment>
  );
}

function ConsolePanel({ lines, open, setOpen }) {
  const ref = React.useRef(null);
  React.useEffect(function () {
    if (ref.current) ref.current.scrollTop = ref.current.scrollHeight;
  }, [lines.length, open]);
  return (
    <div className="console-wrap">
      <div className="console-head" onClick={function () { setOpen(!open); }}>
        <CjIcon d={open ? CJ_PATHS.chevD : CJ_PATHS.chevR} size={10} stroke={2} />
        <span>Console</span>
        <span style={{ fontWeight: 400 }}>{lines.length > 0 ? lines.length + " lines" : ""}</span>
      </div>
      {open ? (
        <div className="console-log" ref={ref}>
          {lines.length === 0 ? <div className="ln-info">— idle —</div> : null}
          {lines.map(function (l, i) {
            return <div key={i} className={"ln-" + l[0]}>{l[1]}</div>;
          })}
        </div>
      ) : null}
    </div>
  );
}

function FooterBar({ jobs, running, onStart, onStop }) {
  const done = jobs.filter(function (j) { return j.status === "done"; }).length;
  const failed = jobs.filter(function (j) { return j.status === "failed"; }).length;
  const total = jobs.length;
  const overallPct = total === 0 ? 0 :
    jobs.reduce(function (a, j) { return a + (j.status === "done" ? 100 : j.pct); }, 0) / total;
  const allDone = total > 0 && done + failed === total && !running;

  return (
    <div className="cj-footer">
      {running ? (
        <button className="btn btn-stop btn-lg" onClick={onStop}>Stop</button>
      ) : (
        <button className="btn btn-primary btn-lg" onClick={onStart}
          disabled={total === 0 || allDone}>Start</button>
      )}
      <div style={{ flex: 1, display: "flex", alignItems: "center", gap: 12 }}>
        <CjProgress pct={overallPct} state={allDone && failed === 0 ? "done" : "running"} />
      </div>
      <div className="totals">
        {total === 0 ? (
          <span>Queue empty</span>
        ) : allDone ? (
          <span className="ok">✓ {done} of {total} joined{failed > 0 ? ", " + failed + " failed" : ", 0 failed"}</span>
        ) : (
          <span><b>{done}</b> of <b>{total}</b> joined · {failed} failed</span>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { OutputBar, JobQueue, ConsolePanel, FooterBar, JOB_STATUS_LABEL });
