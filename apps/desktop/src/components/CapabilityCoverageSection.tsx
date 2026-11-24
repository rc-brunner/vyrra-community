import { useMemo, useState } from "react";
import {
  AudioLines,
  Blocks,
  Bot,
  CalendarClock,
  CheckCircle2,
  CircleDashed,
  ExternalLink,
  NotebookTabs,
  PlugZap,
  Search,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";

import {
  CAPABILITY_CATEGORIES,
  CURRENT_CAPABILITIES,
  DOCUMENTED_PRO_EXTENSIONS,
  ROADMAP_CAPABILITIES,
  VENDOR_SERVICE_REFERENCES,
  type CapabilityCategoryId,
  type CapabilityDelivery,
  type CapabilityParity,
  type CapabilityTarget,
} from "../lib/proCapabilities";
import { cn } from "../lib/cn";
import {
  Badge,
  Card,
  InlineNotice,
  PageHeader,
  SectionHeading,
} from "./ui";

type ParityFilter = "all" | CapabilityParity;

const categoryIcons = {
  transcription: AudioLines,
  "meeting-notes": NotebookTabs,
  ai: Bot,
  productivity: Blocks,
  integrations: PlugZap,
  perks: ShieldCheck,
} satisfies Record<CapabilityCategoryId, typeof AudioLines>;

const targetLabels = {
  library: "Library",
  meetings: "Meetings",
  automations: "Automations",
  models: "AI & Models",
  settings: "Settings",
} satisfies Record<CapabilityTarget, string>;

const deliveryPresentation = {
  prototype: {
    label: "UI modeled",
    tone: "success" as const,
    icon: CheckCircle2,
  },
  "adapter-required": {
    label: "Adapter required",
    tone: "warning" as const,
    icon: TriangleAlert,
  },
  planned: {
    label: "Planned",
    tone: "neutral" as const,
    icon: CircleDashed,
  },
} satisfies Record<
  CapabilityDelivery,
  {
    label: string;
    tone: "success" | "warning" | "neutral";
    icon: typeof CheckCircle2;
  }
>;

export function CapabilityCoverageSection() {
  const [query, setQuery] = useState("");
  const [parity, setParity] = useState<ParityFilter>("all");

  const normalizedQuery = query.trim().toLocaleLowerCase();
  const visibleCapabilities = useMemo(
    () =>
      CURRENT_CAPABILITIES.filter((capability) => {
        if (parity !== "all" && capability.parity !== parity) return false;
        if (!normalizedQuery) return true;
        return [
          capability.title,
          capability.description,
          capability.deliveryDetail,
          targetLabels[capability.target],
        ].some((value) =>
          value.toLocaleLowerCase().includes(normalizedQuery),
        );
      }),
    [normalizedQuery, parity],
  );

  const visibleExtensions = useMemo(() => {
    if (parity === "baseline") return [];
    if (!normalizedQuery) return DOCUMENTED_PRO_EXTENSIONS;
    return DOCUMENTED_PRO_EXTENSIONS.filter((capability) =>
      [
        capability.title,
        capability.description,
        capability.deliveryDetail,
        capability.sourceNote,
      ].some((value) =>
        value.toLocaleLowerCase().includes(normalizedQuery),
      ),
    );
  }, [normalizedQuery, parity]);

  const allVisibleCount =
    visibleCapabilities.length + visibleExtensions.length;

  return (
    <div className="space-y-9">
      <PageHeader
        eyebrow="Settings · Capability coverage"
        title="Every advanced capability has a truthful home."
        description="The current 40-row reference matrix and three documented extensions are mapped into this product scope. Delivery state remains separate from interface coverage."
        actions={<Badge tone="accent">43 capabilities mapped</Badge>}
      />

      <InlineNotice tone="info" title="Included in scope is not shipped">
        “UI modeled” means a non-operational product surface exists. “Adapter
        required” means native, model, provider, storage, or permission work is
        still missing. “Planned” means the interaction or domain contract is
        not complete.
      </InlineNotice>

      <section aria-labelledby="coverage-summary-heading" className="space-y-4">
        <SectionHeading
          id="coverage-summary-heading"
          title="Coverage summary"
          description="No feature is hidden behind a prototype paywall, and no unavailable capability is presented as ready."
        />
        <div className="grid gap-4 sm:grid-cols-3">
          {[
            {
              value: CURRENT_CAPABILITIES.filter(
                ({ parity: itemParity }) => itemParity === "advanced",
              ).length,
              label: "Advanced matrix rows",
              detail: "No app-plan quota intended",
            },
            {
              value:
                CURRENT_CAPABILITIES.filter(
                  ({ delivery }) => delivery === "prototype",
                ).length,
              label: "Interfaces modeled",
              detail: "Includes multi-shortcut parity",
            },
            {
              value: 0,
              label: "Connected adapters",
              detail: "Native and cloud claims fail closed",
            },
          ].map(({ value, label, detail }) => (
            <Card key={label} className="p-5">
              <p className="text-3xl font-semibold tracking-[-0.04em] text-ink">
                {value}
              </p>
              <h3 className="mt-2 text-sm font-semibold text-ink">{label}</h3>
              <p className="mt-1 text-xs leading-5 text-ink-soft">{detail}</p>
            </Card>
          ))}
        </div>
      </section>

      <section aria-labelledby="capability-matrix-heading" className="space-y-4">
        <SectionHeading
          id="capability-matrix-heading"
          title="Searchable capability matrix"
          description="Foundation rows are included because the advanced plan inherits them."
        />

        <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto]">
          <div className="relative">
            <label htmlFor="capability-search" className="sr-only">
              Search capabilities
            </label>
            <Search
              size={18}
              aria-hidden="true"
              className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-ink-faint"
            />
            <input
              id="capability-search"
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search features, states, or product areas"
              className="h-12 w-full rounded-control border border-line-strong bg-surface pl-11 pr-4 text-sm text-ink outline-none placeholder:text-ink-faint focus:border-accent focus:outline-3 focus:outline-offset-2 focus:outline-focus"
            />
          </div>

          <div
            role="group"
            aria-label="Capability scope"
            className="grid grid-cols-3 rounded-control border border-line-strong bg-canvas-subtle p-1"
          >
            {(
              [
                ["all", "All"],
                ["advanced", "Advanced"],
                ["baseline", "Foundation"],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                aria-pressed={parity === id}
                onClick={() => setParity(id)}
                className={cn(
                  "min-h-10 rounded-lg px-3 text-xs font-semibold transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus",
                  parity === id
                    ? "bg-surface-raised text-ink shadow-soft"
                    : "text-ink-soft hover:text-ink",
                )}
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        {allVisibleCount === 0 ? (
          <Card className="p-8 text-center">
            <Search
              size={22}
              className="mx-auto text-ink-faint"
              aria-hidden="true"
            />
            <h3 className="mt-3 text-sm font-semibold text-ink">
              No capabilities match “{query}”
            </h3>
            <p className="mt-1 text-xs text-ink-soft">
              Try a feature, adapter, or product area.
            </p>
          </Card>
        ) : (
          <div className="space-y-4">
            {CAPABILITY_CATEGORIES.filter(
              (category) => category.id !== "perks",
            ).map((category) => {
              const items = visibleCapabilities.filter(
                (capability) => capability.category === category.id,
              );
              if (items.length === 0) return null;
              const Icon = categoryIcons[category.id];

              return (
                <Card key={category.id} className="overflow-hidden">
                  <div className="flex flex-col gap-3 border-b border-line bg-canvas-subtle px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                    <div className="flex items-start gap-3">
                      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-accent-soft text-accent">
                        <Icon size={17} aria-hidden="true" />
                      </span>
                      <div>
                        <h3 className="text-sm font-semibold text-ink">
                          {category.label}
                        </h3>
                        <p className="mt-0.5 text-xs text-ink-soft">
                          {category.description}
                        </p>
                      </div>
                    </div>
                    <Badge tone="neutral">
                      {items.length} {items.length === 1 ? "item" : "items"}
                    </Badge>
                  </div>

                  <ul className="divide-y divide-line">
                    {items.map((capability) => {
                      const delivery =
                        deliveryPresentation[capability.delivery];
                      const DeliveryIcon = delivery.icon;

                      return (
                        <li
                          key={capability.id}
                          className="grid gap-3 px-5 py-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center"
                        >
                          <div>
                            <div className="flex flex-wrap items-center gap-2">
                              <h4 className="text-sm font-semibold text-ink">
                                {capability.title}
                              </h4>
                              <Badge
                                tone={
                                  capability.parity === "advanced"
                                    ? "accent"
                                    : "neutral"
                                }
                              >
                                {capability.parity === "advanced"
                                  ? "Advanced"
                                  : "Foundation"}
                              </Badge>
                            </div>
                            <p className="mt-1.5 text-xs leading-5 text-ink-soft">
                              {capability.description}
                            </p>
                            <p className="mt-1 text-[0.7rem] leading-5 text-ink-faint">
                              {capability.deliveryDetail}
                            </p>
                          </div>
                          <div className="flex flex-wrap items-center gap-2 lg:justify-end">
                            <Badge tone="neutral">
                              {targetLabels[capability.target]}
                            </Badge>
                            <Badge tone={delivery.tone}>
                              <DeliveryIcon size={12} aria-hidden="true" />
                              {delivery.label}
                            </Badge>
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                </Card>
              );
            })}

            {visibleExtensions.length > 0 && (
              <Card className="overflow-hidden">
                <div className="flex flex-col gap-3 border-b border-line bg-canvas-subtle px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                  <div className="flex items-start gap-3">
                    <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-accent-soft text-accent">
                      <ExternalLink size={17} aria-hidden="true" />
                    </span>
                    <div>
                      <h3 className="text-sm font-semibold text-ink">
                        Documented extensions
                      </h3>
                      <p className="mt-0.5 text-xs text-ink-soft">
                        Current detailed docs that are broader than the pricing
                        matrix.
                      </p>
                    </div>
                  </div>
                  <Badge tone="accent">{visibleExtensions.length} extras</Badge>
                </div>
                <ul className="divide-y divide-line">
                  {visibleExtensions.map((capability) => {
                    const delivery =
                      deliveryPresentation[capability.delivery];
                    return (
                      <li key={capability.id} className="px-5 py-4">
                        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                          <div>
                            <h4 className="text-sm font-semibold text-ink">
                              {capability.title}
                            </h4>
                            <p className="mt-1.5 text-xs leading-5 text-ink-soft">
                              {capability.description}
                            </p>
                            <p className="mt-1 text-[0.7rem] leading-5 text-ink-faint">
                              {capability.sourceNote}
                            </p>
                          </div>
                          <div className="flex shrink-0 flex-wrap gap-2">
                            <Badge tone="neutral">
                              {targetLabels[capability.target]}
                            </Badge>
                            <Badge tone={delivery.tone}>
                              {delivery.label}
                            </Badge>
                          </div>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </Card>
            )}
          </div>
        )}
      </section>

      <section aria-labelledby="reference-boundary-heading" className="space-y-4">
        <SectionHeading
          id="reference-boundary-heading"
          title="Roadmap and commercial boundaries"
          description="Future ideas and another vendor’s service promises are cataloged without becoming product commitments."
        />
        <div className="grid gap-4 xl:grid-cols-2">
          <Card className="overflow-hidden">
            <details>
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-5 py-4 focus-visible:outline-3 focus-visible:outline-offset-[-3px] focus-visible:outline-focus">
                <span className="flex items-center gap-3 text-sm font-semibold text-ink">
                  <CalendarClock
                    size={17}
                    className="text-ink-faint"
                    aria-hidden="true"
                  />
                  Reference roadmap
                </span>
                <Badge tone="neutral">
                  {ROADMAP_CAPABILITIES.length} not current
                </Badge>
              </summary>
              <ul className="divide-y divide-line border-t border-line">
                {ROADMAP_CAPABILITIES.map((item) => (
                  <li key={item.id} className="px-5 py-3.5">
                    <p className="text-xs font-semibold text-ink">
                      {item.title}
                    </p>
                    <p className="mt-1 text-xs leading-5 text-ink-soft">
                      {item.description}
                    </p>
                  </li>
                ))}
              </ul>
            </details>
          </Card>

          <Card className="overflow-hidden">
            <details>
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-5 py-4 focus-visible:outline-3 focus-visible:outline-offset-[-3px] focus-visible:outline-focus">
                <span className="flex items-center gap-3 text-sm font-semibold text-ink">
                  <ShieldCheck
                    size={17}
                    className="text-ink-faint"
                    aria-hidden="true"
                  />
                  Vendor service promises
                </span>
                <Badge tone="neutral">Reference only</Badge>
              </summary>
              <ul className="divide-y divide-line border-t border-line">
                {VENDOR_SERVICE_REFERENCES.map((item) => (
                  <li key={item.id} className="px-5 py-3.5">
                    <p className="text-xs font-semibold text-ink">
                      {item.title}
                    </p>
                    <p className="mt-1 text-xs leading-5 text-ink-soft">
                      {item.description}
                    </p>
                  </li>
                ))}
              </ul>
            </details>
          </Card>
        </div>
      </section>
    </div>
  );
}
