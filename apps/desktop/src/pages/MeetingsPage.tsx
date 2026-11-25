import { useCallback, useEffect, useRef, useState } from "react";
import {
  Calendar,
  CalendarPlus,
  CalendarDays,
  Check,
  Download,
  FileUp,
  RefreshCw,
  Settings2,
  Square,
  Trash2,
  X,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { Button, EmptyState, PageHeader } from "../components/ui";
import { QuietIcon } from "../components/QuietIcon";
import { WritingTools } from "../components/WritingTools";
import { isNativeDesktop } from "../lib/native";
import { message, panelSound } from "../lib/dictation";
import {
  calendarCalls,
  isFinal,
  meetings,
  phaseName,
  type MeetingEvent,
  type MeetingMode,
  type MeetingPlan,
  type MeetingView,
} from "../lib/meetings";
const field =
  "w-full rounded-control border border-line bg-canvas-subtle p-2 text-sm text-ink";
const when = (time: number) =>
  new Date(time).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
function AddMeeting({
  view,
  done,
}: {
  view: MeetingView;
  done: () => Promise<void>;
}) {
  const [items, setItems] = useState<MeetingEvent[]>([]),
    [pick, setPick] = useState(""),
    [owner, setOwner] = useState(""),
    [file, setFile] = useState(""),
    [loaded, setLoaded] = useState(false),
    [mode, setMode] = useState<MeetingMode>("local"),
    [consent, setConsent] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const input = useRef<HTMLInputElement>(null);
  const mac = view.sources.some(([id]) => id === "com.apple.Safari");
  const localSource = view.sources.find(
    ([id]) => id === view.profile.source,
  )?.[1];
  const show = (events: MeetingEvent[]) => {
    setLoaded(true);
    const available = events.filter((e) => e.startMs > Date.now());
    setItems(available);
    setPick(available[0]?.uid ?? "");
    setConsent(false);
  };
  async function run(f: () => Promise<void>) {
    setError("");
    setBusy(true);
    try {
      await f();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form
      className="quiet-panel space-y-4 rounded-control border border-line bg-surface p-4"
      onSubmit={(e) => {
        e.preventDefault();
        const event = items.find((i) => i.uid === pick);
        if (event && consent)
          void run(async () => {
            await invoke("meeting_schedule", { event, mode });
            await done();
          });
      }}
    >
      <div className="flex items-center gap-2">
        {mac && (
          <Button
            variant="secondary"
            disabled={busy}
            onClick={() =>
              void run(async () => {
                setFile("");
                show(await invoke<MeetingEvent[]>("meeting_calendar"));
              })
            }
          >
            <Calendar size={15} />
            Choose from Calendar
          </Button>
        )}
        <Button
          variant="quiet"
          disabled={busy}
          onClick={() => input.current?.click()}
        >
          <FileUp size={15} />
          Import .ics
        </Button>
        <input
          type="file"
          ref={input}
          className="hidden"
          accept=".ics,text/calendar"
          aria-label="Calendar file"
          onChange={(e) => {
            const chosen = e.target.files?.[0];
            if (chosen)
              void run(async () => {
                if (chosen.size > 2_000_000)
                  throw new Error("Choose a calendar file under 2 MB.");
                const text = await chosen.text();
                setFile(text);
                show(calendarCalls(text, owner));
              });
            e.target.value = "";
          }}
        />
      </div>
      {file && (
        <label className="block text-xs text-ink-soft">
          Your calendar email
          <input
            type="email"
            className={field}
            placeholder="For invitations with an RSVP"
            value={owner}
            onChange={(e) => {
              setOwner(e.target.value);
              try {
                show(calendarCalls(file, e.target.value));
              } catch (err) {
                setError(message(err));
              }
            }}
          />
        </label>
      )}
      {items.length > 0 ? (
        <>
          <label className="block text-xs text-ink-soft">
            Meeting
            <select
              className={field}
              value={pick}
              onChange={(e) => {
                setPick(e.target.value);
                setConsent(false);
              }}
            >
              {items.map((e) => (
                <option value={e.uid} key={e.uid}>
                  {e.title} · {when(e.startMs)}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs text-ink-soft">
            Join with
            <select
              className={field}
              value={mode}
              onChange={(e) => {
                setMode(e.target.value as MeetingMode);
                setConsent(false);
              }}
            >
              <option value="local">This computer</option>
              <option value="participant">
                {view.profile.name} · self-hosted participant
              </option>
            </select>
          </label>
          <label className="flex items-start gap-2 text-sm text-ink">
            <input
              type="checkbox"
              className="mt-1"
              checked={consent}
              onChange={(e) => setConsent(e.target.checked)}
            />
            {mode === "local"
              ? `Open this call at its start and take notes from my microphone and ${localSource ?? "meeting audio"}. I’ll let everyone know.`
              : `Send this call, participant name, and picture to my server. The participant will announce that it takes notes.`}
          </label>
          {mode === "participant" && !view.profile.server ? (
            <a className="text-sm underline" href="#/settings/meetings">
              Set up participant server
            </a>
          ) : (
            <Button type="submit" disabled={busy || !consent}>
              Schedule
            </Button>
          )}
        </>
      ) : (
        loaded && (
          <p role="status" className="text-sm text-ink-soft">
            No upcoming accepted calls found.
          </p>
        )
      )}
      {error && (
        <p role="alert" className="text-sm text-ink-soft">
          {error}
        </p>
      )}
    </form>
  );
}
function MeetingRow({
  plan,
  reload,
}: {
  plan: MeetingPlan;
  reload: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false),
    [del, setDel] = useState(false),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const closed = isFinal(plan.phase);
  async function run(op: () => Promise<unknown>) {
    setBusy(true);
    setError("");
    try {
      await op();
      await reload();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  const action = (action: string) =>
    run(() => invoke("meeting_action", { key: plan.key, action }));
  return (
    <article className="vyrra-transcript" data-open={open}>
      <div className="vyrra-transcript-row">
        <button
          className="vyrra-row-summary flex-1 flex-col items-start text-left"
          type="button"
          aria-expanded={open}
          onClick={() => {panelSound(open);setOpen(!open);}}
        >
          <span className="block truncate text-sm font-medium text-ink">
            {plan.event.title}
          </span>
          <span className="text-xs text-ink-soft">
            {when(plan.event.startMs)} · {phaseName(plan.phase)}
          </span>
        </button>
        <div className="vyrra-row-actions">
          {plan.mode === "participant" && !closed && (
            <QuietIcon
              icon={RefreshCw}
              label="Refresh participant"
              disabled={busy}
              onClick={() => void action("refresh")}
            />
          )}
          {closed ? (
            <QuietIcon
              icon={Trash2}
              label="Delete meeting notes"
              onClick={() => {
                setOpen(true);
                setDel(true);
              }}
            />
          ) : (
            <QuietIcon
              icon={Square}
              label={
                plan.phase === "scheduled"
                  ? "Cancel scheduled meeting"
                  : "Stop meeting notes"
              }
              disabled={busy}
              onClick={() => void action("stop")}
            />
          )}
        </div>
      </div>
      {open && (
        <div className="quiet-panel space-y-3 p-3">
          {plan.notes && (
            <p className="whitespace-pre-wrap text-sm text-ink">{plan.notes}</p>
          )}
          {plan.transcript ? (
            <>
              <details>
                <summary className="text-sm text-ink-soft">Transcript</summary>
                <p className="whitespace-pre-wrap py-2 text-sm text-ink">
                  {plan.transcript}
                </p>
              </details>
              <div className="flex items-center gap-1">
                <QuietIcon
                  icon={Download}
                  label="Export meeting notes and transcript"
                  onClick={() =>
                    void run(() =>
                      invoke("dictation_export", {
                        text: [plan.event.title, plan.notes, plan.transcript]
                          .filter(Boolean)
                          .join("\n\n"),
                      }),
                    )
                  }
                />
                <WritingTools source={plan.transcript} initial="meetingNotes" />
              </div>
            </>
          ) : (
            <p className="text-sm text-ink-soft">
              {closed
                ? "No transcript was captured."
                : plan.mode === "local"
                  ? "Keep Vyrra open until the call ends."
                  : "Your server manages this participant."}
            </p>
          )}
          {del && (
            <div className="flex items-center gap-2">
              <Button
                variant="danger"
                disabled={busy}
                onClick={() => void action("delete")}
              >
                Delete local notes
              </Button>
              <QuietIcon
                icon={X}
                label="Keep meeting notes"
                onClick={() => setDel(false)}
              />
            </div>
          )}
        </div>
      )}
      {(error || plan.error) && (
        <p role="status" className="px-3 py-2 text-xs text-ink-soft">
          {error || plan.error}
        </p>
      )}
    </article>
  );
}
export function MeetingsPage() {
  const [view, setView] = useState<MeetingView>(),
    [adding, setAdding] = useState(false),
    [error, setError] = useState("");
  const native = isNativeDesktop();
  const reload = useCallback(async () => {
    setView(await meetings());
    setError("");
  }, []);
  useEffect(() => {
    if (!native) return;
    let mounted = true;
    const read = () =>
      meetings()
        .then((data) => {
          if (mounted) {
            setView(data);
            setError("");
          }
        })
        .catch((e) => {
          if (mounted) setError(message(e));
        });
    void read();
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") void read();
    }, 3500);
    return () => {
      mounted = false;
      clearInterval(timer);
    };
  }, [native]);
  return (
    <div className="space-y-5">
      <PageHeader
        title="Meetings"
        actions={
          <div className="flex items-center gap-1">
            <QuietIcon
              label="Meeting settings"
              icon={Settings2}
              onClick={() => {
                window.location.hash = "/settings/meetings";
              }}
            />
            <QuietIcon
              label={adding ? "Close meeting picker" : "Schedule a meeting"}
              icon={adding ? X : CalendarPlus}
              aria-expanded={adding}
              disabled={!view}
              onClick={() => {panelSound(adding);setAdding(!adding);}}
            />
          </div>
        }
      />
      {error && <p role="alert">{error}</p>}
      {adding && view && (
        <AddMeeting
          view={view}
          done={async () => {
            await reload();
            setAdding(false);
          }}
        />
      )}
      {view?.plans.length ? (
        <div className="vyrra-transcript-list">
          {view.plans.map((p) => (
            <MeetingRow key={p.key} plan={p} reload={reload} />
          ))}
        </div>
      ) : native && !view && !error ? (
        <p role="status">Loading meetings…</p>
      ) : (
        <EmptyState
          icon={<CalendarDays size={22} />}
          title="No meetings yet"
          description="Choose a calendar call to take notes."
        />
      )}
    </div>
  );
}
export function MeetingIndicator() {
  const [phase, setPhase] = useState("opening");
  useEffect(() => {
    let mounted = true;
    const read = () =>
      void invoke<string>("meeting_indicator_phase")
        .then((p) => {
          if (mounted) setPhase(p);
        })
        .catch(() => {});
    read();
    const id = setInterval(read, 600);
    return () => {
      mounted = false;
      clearInterval(id);
    };
  }, []);
  return (
    <main className="flex h-screen items-center justify-between gap-2 bg-surface px-3 text-ink">
      <Calendar size={18} />
      <span role="status" className="text-sm font-medium">
        {phase === "taking_notes" ? "Taking meeting notes" : "Opening meeting"}
      </span>
      <QuietIcon
        label="Stop meeting notes"
        icon={Check}
        onClick={() => void invoke("meeting_stop_active")}
      />
    </main>
  );
}
