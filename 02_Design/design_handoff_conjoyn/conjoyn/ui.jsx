// Conjoyn — shared UI atoms (icons, checkbox, switch, progress, badges)

function CjIcon({ d, size = 12, stroke = 1.5, style }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" style={style}>
      <path d={d} stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"></path>
    </svg>
  );
}

const CJ_PATHS = {
  folder: "M1.5 4.5a1 1 0 0 1 1-1h3l1.5 2h6.5a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-8z",
  chevR: "M6 3.5 L10.5 8 L6 12.5",
  chevD: "M3.5 6 L8 10.5 L12.5 6",
  retry: "M13 8a5 5 0 1 1-1.5-3.5M13 1.5V4.5H10",
  x: "M4 4 L12 12 M12 4 L4 12",
  finder: "M10.2 10.2 L14 14 M10.5 6.5 a4 4 0 1 1 -8 0 a4 4 0 0 1 8 0",
  scan: "M2 5V3a1 1 0 0 1 1-1h2M14 5V3a1 1 0 0 0-1-1h-2M2 11v2a1 1 0 0 0 1 1h2M14 11v2a1 1 0 0 1-1 1h-2M4 8h8",
  card: "M4.5 1.5h7a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1h-7a1 1 0 0 1-1-1V5l3-3.5zM6 4v2M8.5 4v2M11 4v2",
};

function MacCheck({ on, onChange, title }) {
  return (
    <button className={"mac-check" + (on ? " on" : "")} title={title}
            onClick={function (e) { e.stopPropagation(); onChange(!on); }}>
      {on ? (
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <path d="M2 5.2 L4.2 7.4 L8 2.8" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"></path>
        </svg>
      ) : null}
    </button>
  );
}

function MacSwitch({ on, onChange }) {
  return (
    <button className={"mac-switch" + (on ? " on" : "")} onClick={function () { onChange(!on); }}>
      <span className="knob"></span>
    </button>
  );
}

function CjBadge({ split, count }) {
  return split
    ? <span className="badge badge-split">Split · {count}</span>
    : <span className="badge badge-single">Single</span>;
}

function CjProgress({ pct, state }) {
  const cls = state === "done" ? "fill done" : state === "failed" ? "fill fail" : "fill";
  return (
    <div className="pbar">
      <div className={cls} style={{ width: Math.max(0, Math.min(100, pct)) + "%" }}></div>
    </div>
  );
}

function CjThumb() {
  return <div className="rec-thumb"></div>;
}

Object.assign(window, { CjIcon, CJ_PATHS, MacCheck, MacSwitch, CjBadge, CjProgress, CjThumb });
