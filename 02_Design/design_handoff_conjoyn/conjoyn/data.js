// Conjoyn — mock card data (DJI-style drone footage)
// A full 256 GB card: 42 clips grouped into 14 recordings (8 split sets, 6 singles).

(function () {
  // ~100 Mbps H.265 → a 4.04 GB segment ≈ 5m23s of footage
  const SEG_SECONDS = 323; // full segment duration
  const SEG_GB = 4.04;     // full segment size

  function pad4(n) { return String(n).padStart(4, '0'); }

  // [firstClipNum, segmentCount, dateLabel, timeLabel, lastSegFraction]
  const SPEC = [
    [42, 6, 'May 31, 2026', '09:14:02', 0.62],
    [48, 1, 'May 31, 2026', '09:48:51', 0.39],
    [49, 4, 'May 31, 2026', '10:02:17', 0.88],
    [53, 1, 'May 31, 2026', '10:31:09', 0.21],
    [54, 5, 'May 31, 2026', '10:44:33', 0.45],
    [59, 2, 'May 31, 2026', '11:18:46', 0.97],
    [61, 1, 'May 31, 2026', '11:40:12', 0.55],
    [62, 7, 'May 31, 2026', '12:05:58', 0.31],
    [69, 1, 'May 31, 2026', '12:51:24', 0.74],
    [70, 3, 'May 31, 2026', '14:06:40', 0.52],
    [73, 1, 'May 31, 2026', '14:27:15', 0.18],
    [74, 4, 'May 31, 2026', '14:39:02', 0.66],
    [78, 1, 'May 31, 2026', '15:12:48', 0.43],
    [79, 5, 'May 31, 2026', '15:24:31', 0.79],
  ];

  function fmtDur(totalSec) {
    totalSec = Math.round(totalSec);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    if (h > 0) return h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
    return m + ':' + String(s).padStart(2, '0');
  }

  function fmtGB(gb) {
    if (gb < 1) return Math.round(gb * 1024) + ' MB';
    return (Math.round(gb * 100) / 100).toFixed(2) + ' GB';
  }

  const RECORDINGS = SPEC.map(function (row, i) {
    const first = row[0], count = row[1], date = row[2], time = row[3], lastFrac = row[4];
    const segments = [];
    for (let s = 0; s < count; s++) {
      const frac = (s === count - 1) ? lastFrac : 1;
      segments.push({
        file: 'DJI_' + pad4(first + s) + '.MP4',
        srt: 'DJI_' + pad4(first + s) + '.SRT',
        seconds: SEG_SECONDS * frac,
        gb: SEG_GB * frac,
      });
    }
    const totalSec = segments.reduce(function (a, s) { return a + s.seconds; }, 0);
    const totalGB = segments.reduce(function (a, s) { return a + s.gb; }, 0);
    const last = 'DJI_' + pad4(first + count - 1);
    return {
      id: 'rec-' + (i + 1),
      name: count > 1 ? ('DJI_' + pad4(first) + ' – ' + last) : ('DJI_' + pad4(first)),
      outName: 'DJI_' + pad4(first) + '_joined.MP4',
      date: date,
      time: time,
      split: count > 1,
      segments: segments,
      seconds: totalSec,
      gb: totalGB,
      durLabel: fmtDur(totalSec),
      sizeLabel: fmtGB(totalGB),
    };
  });

  const TOTAL_CLIPS = RECORDINGS.reduce(function (a, r) { return a + r.segments.length; }, 0);

  // Console log script for a single join job — fn(recording) → array of lines
  function jobLog(rec) {
    const lines = [];
    lines.push(['cmd', '$ conjoyn join --lossless --fix-date --stitch-telemetry ' + rec.name.replace(/ /g, '')]);
    rec.segments.forEach(function (s) {
      lines.push(['info', 'probe  ' + s.file + '  h265 3840×2160 29.97p  ' + fmtGB(s.gb)]);
    });
    lines.push(['info', 'match  ' + rec.segments.length + ' segment(s) → continuous timecode, gap < 1 frame']);
    lines.push(['info', 'join   stream-copy (no re-encode) → ' + rec.outName]);
    if (rec.split) lines.push(['info', 'srt    stitched ' + rec.segments.length + ' telemetry files, offsets rebased']);
    lines.push(['info', 'date   creation date restamped → ' + rec.date + ' ' + rec.time]);
    lines.push(['ok', 'done   ' + rec.outName + '  ' + rec.sizeLabel + '  ✓ verified']);
    return lines;
  }

  Object.assign(window, {
    CONJOYN_RECORDINGS: RECORDINGS,
    CONJOYN_TOTAL_CLIPS: TOTAL_CLIPS,
    conjoynJobLog: jobLog,
    fmtDur: fmtDur,
    fmtGB: fmtGB,
  });
})();
