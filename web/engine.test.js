// Run with `npm test` (needs Node 20+). Mirrors ScheduleCountdownTests/ScheduleEngineTests.swift,
// using the real schedule.json with the calendar swapped out so the tests don't depend on school breaks.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  instantAt, wallClock, addDays, weekday, minutes, display,
  scheduleOn, blocksFor, status, nextSchoolBell, formatCountdown,
} from "./engine.js";

const bundled = JSON.parse(readFileSync(new URL("./schedule.json", import.meta.url)));

// Week of Oct 5, 2026: Mon 5 … Fri 9, Sat 10, Sun 11.
const at = (day, hour, minute) => instantAt(day, hour * 60 + minute);
const engine = (calendar = []) => ({ ...bundled, calendar });
const assign = (scheduleID, start, end = start) => ({ start, end, scheduleID });

const MON = "2026-10-05", WED = "2026-10-07", THU = "2026-10-08", FRI = "2026-10-09", SAT = "2026-10-10";

/// Status at a Klein wall-clock time, plus what the page shows: the period name or Passing.
function at_(master, day, hour, minute, lunch) {
  const st = status(master, at(day, hour, minute), lunch);
  return { ...st, label: st.current?.name ?? (st.inSession ? "Passing" : null) };
}

// --- Time and dates --------------------------------------------------------

test("Klein time ignores the device's time zone", () => {
  // 7:09 on Oct 8 in Klein (CDT, UTC−5) is 12:09 UTC.
  assert.equal(at(THU, 7, 9), Date.UTC(2026, 9, 8, 12, 9));
  assert.deepEqual(wallClock(Date.UTC(2026, 9, 8, 12, 9, 30)), { day: THU, seconds: 7 * 3600 + 9 * 60 + 30 });
});

test("the Klein day changes at midnight Klein time, not UTC", () => {
  assert.equal(wallClock(Date.UTC(2026, 9, 9, 3, 30)).day, THU); // 10:30 pm Thursday in Klein
  assert.equal(wallClock(Date.UTC(2026, 9, 9, 5, 30)).day, FRI); // 12:30 am Friday in Klein
});

test("bells follow daylight saving time", () => {
  assert.equal(at("2026-03-06", 7, 9), Date.UTC(2026, 2, 6, 13, 9)); // before spring forward: CST
  assert.equal(at("2026-03-09", 7, 9), Date.UTC(2026, 2, 9, 12, 9)); // after: CDT
  assert.equal(at("2026-10-30", 7, 9), Date.UTC(2026, 9, 30, 12, 9)); // before fall back: CDT
  assert.equal(at("2026-11-02", 7, 9), Date.UTC(2026, 10, 2, 13, 9)); // after: CST
});

