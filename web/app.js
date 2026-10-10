import {
  LUNCHES, ZONE, status, nextSchoolBell, instantAt, addDays, weekday,
  minutes, display, effectiveEnd, blocksFor, formatCountdown,
} from "./engine.js";

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);

// ?now=2026-10-12T11:45 runs the page as if it were that moment in Klein; the clock keeps ticking from there.
const fakeNow = params.get("now")?.match(/^(\d{4}-\d{2}-\d{2})T(\d{1,2}):(\d{2})$/);
const clockOffset = fakeNow ? instantAt(fakeNow[1], +fakeNow[2] * 60 + +fakeNow[3]) - Date.now() : 0;
const now = () => Date.now() + clockOffset;

let master = null;
let lunch = [params.get("lunch")?.toUpperCase(), readStoredLunch()].find((l) => LUNCHES.includes(l)) ?? "A";
// Start the lunch highlight on the saved choice so it doesn't slide in from A on load.
document.querySelector(".seg").style.setProperty("--i", LUNCHES.indexOf(lunch));

// --- Lunch ---------------------------------------------------------------

function readStoredLunch() {
  try { return localStorage.getItem("lunch"); } catch { return null; }
}

function setLunch(choice) {
  lunch = choice;
  try { localStorage.setItem("lunch", choice); } catch {}
  // Keep a ?lunch= link in sync so a bookmark matches what's on screen.
  if (params.has("lunch")) {
    params.set("lunch", choice);
    history.replaceState(null, "", `?${params}`);
  }
  render();
}

for (const button of document.querySelectorAll("[data-lunch]")) {
  button.addEventListener("click", () => setLunch(button.dataset.lunch));
}

// --- Countdown -----------------------------------------------------------

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

/// "today", "tomorrow", "Monday", or "Nov 30" when it's more than a week away.
function dayName(day, today) {
  if (day === today) return "today";
  if (day === addDays(today, 1)) return "tomorrow";
  if (day <= addDays(today, 6)) return WEEKDAYS[weekday(day)];
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
}

/// "1st" → "1st period"; other names ("A Lunch", "Advisory") stay as they are.
const periodName = (name) => (/^\d+(st|nd|rd|th)$/.test(name) ? `${name} period` : name);

/// What the middle of the page says, and which day the schedule sheet shows.
function headline(st, at) {
  const bell = st.nextBell;
  if (st.current) {
    const out = st.current.dismiss && minutes(st.current.dismiss) === bell?.minutes;
    return { eyebrow: periodName(st.current.name), target: bell?.at, caption: bell && `${out ? "Out" : "Bell"} at ${display(bell.minutes)}` };
  }
  if (st.inSession) {
    const caption = st.next ? `${periodName(st.next.name)} starts at ${display(minutes(st.next.start))}` : `Bell at ${display(bell.minutes)}`;
    return { eyebrow: "Passing period", target: bell?.at, caption };
  }
  if (st.schedule && bell) {
    return { eyebrow: "Before school", target: bell.at, caption: `First bell at ${display(bell.minutes)}` };
  }

  const ahead = nextSchoolBell(master, at, lunch);
  const weekend = weekday(st.day) === 0 || weekday(st.day) === 6;
  const eyebrow = st.schedule ? "School's out" : st.note ?? (weekend ? "Weekend" : "No school");
  if (!ahead) return { eyebrow, target: null, caption: "No school days coming up", idle: true };
  return {
    eyebrow, target: ahead.at, idle: true,
    caption: `Next bell ${dayName(ahead.day, st.day)} at ${display(ahead.minutes)}`,
    sheetDay: st.schedule ? null : ahead,
  };
}

function render() {
  if (!master) return;
  const at = now();
  const st = status(master, at, lunch);
  const head = headline(st, at);
  const clock = head.target ? formatCountdown((head.target - at) / 1000) : "—";

  fadeText($("eyebrow"), head.eyebrow);
  setText($("countdown"), clock);
  setText($("caption"), head.caption ?? "");
  $("countdown").classList.toggle("idle", !!head.idle);
  document.title = head.target ? `${clock} · ${head.eyebrow}` : "Bell Countdown";

  for (const button of document.querySelectorAll("[data-lunch]")) {
    button.setAttribute("aria-pressed", String(button.dataset.lunch === lunch));
  }
  document.querySelector(".seg").style.setProperty("--i", LUNCHES.indexOf(lunch));
  renderSheet(st, head.sheetDay);
}

// --- Schedule sheet --------------------------------------------------------

let lastSheet = "";

/// Today's blocks; on a day off, the next school day's.
function renderSheet(st, ahead) {
  const schedule = ahead ? ahead.schedule : st.schedule;
  const blocks = ahead ? blocksFor(schedule, lunch) : st.blocks;
  const when = ahead ? dayName(ahead.day, st.day) : "Today";
  const title = schedule
    ? [when[0].toUpperCase() + when.slice(1), schedule.name, ahead ? null : st.note].filter(Boolean).join(" · ")
    : "No school days coming up";

  const rows = blocks.map((b) => {
    const state = ahead ? "" : b === st.current ? "current" : st.finished.includes(b) ? "done" : b === st.next ? "next" : "";
    const times = `${display(minutes(b.start))}–${display(minutes(b.end))}` + (b.dismiss ? ` · out ${display(minutes(b.dismiss))}` : "");
    return { name: b.name, times, state };
  });

  const key = JSON.stringify([title, rows]);
  if (key === lastSheet) return;
  lastSheet = key;

  $("sheet-title").textContent = title;
  $("blocks").replaceChildren(...rows.map(({ name, times, state }) => {
    const li = document.createElement("li");
    if (state) li.className = state;
    li.append(span(name, "name"), span(times, "times"));
    return li;
  }));
}

