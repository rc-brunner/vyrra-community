import {
  BadgeCheck,
  Bot,
  Boxes,
  Brain,
  Captions,
  Check,
  CloudOff,
  Command,
  Cpu,
  Download,
  FileCheck2,
  Gauge,
  HardDrive,
  Languages,
  RadioTower,
  ShieldCheck,
  Sparkles,
  UsersRound,
} from "lucide-react";

import {
  Badge,
  Button,
  Card,
  InlineNotice,
  PageHeader,
  SectionHeading,
  StatusDot,
} from "../components/ui";

const activationChecks = [
  { icon: BadgeCheck, label: "Approved manifest signature" },
  { icon: FileCheck2, label: "Matching checksum and source" },
  { icon: Boxes, label: "Compatible runtime and platform" },
  { icon: ShieldCheck, label: "Reviewed license metadata" },
];

export function ModelsPage() {
  return (
    <div className="space-y-9">
      <PageHeader
        eyebrow="AI & Models"
        title="Capabilities appear only after they are verified."
        description="A model name or provider logo is not evidence of support. This prototype shows the activation contract without advertising an unvalidated runtime."
        actions={<Badge tone="warning">Catalog not connected</Badge>}
      />

      <InlineNotice tone="privacy" title="Local remains the default boundary">
        After a compatible runtime and model are installed and verified, the
        planned transcription path must complete with outbound network denied.
        There is no automatic cloud fallback.
      </InlineNotice>

      <section aria-labelledby="local-runtime-heading" className="space-y-4">
        <SectionHeading
          id="local-runtime-heading"
          title="Local capabilities"
          description="Generic capability slots remain unavailable until their manifest and adapter tests pass."
        />
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1.15fr)_minmax(22rem,0.75fr)]">
          <Card className="p-5 sm:p-6">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div className="flex items-start gap-4">
                <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-accent-soft text-accent">
                  <Cpu size={20} aria-hidden="true" />
                </span>
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-base font-semibold text-ink">
                      Local transcription runtime
                    </h2>
                    <Badge tone="neutral">Unavailable</Badge>
                  </div>
                  <p className="mt-2 max-w-2xl text-sm leading-6 text-ink-soft">
                    The desktop core will report compatible language, timing,
                    hardware, size, license, source, and health metadata.
                  </p>
                </div>
              </div>
              <Button disabled variant="secondary">
                <Download size={15} aria-hidden="true" />
                Install
              </Button>
            </div>

            <div className="mt-6 grid gap-3 border-t border-line pt-5 sm:grid-cols-3">
              {[
                { icon: Languages, label: "Languages", value: "Unknown" },
                { icon: HardDrive, label: "Download", value: "Not resolved" },
                { icon: Gauge, label: "Hardware", value: "Not probed" },
              ].map(({ icon: Icon, label, value }) => (
                <div
                  key={label}
                  className="rounded-control bg-canvas-subtle p-3"
                >
                  <Icon
                    size={15}
                    className="text-ink-faint"
                    aria-hidden="true"
                  />
                  <p className="mt-2 text-[0.68rem] font-bold uppercase tracking-[0.08em] text-ink-faint">
                    {label}
                  </p>
                  <p className="mt-1 text-xs font-semibold text-ink">{value}</p>
                </div>
              ))}
            </div>
          </Card>

          <Card className="p-5 sm:p-6">
            <p className="text-xs font-bold uppercase tracking-[0.12em] text-ink-faint">
              Activation gate
            </p>
            <h2 className="mt-2 text-base font-semibold text-ink">
              Four checks, fail closed
            </h2>
            <div className="mt-4 space-y-3">
              {activationChecks.map(({ icon: Icon, label }) => (
                <div
                  key={label}
                  className="flex items-center gap-3 rounded-control border border-line bg-surface-raised p-3"
                >
                  <Icon
                    size={16}
                    className="text-ink-faint"
                    aria-hidden="true"
                  />
                  <span className="min-w-0 flex-1 text-xs font-medium text-ink">
                    {label}
                  </span>
                  <StatusDot tone="neutral" />
                </div>
              ))}
            </div>
          </Card>
        </div>
      </section>

      <section
        aria-labelledby="advanced-model-capabilities-heading"
        className="space-y-4"
      >
        <SectionHeading
          id="advanced-model-capabilities-heading"
          title="Advanced transcription and AI capabilities"
          description="Each feature is gated by effective model metadata, platform support, selected execution route, and a tested adapter."
        />
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {[
            {
              icon: Captions,
              title: "Real-time transcription",
              description:
                "Stream provisional segments, then visibly replace them with durable final segments.",
              requirement: "Streaming speech model",
            },
            {
              icon: Languages,
              title: "Translate to English",
              description:
                "Keep the source-language transcript and save translation as a revisioned derivative.",
              requirement: "Verified translation support",
            },
            {
              icon: UsersRound,
              title: "Speaker diarization",
              description:
                "Expose uncertain speaker labels for review instead of presenting model guesses as identity.",
              requirement: "Platform/model-specific",
            },
            {
              icon: Sparkles,
              title: "AI enhancement",
              description:
                "Apply explicitly scoped guidance without changing the preserved source transcript.",
              requirement: "BYOK provider + preview",
            },
            {
              icon: Command,
              title: "Command Mode",
              description:
                "Transform selected context into a reviewable result with no implicit external authority.",
              requirement: "Reasoning + authorization",
            },
            {
              icon: Brain,
              title: "Memory and instructions",
              description:
                "Use only user-reviewed, scoped context with provenance and clear removal controls.",
              requirement: "Protected settings store",
            },
          ].map(({ icon: Icon, title, description, requirement }) => (
            <Card key={title} className="p-5">
              <div className="flex items-start justify-between gap-3">
                <span className="grid size-10 place-items-center rounded-xl bg-surface-strong text-ink-soft">
                  <Icon size={18} aria-hidden="true" />
                </span>
                <Badge tone="warning">Unavailable</Badge>
              </div>
              <h3 className="mt-4 text-sm font-semibold text-ink">{title}</h3>
              <p className="mt-2 text-sm leading-6 text-ink-soft">
                {description}
              </p>
              <p className="mt-4 flex items-center gap-2 border-t border-line pt-3 text-[0.7rem] font-semibold text-ink-faint">
                <RadioTower size={14} aria-hidden="true" />
                {requirement}
              </p>
            </Card>
          ))}
        </div>
      </section>

      <section aria-labelledby="reasoning-heading" className="space-y-4">
        <SectionHeading
          id="reasoning-heading"
          title="Optional reasoning"
          description="Meeting readiness never depends on a summary engine."
        />
        <Card className="flex flex-col gap-5 p-5 sm:flex-row sm:items-center sm:justify-between sm:p-6">
          <div className="flex items-start gap-4">
            <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-surface-strong text-ink-soft">
              <Bot size={20} aria-hidden="true" />
            </span>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-base font-semibold text-ink">
                  Summary capability
                </h2>
                <Badge tone="neutral">Not configured</Badge>
              </div>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-ink-soft">
                When available, derived artifacts must name exact source
                revisions, execution location, model, template, time, citations,
                and user edits.
              </p>
            </div>
          </div>
          <span className="flex shrink-0 items-center gap-2 text-xs font-semibold text-success">
            <Check size={16} aria-hidden="true" />
            Transcript remains usable
          </span>
        </Card>
      </section>

      <Card className="flex items-start gap-4 p-5">
        <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-success-soft text-success">
          <CloudOff size={18} aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-semibold text-ink">
            Cloud connections stay hidden
          </h2>
          <p className="mt-1.5 text-sm leading-6 text-ink-soft">
            No provider manifest or live adapter suite has passed, so this
            prototype does not display a decorative provider catalog.
          </p>
        </div>
      </Card>
    </div>
  );
}
