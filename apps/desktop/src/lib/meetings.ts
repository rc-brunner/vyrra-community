import { invoke } from "@tauri-apps/api/core";
import ICAL from "ical.js";
export interface MeetingEvent {
  uid: string;
  title: string;
  url: string;
  startMs: number;
  endMs: number;
}
export type MeetingMode = "local" | "participant";
export interface MeetingPlan {
  key: string;
  event: MeetingEvent;
  mode: MeetingMode;
  phase: string;
  source: string;
  server: string;
  remote: string | null;
  transcript: string;
  notes: string;
  error: string | null;
}
export interface ParticipantProfile {
  name: string;
  server: string;
  source: string;
  image: string | null;
}
export interface MeetingView {
  profile: ParticipantProfile;
  avatar: string;
  sources: [string, string][];
  plans: MeetingPlan[];
}
export const meetings = () => invoke<MeetingView>("meeting_list");
export const isFinal = (phase: string) =>
  [
    "ended",
    "missed",
    "canceled",
    "interrupted",
    "failed",
    "fatal_error",
    "data_deleted",
  ].includes(phase);
const phaseNames: Record<string, string> = {
  scheduled: "Scheduled",
  staged: "Ready to join",
  scheduling: "Scheduling",
  opening: "Opening call",
  taking_notes: "Taking notes",
  waiting_room: "Waiting for the host",
  joining: "Joining",
  ready: "Ready to join",
  joined_not_recording: "In the call",
  joined_recording: "Taking notes",
  joined_recording_paused: "Notes paused",
  joined_recording_permission_denied: "Host declined recording",
  post_processing: "Finishing notes",
  leaving: "Leaving",
  ended: "Finished",
  interrupted: "Interrupted",
  fatal_error: "Couldn’t join",
  failed: "Couldn’t take notes",
  missed: "Missed",
  canceled: "Canceled",
  data_deleted: "Removed",
};
export const phaseName = (phase: string) =>
  phaseNames[phase] ?? phase.replaceAll("_", " ");
export function meetingLink(value: string) {
  try {
    const u = new URL(value);
    if (u.protocol !== "https:" || u.username || u.password || u.port)
      return false;
    if (u.hostname === "meet.google.com")
      return /^\/[a-z]{3}-[a-z]{4}-[a-z]{3}\/?$/.test(u.pathname);
    if (/(^|\.)zoom(gov\.com|\.us)$/.test(u.hostname))
      return /^\/(j|w|my)\/[^/]+$/.test(u.pathname);
    return (
      [
        "teams.microsoft.com",
        "teams.live.com",
        "teams.cloud.microsoft",
      ].includes(u.hostname) && /^\/(l\/meetup-join|meet)\/.+/.test(u.pathname)
    );
  } catch {
    return false;
  }
}
// Calendar exports sometimes name an IANA timezone without embedding VTIMEZONE.
function calendarTime(t: InstanceType<typeof ICAL.Time>, tzid: unknown): number {
  if(t.zone.tzid !== "floating") return t.toUnixTime()*1000;
  if(!tzid) return new Date(t.year,t.month-1,t.day,t.hour,t.minute,t.second).getTime();
  const local=Date.UTC(t.year,t.month-1,t.day,t.hour,t.minute,t.second);
  let instant=local;
  try {
    const format=new Intl.DateTimeFormat("en-US",{timeZone:String(tzid),timeZoneName:"longOffset"});
    for(let i=0;i<3;i++) {
      const offset=format.formatToParts(instant).find(p=>p.type==="timeZoneName")?.value??"GMT";
      const match=/GMT([+-])(\d{2}):(\d{2})/.exec(offset);
      const delta=match?(match[1]==="+"?1:-1)*(Number(match[2])*60+Number(match[3]))*60000:0;
      const next=local-delta;if(next===instant)break;instant=next;
    }
  } catch {throw new Error("This file uses an unknown time zone. Export it with time zone information or use Calendar.");}
  return instant;
}
/** Import a bounded preview. Recurrence exceptions and timezone components apply only to this file. */
export function calendarCalls(
  text: string,
  owner: string,
  now = Date.now(),
): MeetingEvent[] {
  if (text.length > 2_000_000)
    throw new Error("Choose a calendar file under 2 MB.");
  const root = new ICAL.Component(ICAL.parse(text));
  if (root.name !== "vcalendar")
    throw new Error("Choose an iCalendar (.ics) file.");
  if(String(root.getFirstPropertyValue("method")).toUpperCase()==="CANCEL") return [];
  let budget=50000;
  const horizon = now + 90 * 86400000,
    calls = new Map<string, MeetingEvent>();
  const email = owner.trim().toLowerCase();
  const components = root.getAllSubcomponents("vevent");
  for (const component of components) {
    if (
      component.hasProperty("recurrence-id") ||
      !component.hasProperty("dtstart")
    )
      continue;
    const event = new ICAL.Event(component, {
      exceptions: components.filter(
        (c) =>
          c.hasProperty("recurrence-id") &&
          c.getFirstPropertyValue("uid") ===
            component.getFirstPropertyValue("uid"),
      ),
    });
    if (event.startDate.isDate) continue;
    const iterator = event.iterator();
    for (let i = 0; i < 20000; i++) {
      if(--budget<0) throw new Error("Choose a smaller calendar export for this date range.");
      const date = iterator.next();
      if (!date || calendarTime(date,component.getFirstProperty("dtstart")?.getParameter("tzid"))>horizon) break;
      const single=event.getOccurrenceDetails(date), item=single.item.component;
      const tz=(name:string)=>item.getFirstProperty(name)?.getParameter("tzid") ?? component.getFirstProperty(name)?.getParameter("tzid");
      const start=calendarTime(single.startDate,tz("dtstart")),end=calendarTime(single.endDate,tz("dtend")??tz("dtstart"));
      if (start >= now && end > start) {
        const item = single.item.component,
          value = (name: string) =>
            String(
              item.getFirstPropertyValue(name) ??
                component.getFirstPropertyValue(name) ??
                "",
            );
        const guests = item.hasProperty("attendee")
          ? item.getAllProperties("attendee")
          : component.getAllProperties("attendee");
        const norm = (s: unknown) =>
          String(s ?? "")
            .toLowerCase()
            .replace(/^mailto:/, "");
        const self = guests.find((p) => norm(p.getFirstValue()) === email);
        const status = String(
          self?.getParameter("partstat") ?? "",
        ).toUpperCase();
        if (
          value("status").toUpperCase() !== "CANCELLED" &&
          (guests.length === 0 ||
            (email &&
              (status === "ACCEPTED" || norm(value("organizer")) === email)))
        ) {
          const fields = [
            "conference",
            "x-google-conference",
            "x-microsoft-skypeteamsmeetingurl",
            "url",
            "location",
            "description",
          ];
          const urls = fields.flatMap(
            (name) => value(name).match(/https:\/\/[^\s<>"\])]+/gi) ?? [],
          );
          const url = urls
            .map((s) => s.replace(/[.,;]+$/, ""))
            .find(meetingLink);
          if (url) {
            const uid = `ics:${event.uid}/${event.isRecurring() ? date.toString() : "single"}`;
            calls.set(uid, {
              uid,
              title: single.item.summary || event.summary || "Meeting",
              url,
              startMs: start,
              endMs: end,
            });
          }
        }
      }
      if (!event.isRecurring() || calls.size >= 250) break;
    }
    if (calls.size >= 250) break;
  }
  return [...calls.values()].sort((a, b) => a.startMs - b.startMs);
}
