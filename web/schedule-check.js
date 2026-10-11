// Checks schedule.json for mistakes before it goes out to every installed app.
// Run `node schedule-check.js [file]` (defaults to schedule.json); `npm test` runs it too.
// Covers what the app's editor flags (overlaps, bad dismiss times), plus mistakes the app and
// site accept silently: a calendar entry pointing at a schedule that doesn't exist falls back
// to the normal schedule, and a misspelled key like "schedulID" quietly means "no school".
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const LUNCHES = ["A", "B", "C"];
const KEYS = {
  file: ["version", "updatedAt", "defaultScheduleID", "schedules", "calendar"],
  schedule: ["id", "name", "bells", "blocks"],
  bell: ["name", "time"],
  block: ["name", "start", "end", "dismiss", "groups"],
  entry: ["start", "end", "scheduleID", "note"],
};

const timeOK = (t) => typeof t === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(t);
const mins = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3));
const dateOK = (d) => {
  if (typeof d !== "string" || !/^\d{4}-\d\d-\d\d$/.test(d)) return false;
  const [y, m, day] = d.split("-").map(Number);
  const utc = new Date(Date.UTC(y, m - 1, day));
  return utc.getUTCFullYear() === y && utc.getUTCMonth() === m - 1 && utc.getUTCDate() === day;
};
const days = (d) => Date.parse(d + "T00:00:00Z") / 86_400_000;

/// Returns a list of plain-English problems; empty means the file looks fine.
export function checkSchedule(master) {
  const problems = [];
  const unknownKeys = (obj, allowed, where) => {
    for (const key of Object.keys(obj)) {
      if (!allowed.includes(key)) problems.push(`${where}: unknown key "${key}" (typo?)`);
    }
  };

  if (typeof master !== "object" || master === null || Array.isArray(master)) return ["The file isn't an object."];
  unknownKeys(master, KEYS.file, "File");
  if (!Number.isInteger(master.version)) problems.push("version must be a whole number.");
  if (master.updatedAt != null && !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(master.updatedAt)) {
    problems.push(`updatedAt "${master.updatedAt}" isn't a UTC time like 2026-10-10T19:28:32Z.`);
  }
  if (!Array.isArray(master.schedules) || master.schedules.length === 0) {
    return [...problems, "schedules must be a list with at least one schedule."];
  }
  if (!Array.isArray(master.calendar)) return [...problems, "calendar must be a list."];

  const ids = master.schedules.map((s) => s.id);
  ids.forEach((id, i) => {
    if (typeof id !== "string" || id === "") problems.push(`Schedule #${i + 1} has no id.`);
    else if (ids.indexOf(id) !== i) problems.push(`Two schedules share the id "${id}".`);
  });
  if (!ids.includes(master.defaultScheduleID)) {
    problems.push(`defaultScheduleID "${master.defaultScheduleID}" doesn't match any schedule.`);
  }

  for (const schedule of master.schedules) {
    const where = `Schedule "${schedule.id}"`;
    unknownKeys(schedule, KEYS.schedule, where);
    if (typeof schedule.name !== "string" || schedule.name.trim() === "") problems.push(`${where} has no name.`);
    if (!Array.isArray(schedule.blocks) || schedule.blocks.length === 0) {
      problems.push(`${where} has no blocks.`);
      continue;
    }

    for (const bell of schedule.bells ?? []) {
      unknownKeys(bell, KEYS.bell, `${where}, bell "${bell.name}"`);
      if (!timeOK(bell.time)) problems.push(`${where}: bell "${bell.name}" has a bad time "${bell.time}".`);
    }

    const valid = [];
    for (const block of schedule.blocks) {
      const name = `${where}: ${block.name} (${block.start})`;
      unknownKeys(block, KEYS.block, name);
      if (typeof block.name !== "string" || block.name.trim() === "") problems.push(`${name} has no name.`);
      const times = ["start", "end", ...(block.dismiss == null ? [] : ["dismiss"])];
      const badTimes = times.filter((k) => !timeOK(block[k]));
      for (const k of badTimes) problems.push(`${name} has a bad ${k} time "${block[k]}".`);
      if (badTimes.length > 0) continue;

      if (mins(block.end) <= mins(block.start)) problems.push(`${name} ends before it starts.`);
      if (block.dismiss != null && !(mins(block.start) < mins(block.dismiss) && mins(block.dismiss) <= mins(block.end))) {
        problems.push(`${name} dismisses outside its own time.`);
      }
      if (block.groups != null) {
        if (!Array.isArray(block.groups) || block.groups.length === 0) {
          problems.push(`${name} has an empty groups list. Leave "groups" out to mean every lunch.`);
        } else if (block.groups.some((g) => !LUNCHES.includes(g))) {
          problems.push(`${name} has an unknown lunch in groups: ${JSON.stringify(block.groups)}.`);
        }
      }
      valid.push(block);
    }

    for (const lunch of LUNCHES) {
      const mine = valid
        .filter((b) => !Array.isArray(b.groups) || b.groups.includes(lunch))
        .sort((a, b) => mins(a.start) - mins(b.start));
      if (mine.length === 0) problems.push(`${where}: ${lunch} Lunch has no blocks.`);
      for (let i = 1; i < mine.length; i++) {
        if (mins(mine[i - 1].end) > mins(mine[i].start)) {
          problems.push(`${where}, ${lunch} Lunch: ${mine[i - 1].name} overlaps ${mine[i].name}.`);
        }
      }
    }
  }

  const entries = [];
  for (const entry of master.calendar) {
    const where = `Calendar ${entry.start ?? "?"} to ${entry.end ?? "?"}`;
    unknownKeys(entry, KEYS.entry, where);
    if (!dateOK(entry.start) || !dateOK(entry.end)) {
      problems.push(`${where} has a date that isn't a real YYYY-MM-DD day.`);
      continue;
    }
    if (days(entry.end) < days(entry.start)) problems.push(`${where} ends before it starts.`);
    // No scheduleID means no school. A wrong one doesn't fail loudly: it falls back to normal.
    if (entry.scheduleID != null && !ids.includes(entry.scheduleID)) {
      problems.push(`${where} uses "${entry.scheduleID}", which isn't a schedule. It would fall back to the normal one.`);
    }
    entries.push(entry);
  }
  // The shortest entry wins, so two with the same length that share a day can't be sorted out.
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      const a = entries[i], b = entries[j];
      const overlap = days(a.start) <= days(b.end) && days(b.start) <= days(a.end);
      const sameLength = days(a.end) - days(a.start) === days(b.end) - days(b.start);
      if (overlap && sameLength) {
        problems.push(`Calendar ${a.start} to ${a.end} and ${b.start} to ${b.end} cover the same day and are the same length, so it's a coin flip.`);
      }
    }
  }
  return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const path = process.argv[2] ?? fileURLToPath(new URL("./schedule.json", import.meta.url));
  let master;
  try {
    master = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    console.error(`${path} isn't valid JSON: ${error.message}`);
    process.exit(1);
  }
  const problems = checkSchedule(master);
  if (problems.length === 0) console.log(`${path}: OK`);
  else {
    console.error(`${path}: ${problems.length} problem${problems.length === 1 ? "" : "s"}`);
    for (const p of problems) console.error(`  - ${p}`);
    process.exit(1);
  }
}
