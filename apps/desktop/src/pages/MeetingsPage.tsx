import { useState } from "react";
import {
  ArchiveRestore,
  AudioLines,
  Captions,
  CheckCircle2,
  CircleAlert,
  Clock3,
  FileWarning,
  LoaderCircle,
  MessageSquareText,
  NotebookTabs,
  PauseCircle,
  Search,
  ScanSearch,
  Upload,
  UsersRound,
  VolumeX,
  WandSparkles,
  WifiOff,
} from "lucide-react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  InlineNotice,
  PageHeader,
  SectionHeading,
} from "../components/ui";
import { cn } from "../lib/cn";

const meetingStates = [
  {
    id: "processing",
    label: "Processing",
    title: "Finalization in progress",
    detail: "Buffers are draining; ready is not reported yet.",
    tone: "info" as const,
    icon: LoaderCircle,
  },
  {
    id: "offline",
    label: "Offline",
    title: "Local route preserved",
    detail: "Network is unavailable and cloud fallback remains denied.",
    tone: "success" as const,
    icon: WifiOff,
  },
  {
    id: "recoverable",
    label: "Recoverable",
    title: "Incomplete journal found",
    detail: "Integrity must be validated before recovery choices appear.",
    tone: "warning" as const,
    icon: ArchiveRestore,
  },
  {
    id: "terminal",
    label: "Terminal",
    title: "Session is incomplete",
    detail: "A redacted diagnosis and safe cleanup path remain visible.",
    tone: "danger" as const,
    icon: FileWarning,
  },
] as const;

type MeetingStateId = (typeof meetingStates)[number]["id"];

