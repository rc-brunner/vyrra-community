import {
  CloudCog,
  CloudOff,
  Database,
  FileArchive,
  Files,
  Laptop,
  LockKeyhole,
  RefreshCcw,
  ShieldCheck,
} from "lucide-react";

import {
  Badge,
  Button,
  Card,
  InlineNotice,
  PageHeader,
  SectionHeading,
  StatusDot,
} from "./ui";

const providers = [
  {
    id: "icloud",
    name: "iCloud Drive",
    platform: "macOS",
    connection: "File-based folder",
  },
  {
    id: "google-drive",
    name: "Google Drive",
    platform: "macOS · Windows",
    connection: "OAuth account",
  },
  {
    id: "dropbox",
    name: "Dropbox",
    platform: "macOS · Windows",
    connection: "OAuth account",
  },
  {
    id: "onedrive",
    name: "OneDrive",
    platform: "macOS · Windows",
    connection: "OAuth account",
  },
] as const;

const syncScopes = [
  {
    icon: Database,
    title: "Workspace configuration",
    status: "Required scope",
    tone: "accent" as const,
    description:
      "Preferences, shortcuts, vocabulary, snippets, expansions, automations, utilities, profiles, instructions, and memory.",
  },
  {
    icon: Files,
    title: "User content",
    status: "Optional scope",
    tone: "warning" as const,
    description:
      "Transcript history, meeting notes, and imported-transcription metadata require a separate opt-in.",
  },
  {
    icon: FileArchive,
    title: "Large local artifacts",
    status: "Excluded",
    tone: "success" as const,
    description:
      "Raw audio, screenshots, model downloads, and secret material remain outside the sync contract.",
  },
] as const;

export function SyncSettingsSection() {
  return (
    <div className="space-y-9">
      <PageHeader
        eyebrow="Settings · Sync & integrations"
        title="Cross-device sync stays optional, scoped, and inspectable."
        description="Provider choices and data boundaries are modeled here. No account, OAuth flow, connector, or sync engine is attached to this browser prototype."
        actions={<Badge tone="warning">No provider connected</Badge>}
      />

      <InlineNotice tone="privacy" title="Local remains the source of truth">
        Enabling future sync must not enable cloud transcription, AI routing, or
        silent fallback. A conflict cannot overwrite local notes without a
        reviewable resolution contract.
      </InlineNotice>

      <section aria-labelledby="sync-provider-heading" className="space-y-4">
        <SectionHeading
          id="sync-provider-heading"
          title="Storage provider"
          description="The target architecture uses storage the user controls; connection actions stay unavailable until typed provider adapters and tests exist."
        />
        <div className="grid gap-4 md:grid-cols-2">
          {providers.map((provider) => (
            <Card key={provider.id} className="p-5">
              <div className="flex items-start gap-4">
                <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-surface-strong text-ink-soft">
                  <CloudCog size={19} aria-hidden="true" />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <h3 className="text-sm font-semibold text-ink">
                        {provider.name}
                      </h3>
                      <p className="mt-1 text-xs text-ink-faint">
                        {provider.platform}
                      </p>
                    </div>
                    <Badge tone="neutral">Adapter required</Badge>
                  </div>
                  <div className="mt-4 flex items-center justify-between gap-3 border-t border-line pt-4">
                    <span className="flex items-center gap-2 text-xs text-ink-soft">
                      <StatusDot tone="neutral" />
                      {provider.connection}
                    </span>
                    <Button
                      variant="secondary"
                      disabled
                      title={`${provider.name} adapter is unavailable`}
                    >
                      Connect
                    </Button>
                  </div>
                </div>
              </div>
            </Card>
          ))}
        </div>
      </section>

      <section aria-labelledby="sync-scope-heading" className="space-y-4">
        <SectionHeading
          id="sync-scope-heading"
          title="Data scope"
          description="These categories define the intended review screen before the first transfer."
        />
        <div className="grid gap-4 lg:grid-cols-3">
          {syncScopes.map(
            ({ icon: Icon, title, status, tone, description }) => (
              <Card key={title} className="p-5">
                <div className="flex items-start justify-between gap-3">
                  <span className="grid size-10 place-items-center rounded-xl bg-accent-soft text-accent">
                    <Icon size={18} aria-hidden="true" />
                  </span>
                  <Badge tone={tone}>{status}</Badge>
                </div>
                <h3 className="mt-4 text-sm font-semibold text-ink">
                  {title}
                </h3>
                <p className="mt-2 text-sm leading-6 text-ink-soft">
                  {description}
                </p>
              </Card>
            ),
          )}
        </div>
      </section>

      <section aria-labelledby="sync-state-heading" className="space-y-4">
        <SectionHeading
          id="sync-state-heading"
          title="Effective state"
          description="Connection, device, conflict, and encryption claims remain closed until the desktop core can prove them."
        />
        <Card className="divide-y divide-line px-5">
          {[
            {
              icon: CloudOff,
              title: "Network transfer",
              detail: "No sync requests can leave this prototype",
              status: "Off",
            },
            {
              icon: Laptop,
              title: "Paired devices",
              detail: "No device identity or pairing record exists",
              status: "0 devices",
            },
            {
              icon: RefreshCcw,
              title: "Conflict resolution",
              detail: "Policy and recovery UI require an approved contract",
              status: "Not implemented",
            },
            {
              icon: LockKeyhole,
              title: "Protected credentials",
              detail: "Provider tokens must live in OS-protected storage",
              status: "Not connected",
            },
          ].map(({ icon: Icon, title, detail, status }) => (
            <div
              key={title}
              className="flex flex-col gap-3 py-5 sm:flex-row sm:items-center sm:justify-between"
            >
              <div className="flex items-start gap-3.5">
                <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-surface-strong text-ink-soft">
                  <Icon size={16} aria-hidden="true" />
                </span>
                <div>
                  <h3 className="text-sm font-semibold text-ink">{title}</h3>
                  <p className="mt-1 text-xs leading-5 text-ink-soft">
                    {detail}
                  </p>
                </div>
              </div>
              <Badge tone="neutral">{status}</Badge>
            </div>
          ))}
        </Card>
      </section>

      <Card className="flex items-start gap-4 p-5">
        <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-success-soft text-success">
          <ShieldCheck size={18} aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-semibold text-ink">
            A license limit is not a privacy boundary
          </h2>
          <p className="mt-1.5 text-sm leading-6 text-ink-soft">
            Future device limits, if any, belong to product policy. Encryption,
            least-privilege grants, revocation, conflict recovery, and content
            exclusions must be enforced independently.
          </p>
        </div>
      </Card>
    </div>
  );
}