// --- Bearkat Brief ------------------------------------------------------------

async function loadBriefs() {
  const text = await (await fetch("briefs.txt", { cache: "no-cache" })).text();
  const links = text.split("\n").map((l) => l.trim()).filter((l) => /^https?:\/\//.test(l)).slice(0, 3);
  $("briefs").replaceChildren(...links.map((url) => {
    const a = document.createElement("a");
    a.href = url;
    a.target = "_blank";
    a.rel = "noopener";
    a.append(span(briefTitle(url), "title"), span("↗", "arrow"));
    const li = document.createElement("li");
    li.append(a);
    return li;
  }));
}

// On a wide screen the Brief is an open bar at the bottom whose open/closed choice is remembered.
// On a narrow one it's a pill that opens a card, like View schedule, and starts closed.
// On a wide but short one it stays a bar but starts closed and opens as a card over the countdown;
// that choice isn't remembered, so it doesn't change the tall-screen one.
const compact = matchMedia("(max-width: 900px)");
const short = matchMedia("(max-height: 800px)");

function setupBriefMemory() {
  const brief = $("brief");
  const overlay = () => compact.matches || short.matches;
  const sync = () => {
    let remembered = true;
    try { remembered = localStorage.getItem("briefOpen") !== "no"; } catch {}
    brief.open = overlay() ? false : remembered;
  };
  sync();
  compact.addEventListener("change", sync);
  short.addEventListener("change", sync);

  brief.addEventListener("toggle", () => {
    if (!overlay()) {
      try { localStorage.setItem("briefOpen", brief.open ? "yes" : "no"); } catch {}
    } else if (brief.open) {
      $("schedule").hidePopover?.();
    }
  });

  // Like a popover: tap outside or press Escape to close the card.
  document.addEventListener("pointerdown", (e) => {
    if (overlay() && brief.open && !brief.contains(e.target)) brief.open = false;
  });
  document.addEventListener("keydown", (e) => {
    if (overlay() && brief.open && e.key === "Escape") brief.open = false;
  });
}

/// ".../brief-community-week-9-179364" → "Week 9".
function briefTitle(url) {
  const week = url.match(/week-(\d+)/i);
  return week ? `Week ${week[1]}` : "Bearkat Brief";
}

// --- Dev bar (only with ?now=) -------------------------------------------------

function renderDevBar() {
  if (!fakeNow) return;
  const presets = [
    ["Live", null],
    ["Before school", "2026-10-12T06:55"],
    ["1st", "2026-10-12T07:30"],
    ["Passing", "2026-10-12T08:05"],
    ["Lunch", "2026-10-12T11:55"],
    ["After school", "2026-10-12T15:10"],
    ["Weekend", "2026-10-10T10:00"],
    ["Jamboree", "2026-10-09T10:00"],
  ];
  const bar = $("devbar");
  bar.replaceChildren(...presets.map(([label, moment]) => {
    const p = new URLSearchParams(params);
    moment ? p.set("now", moment) : p.delete("now");
    const a = document.createElement("a");
    a.href = `?${p}`;
    a.textContent = label;
    if (moment === params.get("now")) a.setAttribute("aria-current", "true");
    return a;
  }));
  bar.hidden = false;
}

// --- Helpers and startup -------------------------------------------------------

function span(text, className) {
  const s = document.createElement("span");
  s.className = className;
  s.textContent = text;
  return s;
}

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");

/// Like setText, but a changed label (3rd → Passing period) fades in; the first fill doesn't.
function fadeText(el, text) {
  if (el.textContent === text) return;
  const first = !el.textContent.trim();
  el.textContent = text;
  if (first) return;
  const blur = reduceMotion.matches ? "blur(0)" : "blur(2px)";
  el.animate([{ opacity: 0, filter: blur }, { opacity: 1, filter: "blur(0)" }], { duration: 200, easing: "ease-out" });
}

function setText(el, text) {
  if (el.textContent !== text) el.textContent = text;
}

function tick() {
  render();
  setTimeout(tick, 1000 - (now() % 1000) + 5);
}

async function start() {
  renderDevBar();
  setupBriefMemory();
  loadBriefs().catch(() => setText($("briefs"), "Couldn't load the Bearkat Brief."));
  try {
    master = await (await fetch("schedule.json", { cache: "no-cache" })).json();
  } catch {
    setText($("eyebrow"), "Couldn't load the schedule");
    setText($("caption"), "Refresh the page to try again.");
    return;
  }
  if (master.updatedAt) {
    const date = new Date(master.updatedAt).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: ZONE });
    setText($("updated"), `Last updated ${date}`);
  }
  tick();
}

start();
