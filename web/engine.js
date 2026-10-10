// Schedule logic for the web countdown, ported from ScheduleCountdown/Engine/ScheduleEngine.swift.
// Pure: no DOM, timers or network, and the moment is always passed in, so it's easy to test.
// Bells ring on Klein time, so every wall-clock reading uses Central time, whatever the device says.

export const ZONE = "America/Chicago";
export const LUNCHES = ["A", "B", "C"];

const DAY_MS = 86_400_000;

const wallFormat = new Intl.DateTimeFormat("en-US", {
  timeZone: ZONE, hourCycle: "h23",
  year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit",
});

/// The Klein calendar day ("2026-10-12") and seconds since midnight at an instant (ms since epoch).
export function wallClock(instant) {
  const p = Object.fromEntries(wallFormat.formatToParts(instant).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, seconds: +p.hour * 3600 + +p.minute * 60 + +p.second };
}

/// The instant a Klein wall-clock time happens on a day.
export function instantAt(day, minutesSinceMidnight) {
  const asUTC = utcMidnight(day) + minutesSinceMidnight * 60_000;
  // Shift by the zone's offset, then once more in case that crossed a daylight saving change.
  const guess = asUTC - offsetAt(asUTC);
  return asUTC - offsetAt(guess);
}

function offsetAt(instant) {
  const { day, seconds } = wallClock(instant);
  const whole = instant - (instant % 1000);
  return utcMidnight(day) + seconds * 1000 - whole;
}

function utcMidnight(day) {
  const [y, m, d] = day.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

export function addDays(day, count) {
  return new Date(utcMidnight(day) + count * DAY_MS).toISOString().slice(0, 10);
}

/// 0 = Sunday … 6 = Saturday.
export function weekday(day) {
  return new Date(utcMidnight(day)).getUTCDay();
}

/// "07:15" → 435.
export function minutes(time) {
  const [h, m] = time.split(":").map(Number);
  return h * 60 + m;
}

/// 435 → "7:15", 780 → "1:00": how the school writes times.
export function display(minutesSinceMidnight) {
  const h = Math.floor(minutesSinceMidnight / 60);
  const m = minutesSinceMidnight % 60;
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, "0")}`;
}

/// When you actually leave: the dismiss bell if there is one, otherwise the end.
export function effectiveEnd(block) {
  return block.dismiss ?? block.end;
}

/// The schedule for a day, plus the calendar note ("Homecoming") if one applies.
/// Calendar entries win over everything (the shortest matching range wins, so one day
/// inside a break can still be a school day); otherwise weekends are off and weekdays
/// use the default schedule.
export function scheduleOn(master, day) {
  const byID = (id) => master.schedules.find((s) => s.id === id);
  const matches = master.calendar.filter((e) => e.start <= day && day <= e.end);
  if (matches.length > 0) {
    const span = (e) => utcMidnight(e.end) - utcMidnight(e.start);
    const entry = matches.reduce((best, e) => (span(e) < span(best) ? e : best));
    const schedule = entry.scheduleID == null ? null : byID(entry.scheduleID) ?? byID(master.defaultScheduleID);
    return { schedule, note: entry.note ?? null };
  }
  const weekend = weekday(day) === 0 || weekday(day) === 6;
  return { schedule: weekend ? null : byID(master.defaultScheduleID), note: null };
}

/// Blocks this lunch group actually sits through, in time order. A block without groups is for everyone.
export function blocksFor(schedule, lunch) {
  return schedule.blocks
    .filter((b) => !b.groups || b.groups.includes(lunch))
    .sort((a, b) => minutes(a.start) - minutes(b.start));
}

/// Every bell you hear that day, in minutes since midnight: one-off bells, block starts,
/// and block ends (or the dismiss bell when a block lets out early).
export function bellMinutes(schedule, lunch) {
  const times = [
    ...(schedule.bells ?? []).map((b) => minutes(b.time)),
    ...blocksFor(schedule, lunch).flatMap((b) => [minutes(b.start), minutes(effectiveEnd(b))]),
  ];
  return [...new Set(times)].sort((a, b) => a - b);
}

/// Where you are in the school day at an instant.
export function status(master, instant, lunch) {
  const { day, seconds } = wallClock(instant);
  const { schedule, note } = scheduleOn(master, day);
  const result = {
    day, schedule, note,
    blocks: [], current: null, next: null, finished: [],
    inSession: false, nextBell: null,
  };
  if (!schedule) return result;

  const at = (time) => minutes(time) * 60;
  const blocks = blocksFor(schedule, lunch);
  result.blocks = blocks;
  result.current = blocks.find((b) => at(b.start) <= seconds && seconds < at(effectiveEnd(b))) ?? null;
  result.next = blocks.find((b) => at(b.start) > seconds) ?? null;
  result.finished = blocks.filter((b) => at(effectiveEnd(b)) <= seconds);

  const bells = bellMinutes(schedule, lunch);
  if (bells.length > 0) {
    result.inSession = bells[0] * 60 <= seconds && seconds < bells.at(-1) * 60;
  }
  const next = bells.find((m) => m * 60 > seconds);
  if (next != null) result.nextBell = { at: instantAt(day, next), minutes: next };
  return result;
}

/// The next bell from an instant, looking ahead across days (for after school and days off).
export function nextSchoolBell(master, instant, lunch, lookAheadDays = 30) {
  const today = status(master, instant, lunch);
  if (today.nextBell) return { ...today.nextBell, day: today.day, schedule: today.schedule };
  for (let offset = 1; offset <= lookAheadDays; offset++) {
    const day = addDays(today.day, offset);
    const { schedule } = scheduleOn(master, day);
    const first = schedule && bellMinutes(schedule, lunch)[0];
    if (first != null) return { at: instantAt(day, first), minutes: first, day, schedule };
  }
  return null;
}

/// "4:59", "12:03", "1:02:03", or "2d 3h" for very long waits.
export function formatCountdown(seconds) {
  const total = Math.max(0, Math.ceil(seconds));
  const days = Math.floor(total / 86_400);
  const hours = Math.floor((total % 86_400) / 3600);
  const mins = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  const pad = (n) => String(n).padStart(2, "0");
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}:${pad(mins)}:${pad(secs)}`;
  return `${mins}:${pad(secs)}`;
}