test("date helpers", () => {
  assert.equal(addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(addDays("2026-03-01", -1), "2026-02-28");
  assert.equal(weekday(SAT), 6);
  assert.equal(weekday(MON), 1);
  assert.equal(minutes("07:15"), 435);
  assert.equal(display(435), "7:15");
  assert.equal(display(780), "1:00");
  assert.equal(display(0), "12:00");
});

// --- Picking the day's schedule --------------------------------------------

test("weekdays use the default schedule", () => {
  assert.equal(scheduleOn(engine(), THU).schedule.id, "normal");
});

test("weekends have no school", () => {
  assert.equal(scheduleOn(engine(), SAT).schedule, null);
  const st = at_(engine(), SAT, 9, 0, "A");
  assert.equal(st.schedule, null);
  assert.equal(st.inSession, false);
  assert.equal(st.nextBell, null);
});

test("the calendar assigns alternate schedules and notes", () => {
  const m = engine([{ ...assign("jamboree", FRI), note: "Homecoming" }]);
  assert.deepEqual([scheduleOn(m, FRI).schedule.id, scheduleOn(m, FRI).note], ["jamboree", "Homecoming"]);
  assert.equal(scheduleOn(m, THU).schedule.id, "normal");
});

test("no-school ranges cover every day in them", () => {
  const m = engine([assign(null, "2026-11-23", "2026-11-27")]);
  for (let d = 23; d <= 27; d++) assert.equal(scheduleOn(m, `2026-11-${d}`).schedule, null);
  assert.equal(scheduleOn(m, "2026-11-30").schedule.id, "normal");
});

test("a single day beats the range around it", () => {
  const m = engine([assign(null, "2026-12-14", "2026-12-18"), assign("pep-rally", "2026-12-16")]);
  assert.equal(scheduleOn(m, "2026-12-16").schedule.id, "pep-rally");
  assert.equal(scheduleOn(m, "2026-12-15").schedule, null);
});

test("an unknown schedule falls back to the default", () => {
  assert.equal(scheduleOn(engine([assign("deleted-schedule", FRI)]), FRI).schedule.id, "normal");
});

// --- Normal schedule -------------------------------------------------------

test("before the release bell is outside school hours", () => {
  const st = at_(engine(), THU, 7, 0, "A");
  assert.equal(st.inSession, false);
  assert.equal(st.label, null);
  assert.equal(st.nextBell.at, at(THU, 7, 9));
});

test("the release bell starts passing", () => {
  const st = at_(engine(), THU, 7, 10, "B");
  assert.equal(st.label, "Passing");
  assert.equal(st.nextBell.at, at(THU, 7, 15));
  assert.equal(st.next.name, "1st");
});

test("in class counts down to the end of the period", () => {
  const st = at_(engine(), THU, 10, 0, "C");
  assert.equal(st.label, "4th");
  assert.equal(st.nextBell.at, at(THU, 10, 45));
  assert.equal(st.next.name, "Advisory");
});

test("A lunch counts down to the dismiss bell", () => {
  const st = at_(engine(), THU, 11, 45, "A");
  assert.equal(st.label, "A Lunch");
  assert.equal(st.nextBell.at, at(THU, 11, 47));
});

test("after the A lunch dismiss bell it's passing until 5th", () => {
  const st = at_(engine(), THU, 11, 47, "A");
  assert.equal(st.label, "Passing");
  assert.equal(st.nextBell.at, at(THU, 11, 52));
});

test("B and C have passing after advisory", () => {
  for (const lunch of ["B", "C"]) {
    const st = at_(engine(), THU, 11, 25, lunch);
    assert.equal(st.label, "Passing");
    assert.equal(st.nextBell.at, at(THU, 11, 28));
  }
});

test("B lunch is split around lunch", () => {
  const m = engine();
  assert.equal(at_(m, THU, 11, 40, "B").nextBell.at, at(THU, 11, 52));
  assert.equal(at_(m, THU, 12, 0, "B").label, "B Lunch");
  assert.equal(at_(m, THU, 12, 0, "B").nextBell.at, at(THU, 12, 17));
  assert.equal(at_(m, THU, 12, 30, "B").label, "5th");
});

test("C lunch dismisses at 12:47", () => {
  const st = at_(engine(), THU, 12, 30, "C");
  assert.equal(st.label, "C Lunch");
  assert.equal(st.nextBell.at, at(THU, 12, 47));
});

test("everyone meets at 6th", () => {
  for (const lunch of ["A", "B", "C"]) {
    const st = at_(engine(), THU, 12, 50, lunch);
    assert.equal(st.label, "Passing");
    assert.equal(st.nextBell.at, at(THU, 12, 53));
  }
});

test("the last bell ends the day", () => {
  const st = at_(engine(), THU, 14, 35, "A");
  assert.equal(st.inSession, false);
  assert.equal(st.label, null);
  assert.equal(st.nextBell, null);
});

test("finished blocks are the ones you've already left", () => {
  assert.deepEqual(at_(engine(), THU, 10, 0, "C").finished.map((b) => b.name), ["1st", "2nd", "3rd"]);
});

test("a lunch only lists its own blocks", () => {
  const normal = bundled.schedules.find((s) => s.id === "normal");
  assert.deepEqual(blocksFor(normal, "A").map((b) => b.name), ["1st", "2nd", "3rd", "4th", "Advisory", "A Lunch", "5th", "6th", "7th"]);
  assert.deepEqual(blocksFor(normal, "B").map((b) => b.name), ["1st", "2nd", "3rd", "4th", "Advisory", "5th", "B Lunch", "5th", "6th", "7th"]);
});

// --- Alternate schedules ---------------------------------------------------

test("jamboree A lunch has passing before 5th", () => {
  const m = engine([assign("jamboree", FRI)]);
  const st = at_(m, FRI, 11, 18, "A");
  assert.equal(st.schedule.name, "Jamboree");
  assert.equal(st.label, "Passing");
  assert.equal(st.nextBell.at, at(FRI, 11, 22));
});

test("jamboree C lunch runs into passing", () => {
  const m = engine([assign("jamboree", FRI)]);
  assert.equal(at_(m, FRI, 12, 20, "C").label, "C Lunch → Jamboree");
  assert.equal(at_(m, FRI, 12, 55, "C").nextBell.at, at(FRI, 12, 59));
});

test("pep rally transition and rally", () => {
  const m = engine([assign("pep-rally", WED)]);
  assert.equal(at_(m, WED, 10, 40, "B").label, "Transition to Field");
  assert.equal(at_(m, WED, 11, 0, "B").label, "Pep Rally");
  assert.equal(at_(m, WED, 11, 0, "B").nextBell.at, at(WED, 11, 18));
  assert.equal(at_(m, WED, 11, 20, "B").label, "Passing");
});

test("pep rally C lunch dismissal", () => {
  const m = engine([assign("pep-rally", WED)]);
  assert.equal(at_(m, WED, 12, 50, "C").nextBell.at, at(WED, 12, 53));
  assert.equal(at_(m, WED, 12, 55, "C").nextBell.at, at(WED, 12, 59));
});

// --- Looking ahead ---------------------------------------------------------

test("the next bell skips the weekend", () => {
  assert.equal(nextSchoolBell(engine(), at(FRI, 15, 0), "A").at, at("2026-10-12", 7, 9));
});

test("the next bell skips no-school days", () => {
  const m = engine([assign(null, "2026-10-12", "2026-10-13")]);
  const next = nextSchoolBell(m, at(FRI, 15, 0), "A");
  assert.equal(next.at, at("2026-10-14", 7, 9));
  assert.equal(next.day, "2026-10-14");
});

test("the next bell is null when nothing is coming", () => {
  const m = engine([assign(null, "2026-10-01", "2027-12-31")]);
  assert.equal(nextSchoolBell(m, at(THU, 15, 0), "A"), null);
});

test("before school the next bell is today's", () => {
  assert.equal(nextSchoolBell(engine(), at(MON, 6, 0), "A").day, MON);
});

// --- Formatting ------------------------------------------------------------

test("countdown formats", () => {
  assert.equal(formatCountdown(299), "4:59");
  assert.equal(formatCountdown(298.2), "4:59");
  assert.equal(formatCountdown(723), "12:03");
  assert.equal(formatCountdown(3723), "1:02:03");
  assert.equal(formatCountdown(2 * 86_400 + 3 * 3600 + 5), "2d 3h");
  assert.equal(formatCountdown(-5), "0:00");
});