export function MeetingsPage() {
  const [selectedState, setSelectedState] =
    useState<MeetingStateId>("recoverable");
  const activeState =
    meetingStates.find((state) => state.id === selectedState) ??
    meetingStates[0];
  const ActiveIcon = activeState.icon;

  return (
    <div className="space-y-9">
      <PageHeader
        eyebrow="Meetings"
        title="Your local record, with no invented history."
        description="Real sessions will be backed by validated journals, independently revisioned transcripts and notes, and explicit retention state."
        actions={<Badge tone="neutral">0 local meetings</Badge>}
      />

      <section aria-labelledby="meeting-list-heading" className="space-y-4">
        <SectionHeading
          id="meeting-list-heading"
          title="Meeting history"
          description="Search and filters activate when durable meeting data exists."
          action={
            <div className="relative hidden sm:block">
              <Search
                size={15}
                className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint"
                aria-hidden="true"
              />
              <input
                type="search"
                disabled
                aria-label="Search meetings"
                placeholder="Search meetings"
                className="min-h-10 w-52 rounded-control border border-line-strong bg-surface-raised pl-9 pr-3 text-sm text-ink placeholder:text-ink-faint disabled:cursor-not-allowed disabled:opacity-55"
              />
            </div>
          }
        />
        <div>
          <EmptyState
            icon={<Clock3 size={21} aria-hidden="true" />}
            title="No meetings are stored"
            description="This is the genuine empty state. The interface will not seed plausible transcripts or participant data into a production path."
          />
        </div>
      </section>

      <section
        aria-labelledby="meeting-intelligence-heading"
        className="space-y-4"
      >
        <SectionHeading
          id="meeting-intelligence-heading"
          title="Meeting intelligence"
          description="Advanced capture and note tools are included in product scope, with visible consent and review boundaries that the reference product does not always require."
        />
        <div className="grid gap-5 xl:grid-cols-2">
          <Card className="overflow-hidden">
            <div className="border-b border-line bg-canvas-subtle px-5 py-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <span className="grid size-9 place-items-center rounded-xl bg-accent-soft text-accent">
                    <ScanSearch size={17} aria-hidden="true" />
                  </span>
                  <div>
                    <h3 className="text-sm font-semibold text-ink">
                      Meeting detection
                    </h3>
                    <p className="mt-0.5 text-[0.7rem] text-ink-faint">
                      Suggestion only · never auto-starts capture
                    </p>
                  </div>
                </div>
                <Badge tone="warning">Native adapter required</Badge>
              </div>
            </div>

            <div className="divide-y divide-line px-5">
              {[
                {
                  icon: PauseCircle,
                  title: "Pause and resume",
                  detail: "Visible indicator remains present",
                },
                {
                  icon: VolumeX,
                  title: "Mute background audio",
                  detail: "Separate from recorded source state",
                },
                {
                  icon: Captions,
                  title: "Real-time transcript",
                  detail: "Partial and final segments stay distinct",
                },
                {
                  icon: MessageSquareText,
                  title: "Ask during the meeting",
                  detail: "Scoped only to the active transcript",
                },
              ].map(({ icon: Icon, title, detail }) => (
                <div
                  key={title}
                  className="flex items-center justify-between gap-4 py-4"
                >
                  <span className="flex min-w-0 items-center gap-3 text-xs font-semibold text-ink">
                    <Icon
                      size={16}
                      className="shrink-0 text-ink-faint"
                      aria-hidden="true"
                    />
                    {title}
                  </span>
                  <span className="text-right text-[0.68rem] text-ink-faint">
                    {detail}
                  </span>
                </div>
              ))}
            </div>

            <div className="border-t border-line p-5">
              <div className="rounded-control border border-dashed border-line-strong bg-canvas-subtle p-5 text-center">
                <AudioLines
                  size={20}
                  className="mx-auto text-ink-faint"
                  aria-hidden="true"
                />
                <p className="mt-2 text-xs font-semibold text-ink">
                  Live transcript is idle
                </p>
                <p className="mt-1 text-[0.7rem] text-ink-faint">
                  No audio source or streaming model is connected
                </p>
              </div>
            </div>
          </Card>

          <Card className="overflow-hidden">
            <div className="border-b border-line bg-canvas-subtle px-5 py-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <span className="grid size-9 place-items-center rounded-xl bg-accent-soft text-accent">
                    <NotebookTabs size={17} aria-hidden="true" />
                  </span>
                  <div>
                    <h3 className="text-sm font-semibold text-ink">
                      Note workspace
                    </h3>
                    <p className="mt-0.5 text-[0.7rem] text-ink-faint">
                      Independent from summary success
                    </p>
                  </div>
                </div>
                <Badge tone="neutral">No meeting selected</Badge>
              </div>
            </div>

            <div className="grid gap-3 p-5 sm:grid-cols-2">
              {[
                {
                  icon: UsersRound,
                  title: "Speaker review",
                  detail:
                    "Uncertain labels stay editable; source evidence is revisioned.",
                },
                {
                  icon: WandSparkles,
                  title: "Custom templates",
                  detail:
                    "Summary template and note instructions are recorded in provenance.",
                },
                {
                  icon: MessageSquareText,
                  title: "Chat with this note",
                  detail:
                    "Context is the open item only, never the entire library by default.",
                },
                {
                  icon: Upload,
                  title: "Import media as a note",
                  detail:
                    "Uses the same bounded parser and retention preflight as file transcription.",
                },
              ].map(({ icon: Icon, title, detail }) => (
                <div
                  key={title}
                  className="rounded-control border border-line bg-surface-raised p-4"
                >
                  <Icon
                    size={17}
                    className="text-ink-faint"
                    aria-hidden="true"
                  />
                  <h4 className="mt-3 text-xs font-semibold text-ink">
                    {title}
                  </h4>
                  <p className="mt-1.5 text-xs leading-5 text-ink-soft">
                    {detail}
                  </p>
                </div>
              ))}
            </div>

            <div className="border-t border-line px-5 py-4">
              <p className="text-xs leading-5 text-ink-soft">
                Speaker merge and transcript regeneration are destructive or
                evidence-changing operations. They require an explicit preview,
                revision record, and recoverable prior state.
              </p>
            </div>
          </Card>
        </div>
      </section>

      <section aria-labelledby="state-gallery-heading" className="space-y-4">
        <SectionHeading
          id="state-gallery-heading"
          title="Meeting-state gallery"
          description="Isolated UI fixtures for reviewing recovery and failure language."
        />
        <Card className="overflow-hidden">
          <div
            className="flex gap-1 overflow-x-auto border-b border-line bg-canvas-subtle p-2"
            role="group"
            aria-label="Meeting state previews"
          >
            {meetingStates.map((state) => (
              <button
                key={state.id}
                type="button"
                aria-pressed={state.id === selectedState}
                onClick={() => setSelectedState(state.id)}
                className={cn(
                  "min-h-10 shrink-0 rounded-control px-3 text-xs font-semibold transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus",
                  state.id === selectedState
                    ? "bg-surface-raised text-ink shadow-soft"
                    : "text-ink-soft hover:bg-surface-strong hover:text-ink",
                )}
              >
                {state.label}
              </button>
            ))}
          </div>

          <div
            id="meeting-state-panel"
            aria-live="polite"
            className="grid gap-5 p-5 md:grid-cols-[auto_minmax(0,1fr)_auto] md:items-center md:p-7"
          >
            <span
              className={cn(
                "grid size-12 place-items-center rounded-2xl",
                activeState.tone === "success" &&
                  "bg-success-soft text-success",
                activeState.tone === "warning" &&
                  "bg-warning-soft text-warning",
                activeState.tone === "danger" && "bg-danger-soft text-danger",
                activeState.tone === "info" && "bg-info-soft text-info",
              )}
            >
              <ActiveIcon size={22} aria-hidden="true" />
            </span>

            <div>
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={activeState.tone}>{activeState.label}</Badge>
                <Badge tone="neutral">State fixture</Badge>
              </div>
              <h3 className="mt-3 text-lg font-semibold text-ink">
                {activeState.title}
              </h3>
              <p className="mt-1.5 text-sm leading-6 text-ink-soft">
                {activeState.detail}
              </p>
            </div>

            <div className="flex flex-wrap gap-2 md:justify-end">
              {selectedState === "recoverable" ? (
                <>
                  <Button variant="secondary" disabled>
                    Validate journal
                  </Button>
                  <Button variant="quiet" disabled>
                    Review choices
                  </Button>
                </>
              ) : selectedState === "processing" ? (
                <Button variant="secondary" disabled>
                  <LoaderCircle size={15} aria-hidden="true" />
                  Finalizing
                </Button>
              ) : selectedState === "offline" ? (
                <span className="flex items-center gap-2 text-xs font-semibold text-success">
                  <CheckCircle2 size={16} aria-hidden="true" />
                  Route unchanged
                </span>
              ) : (
                <Button variant="secondary" disabled>
                  <CircleAlert size={15} aria-hidden="true" />
                  View diagnosis
                </Button>
              )}
            </div>
          </div>
        </Card>
      </section>

      <InlineNotice tone="info" title="Fixture isolation">
        These states are interface-only examples. They are not imported as
        meeting data and cannot satisfy capture, recovery, or privacy evidence.
      </InlineNotice>
    </div>
  );
}
