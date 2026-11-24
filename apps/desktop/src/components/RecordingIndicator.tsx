import { Check, Mic, Square, X } from "lucide-react";
import { dictate, useDictation } from "../lib/dictation";

export function RecordingIndicator() {
  const state = useDictation();
  const active = state.phase === "listening" || state.phase === "paused";
  const labels = { starting: "Starting microphone", listening: "Listening", paused: "Paused", transcribing: "Transcribing", idle: state.error ? "See Dictate for details" : state.delivery === true ? "Inserted" : state.delivery === false ? "Ready in Vyrra" : "Ready" };
  return <main className="flex h-screen items-center justify-between gap-2 bg-surface px-3 text-ink">
    <Mic size={19} className="shrink-0" />
    <span role="status" className="min-w-0 flex-1 text-sm font-semibold">{labels[state.phase]}</span>
    {active && <button className="grid size-9 place-items-center rounded-full bg-accent text-on-accent" aria-label="Finish dictation" onClick={() => { void dictate("finish").catch(() => {}); }}><Square size={13} fill="currentColor" /></button>}
    {state.phase !== "idle" ? <button className="grid size-9 place-items-center rounded-full" aria-label="Cancel dictation" onClick={() => { void dictate("cancel").catch(() => {}); }}><X size={16} /></button> : <Check size={17} />}
  </main>;
}
