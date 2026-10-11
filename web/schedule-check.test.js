// Run with `npm test`. Checks the real schedule.json, then makes sure the checker catches mistakes.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { checkSchedule } from "./schedule-check.js";

const real = JSON.parse(readFileSync(new URL("./schedule.json", import.meta.url)));
const copy = () => structuredClone(real);
const found = (master, text) => checkSchedule(master).some((p) => p.includes(text));

test("the real schedule.json has no problems", () => {
  assert.deepEqual(checkSchedule(real), []);
});

test("catches a calendar entry pointing at a schedule that doesn't exist", () => {
  const m = copy();
  m.calendar.push({ start: "2026-12-01", end: "2026-12-01", scheduleID: "pep-raly" });
  assert.ok(found(m, "pep-raly"));
});

test("catches a misspelled key", () => {
  const m = copy();
  m.calendar.push({ start: "2026-12-01", end: "2026-12-01", schedulID: "normal" });
  assert.ok(found(m, 'unknown key "schedulID"'));
});

test("catches a bad or impossible date", () => {
  const m = copy();
  m.calendar.push({ start: "2026-02-30", end: "2026-03-01" });
  assert.ok(found(m, "real YYYY-MM-DD"));
});

test("catches an entry that ends before it starts", () => {
  const m = copy();
  m.calendar.push({ start: "2026-12-05", end: "2026-12-01" });
  assert.ok(found(m, "ends before it starts"));
});

test("catches two same-length calendar entries on one day", () => {
  const m = copy();
  m.calendar.push({ start: "2026-12-01", end: "2026-12-01", scheduleID: "normal" });
  m.calendar.push({ start: "2026-12-01", end: "2026-12-01", scheduleID: "pep-rally" });
  assert.ok(found(m, "coin flip"));
});

test("catches a bad time like 25:00 or 7:5", () => {
  const m = copy();
  m.schedules[0].blocks[0].end = "25:00";
  m.schedules[0].blocks[1].start = "7:5";
  assert.ok(found(m, 'bad end time "25:00"'));
  assert.ok(found(m, 'bad start time "7:5"'));
});

test("catches a block that ends before it starts", () => {
  const m = copy();
  m.schedules[0].blocks[0].end = "07:00";
  assert.ok(found(m, "ends before it starts"));
});

test("catches overlapping blocks for the same lunch", () => {
  const m = copy();
  m.schedules[0].blocks[1].start = "07:30"; // 2nd now starts inside 1st
  assert.ok(found(m, "overlaps"));
});

test("catches a dismiss time outside its block", () => {
  const m = copy();
  const lunch = m.schedules[0].blocks.find((b) => b.dismiss);
  lunch.dismiss = "06:00";
  assert.ok(found(m, "dismisses outside"));
});

test("catches an unknown lunch group", () => {
  const m = copy();
  m.schedules[0].blocks.find((b) => b.groups).groups = ["D"];
  assert.ok(found(m, "unknown lunch"));
});

test("catches a default schedule that doesn't exist", () => {
  const m = copy();
  m.defaultScheduleID = "nope";
  assert.ok(found(m, "defaultScheduleID"));
});

test("catches duplicate schedule ids", () => {
  const m = copy();
  m.schedules[1].id = m.schedules[0].id;
  assert.ok(found(m, "share the id"));
});
