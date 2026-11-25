import {describe,expect,it} from "vitest";
import {calendarCalls,meetingLink} from "./meetings";
const ics=(...props:string[])=>["BEGIN:VCALENDAR","VERSION:2.0","BEGIN:VEVENT","UID:studio-series","SUMMARY:Studio standup","URL:https://meet.google.com/aaa-bbbb-ccc",...props,"END:VEVENT","END:VCALENDAR"].join("\r\n");
const now=Date.parse("2027-03-12T00:00Z");
describe("meeting calendar import",()=>{
  it("only offers the owner’s accepted invitations and preserves local time across DST",()=>{
    const data=ics("DTSTART;TZID=America/New_York:20270313T090000","DTEND;TZID=America/New_York:20270313T093000","RRULE:FREQ=DAILY;COUNT=3","ATTENDEE;PARTSTAT=ACCEPTED:mailto:studio@example.test","ATTENDEE;PARTSTAT=DECLINED:mailto:other@example.test");
    expect(calendarCalls(data,"other@example.test",now)).toEqual([]);expect(calendarCalls(data,"",now)).toEqual([]);
    const calls=calendarCalls(data,"Studio@example.test",now);expect(calls.map(e=>new Date(e.startMs).toISOString())).toEqual(["2027-03-13T14:00:00.000Z","2027-03-14T13:00:00.000Z","2027-03-15T13:00:00.000Z"]);expect(new Set(calls.map(c=>c.uid)).size).toBe(3);
  });
  it("respects exclusions and cancellation, rejects unrelated URLs",()=>{
    const data=ics("DTSTART:20270313T090000Z","DTEND:20270313T093000Z","RRULE:FREQ=DAILY;COUNT=3","EXDATE:20270314T090000Z");expect(calendarCalls(data,"",now)).toHaveLength(2);
    expect(calendarCalls(data.replace("SUMMARY:","STATUS:CANCELLED\r\nSUMMARY:"),"",now)).toEqual([]);
    expect(calendarCalls(data.replace("meet.google.com","meet.google.com.unrelated.test"),"",now)).toEqual([]);
    expect(meetingLink("https://zoom.us@unrelated.test/j/12")).toBe(false);
  });
});
