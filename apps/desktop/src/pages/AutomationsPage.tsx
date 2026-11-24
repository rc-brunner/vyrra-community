import {
  Blocks,
  Braces,
  CheckCircle2,
  ClipboardCheck,
  Command,
  Eye,
  GitBranch,
  LockKeyhole,
  MousePointerClick,
  Send,
  ShieldAlert,
  Sparkles,
  TextCursorInput,
  Webhook,
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

export function AutomationsPage() {
  return (
    <div className="space-y-9">
      <PageHeader
        eyebrow="Automations"
        title="Voice workflows with authority proportional to risk."
        description="Read-only organization, local drafts, and external writes have different approval requirements. No workflow engine is connected to this interface prototype."
        actions={
          <Button disabled>
            <Blocks size={16} aria-hidden="true" />
            New automation
          </Button>
        }
      />

      <InlineNotice tone="warning" title="No external action can run">
        Provider and integration adapters are absent. A future external write
        must include a preview, explicit authorization, idempotency key, receipt,
        and provenance.
      </InlineNotice>

      <section aria-labelledby="risk-model-heading" className="space-y-4">
        <SectionHeading
          id="risk-model-heading"
          title="Approval model"
          description="The interface makes the side-effect boundary visible before execution."
        />
        <div className="grid gap-4 lg:grid-cols-3">
          {[
            {
              icon: LockKeyhole,
              badge: "Low risk",
              tone: "success" as const,
              title: "Organize locally",
              description:
                "Tag, format, or classify user-selected local content.",
              rule: "Reviewable result",
            },
            {
              icon: MousePointerClick,
              badge: "Confirm",
              tone: "warning" as const,
              title: "Prepare a draft",
              description:
                "Create a local draft without sending it anywhere.",
              rule: "Explicit save",
            },
            {
              icon: Send,
              badge: "High risk",
              tone: "danger" as const,
              title: "Write externally",
              description:
                "Send, publish, update, or modify an external system.",
              rule: "Preview + explicit send",
            },
          ].map(({ icon: Icon, badge, tone, title, description, rule }) => (
            <Card key={title} className="p-5">
              <div className="flex items-start justify-between gap-3">
                <span className="grid size-10 place-items-center rounded-xl bg-surface-strong text-ink-soft">
                  <Icon size={18} aria-hidden="true" />
                </span>
                <Badge tone={tone}>{badge}</Badge>
              </div>
              <h2 className="mt-5 text-sm font-semibold text-ink">{title}</h2>
              <p className="mt-2 text-sm leading-6 text-ink-soft">
                {description}
              </p>
              <p className="mt-5 flex items-center gap-2 border-t border-line pt-4 text-xs font-semibold text-ink">
                <CheckCircle2
                  size={15}
                  className="text-success"
                  aria-hidden="true"
                />
                {rule}
              </p>
            </Card>
          ))}
        </div>
      </section>

      <section
        aria-labelledby="productivity-tools-heading"
        className="space-y-4"
      >
        <SectionHeading
          id="productivity-tools-heading"
          title="Command and productivity tools"
          description="Commands, workflows, text expansions, and utilities are separate product objects with different inputs, outputs, and authority."
        />
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {[
            {
              icon: Command,
              title: "Command workspace",
              description:
                "Review selected text, files, screenshots, memory, and profile context before an AI transformation.",
              status: "Provider + context adapters",
            },
            {
              icon: GitBranch,
              title: "Voice workflows",
              description:
                "Match an explicit trigger, preview each step, then request authorization proportional to side effects.",
              status: "Engine unavailable",
            },
            {
              icon: TextCursorInput,
              title: "Text expansions",
              description:
                "Resolve user-defined abbreviations with collision checks and rich/plain-text fallback.",
              status: "Insertion adapter required",
            },
            {
              icon: Sparkles,
              title: "Custom utilities",
              description:
                "Run a focused transformation on selected text or clipboard input with an explicit output destination.",
              status: "Execution schema planned",
            },
          ].map(({ icon: Icon, title, description, status }) => (
            <Card key={title} className="p-5">
              <div className="flex items-start justify-between gap-3">
                <span className="grid size-10 place-items-center rounded-xl bg-accent-soft text-accent">
                  <Icon size={18} aria-hidden="true" />
                </span>
                <Badge tone="neutral">Unavailable</Badge>
              </div>
              <h3 className="mt-4 text-sm font-semibold text-ink">{title}</h3>
              <p className="mt-2 text-sm leading-6 text-ink-soft">
                {description}
              </p>
              <p className="mt-4 border-t border-line pt-3 text-[0.7rem] text-ink-faint">
                {status}
              </p>
            </Card>
          ))}
        </div>
        <InlineNotice tone="info" title="No app-plan quota intended">
          Device resources, provider rate limits, permission scope, safety
          policy, and external-service limits still apply. “Included” never
          means unbounded execution.
        </InlineNotice>
      </section>

      <section aria-labelledby="advanced-step-heading" className="space-y-4">
        <SectionHeading
          id="advanced-step-heading"
          title="Advanced integration steps"
          description="Network calls, local scripts, and connector reads fail closed until separately reviewed adapters exist."
        />
        <Card className="divide-y divide-line px-5">
          {[
            {
              icon: Webhook,
              title: "Webhook delivery",
              description:
                "Scoped JSON payload, redacted headers, bounded retries, idempotency, and a delivery receipt.",
              boundary: "External write",
              tone: "danger" as const,
            },
            {
              icon: Braces,
              title: "Custom script step",
              description:
                "Allowlisted executable, sandboxed input, timeout, output cap, no inherited secrets, and an exact preview.",
              boundary: "Local execution",
              tone: "warning" as const,
            },
            {
              icon: Eye,
              title: "Read-only connectors",
              description:
                "Search, list, get, or read only after a user grant; create, edit, send, and delete remain outside the connector contract.",
              boundary: "External read",
              tone: "info" as const,
            },
          ].map(
            ({ icon: Icon, title, description, boundary, tone }) => (
              <div
                key={title}
                className="flex flex-col gap-4 py-5 lg:flex-row lg:items-center lg:justify-between"
              >
                <div className="flex items-start gap-4">
                  <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-surface-strong text-ink-soft">
                    <Icon size={18} aria-hidden="true" />
                  </span>
                  <div>
                    <h3 className="text-sm font-semibold text-ink">
                      {title}
                    </h3>
                    <p className="mt-1 max-w-3xl text-xs leading-5 text-ink-soft">
                      {description}
                    </p>
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <Badge tone={tone}>{boundary}</Badge>
                  <Badge tone="neutral">Adapter required</Badge>
                </div>
              </div>
            ),
          )}
        </Card>
      </section>

      <section aria-labelledby="workflow-list-heading" className="space-y-4">
        <SectionHeading
          id="workflow-list-heading"
          title="Your automations"
          description="Only user-created, locally stored workflows will appear here."
        />
        <div>
          <EmptyState
            icon={<GitBranch size={21} aria-hidden="true" />}
            title="No automations configured"
            description="Workflow creation is planned for a later phase after reliable capture, transcription, recovery, and export are verified."
          />
        </div>
      </section>

      <Card className="flex items-start gap-4 p-5">
        <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-danger-soft text-danger">
          <ShieldAlert size={18} aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-semibold text-ink">
            Transcript content is never authority
          </h2>
          <p className="mt-1.5 text-sm leading-6 text-ink-soft">
            Meeting text, imported content, and provider output are untrusted
            data. They cannot invoke tools or bypass confirmation.
          </p>
        </div>
      </Card>

      <Card className="flex items-start gap-4 p-5">
        <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-success-soft text-success">
          <ClipboardCheck size={18} aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-semibold text-ink">
            Results remain drafts until the user chooses otherwise
          </h2>
          <p className="mt-1.5 text-sm leading-6 text-ink-soft">
            Command results support review, copy, paste, retry, and discard.
            Provider output cannot silently replace selected text, write a file,
            or trigger a second action.
          </p>
        </div>
      </Card>
    </div>
  );
}
