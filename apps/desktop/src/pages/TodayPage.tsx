import {
  ArrowRight,
  Clock3,
  HardDrive,
  Mic2,
  Settings2,
  Sparkles,
} from "lucide-react";

import { RecorderPill } from "../components/RecorderPill";
import {
  ActionLink,
  Badge,
  Card,
  PageHeader,
  StatusDot,
  TextLink,
} from "../components/ui";
import { hrefForRoute } from "../lib/navigation";

const setupItems = [
  {
    icon: Mic2,
    label: "Microphone",
    value: "Not connected",
    tone: "warning" as const,
  },
  {
    icon: Sparkles,
    label: "Transcription",
    value: "Not installed",
    tone: "warning" as const,
  },
  {
    icon: HardDrive,
    label: "Storage",
    value: "Not connected",
    tone: "neutral" as const,
  },
];

export function TodayPage() {
  return (
    <div className="space-y-12">
      <PageHeader
        eyebrow="Today"
        title="Welcome back, Brandon."
        actions={
          <ActionLink href={hrefForRoute("capture")}>
            New capture
            <ArrowRight size={16} aria-hidden="true" />
          </ActionLink>
        }
      />

      <section
        aria-labelledby="voice-studio-heading"
        className="grid gap-5 xl:grid-cols-[minmax(0,1.45fr)_minmax(18rem,0.65fr)]"
      >
        <Card className="flex min-h-[24rem] flex-col justify-between overflow-hidden p-6 sm:p-9">
          <div className="flex items-center justify-between gap-4">
            <Badge tone="neutral">Voice studio</Badge>
            <span className="flex items-center gap-2 text-xs text-ink-faint">
              <StatusDot tone="neutral" />
              Preview mode
            </span>
          </div>

          <div className="my-12 max-w-3xl">
            <h2
              id="voice-studio-heading"
              className="max-w-2xl text-3xl font-medium tracking-[-0.045em] text-ink sm:text-5xl sm:leading-[1.04]"
            >
              Give your thoughts a quieter place to land.
            </h2>
          </div>

          <div className="space-y-5">
            <RecorderPill active={false} label="Idle" />
            <div className="flex flex-wrap items-center gap-3">
              <ActionLink href={hrefForRoute("capture")}>
                <Mic2 size={16} aria-hidden="true" />
                Open capture
              </ActionLink>
              <TextLink href={hrefForRoute("settings")}>Customize</TextLink>
            </div>
          </div>
        </Card>

        <Card className="p-5 sm:p-6">
          <div className="flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold text-ink">Setup</h2>
            <Badge tone="warning">3 items</Badge>
          </div>

          <div className="mt-5 divide-y divide-line border-y border-line">
            {setupItems.map(({ icon: Icon, label, value, tone }) => (
              <div
                key={label}
                className="flex items-center justify-between gap-3 py-4"
              >
                <span className="flex min-w-0 items-center gap-3">
                  <Icon
                    size={16}
                    className="shrink-0 text-ink-faint"
                    aria-hidden="true"
                  />
                  <span className="truncate text-sm text-ink">{label}</span>
                </span>
                <span className="flex shrink-0 items-center gap-2 text-xs text-ink-faint">
                  <StatusDot tone={tone} />
                  {value}
                </span>
              </div>
            ))}
          </div>

          <TextLink href={hrefForRoute("settings")} className="mt-3">
            <Settings2 size={15} aria-hidden="true" />
            Finish setup
          </TextLink>
        </Card>
      </section>

      <section aria-labelledby="recent-heading">
        <div className="flex items-center justify-between gap-4 border-b border-line pb-4">
          <h2 id="recent-heading" className="text-lg font-medium text-ink">
            Recent
          </h2>
          <TextLink href={hrefForRoute("library")}>View all</TextLink>
        </div>

        <div className="flex min-h-36 items-center justify-center border-b border-line px-6 py-10 text-center">
          <div>
            <Clock3
              size={20}
              className="mx-auto text-ink-faint"
              aria-hidden="true"
            />
            <h3 className="mt-3 text-sm font-medium text-ink">
              No sessions yet
            </h3>
            <p className="mt-1 text-xs text-ink-faint">
              Your recordings will appear here.
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
