import { useEffect, useState, type ReactNode } from "react";
import {
  Check,
  Keyboard,
  CalendarDays,
  Mic,
  Palette,
  Scissors,
  Shield,
  Sparkles,
} from "lucide-react";

import { RecorderPill } from "../components/RecorderPill";
import { DictationShortcutSettings } from "../components/DictationShortcutSettings";
import { MeetingProfile } from "../components/MeetingProfile";
import { DictationPreferences } from "../components/DictationPreferences";
import { ShortcutSettingsSection } from "../components/ShortcutSettingsSection";
import {
  Badge,
  Card,
  PageHeader,
  SectionHeading,
} from "../components/ui";
import {
  ACCENT_THEMES,
  APPEARANCE_MODES,
  type AccentTheme,
  type AppearanceMode,
  useAppearancePreference,
} from "../lib/appearance";
import { cn } from "../lib/cn";
import {
  readWaveformSensitivity,
  readWaveformVariant,
  WAVEFORM_VARIANTS,
  writeWaveformSensitivity,
  writeWaveformVariant,
  type WaveformVariant,
} from "../lib/waveform";

type SettingsSection = "shortcuts" | "dictation" | "meetings" | "appearance" | "privacy";

const SETTINGS_SECTIONS = [
  {
    id: "shortcuts",
    label: "Shortcuts",
    icon: Keyboard,
  },
  {
    id: "dictation",
    label: "Dictation",
    icon: Mic,
  },
  {
    id: "meetings", label: "Meetings", icon: CalendarDays,
  },
  {
    id: "appearance",
    label: "Appearance",
    icon: Palette,
  },
  {
    id: "privacy",
    label: "Privacy",
    icon: Shield,
  },
] satisfies ReadonlyArray<{
  id: SettingsSection;
  label: string;
  icon: typeof Keyboard;
}>;

function settingsSectionFromHash(hash: string): SettingsSection {
  const section = hash.replace(/^#\/?/, "").split("/")[1];
  return SETTINGS_SECTIONS.some((item) => item.id === section)
    ? (section as SettingsSection)
    : "shortcuts";
}

function useSettingsSection() {
  const [section, setSection] = useState<SettingsSection>(() =>
    settingsSectionFromHash(window.location.hash),
  );

  useEffect(() => {
    const onHashChange = () =>
      setSection(settingsSectionFromHash(window.location.hash));
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  return section;
}

function SettingsNavigation({ section }: { section: SettingsSection }) {
  return (
    <nav
      aria-label="Settings sections"
      className="flex gap-2 overflow-x-auto pb-1 lg:sticky lg:top-28 lg:flex-col lg:overflow-visible lg:pb-0"
    >
      {SETTINGS_SECTIONS.map(({ id, label, icon: Icon }) => {
        const active = section === id;

        return (
          <a
            key={id}
            href={`#/settings/${id}`}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex min-h-12 shrink-0 items-center gap-3 rounded-control border px-3.5 py-2.5 text-left transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus lg:w-full",
              active
                ? "order-first border-accent/35 bg-accent-soft text-ink lg:order-none"
                : "border-transparent text-ink-soft hover:border-line hover:bg-surface hover:text-ink",
            )}
          >
            <span
              className={cn(
                "grid size-8 shrink-0 place-items-center rounded-lg",
                active
                  ? "bg-accent text-on-accent"
                  : "bg-surface-strong text-ink-faint",
              )}
            >
              <Icon size={16} aria-hidden="true" />
            </span>
            <span className="block text-sm font-semibold">{label}</span>
          </a>
        );
      })}
    </nav>
  );
}

function AppearancePreview({
  mode,
  selected,
}: {
  mode: (typeof APPEARANCE_MODES)[number];
  selected: boolean;
}) {
  const [background, surface, foreground] = mode.swatches;

  return (
    <div
      className="relative h-20 overflow-hidden rounded-xl border"
      style={{
        background,
        borderColor: selected ? foreground : `${foreground}30`,
      }}
      aria-hidden="true"
    >
      <div
        className="absolute inset-y-0 left-0 w-[28%] border-r p-2"
        style={{ borderColor: `${foreground}24` }}
      >
        <span
          className="block size-4 rounded-md"
          style={{ background: foreground }}
        />
        <span
          className="mt-3 block h-1.5 w-full rounded-full"
          style={{ background: `${foreground}40` }}
        />
        <span
          className="mt-2 block h-1.5 w-3/4 rounded-full"
          style={{ background: `${foreground}28` }}
        />
      </div>
      <div className="ml-[28%] p-3">
        <span
          className="block h-2 w-1/2 rounded-full"
          style={{ background: foreground }}
        />
        <span
          className="mt-2 block h-1.5 w-4/5 rounded-full"
          style={{ background: `${foreground}35` }}
        />
        <div className="mt-4 flex gap-2">
          <span
            className="h-7 flex-1 rounded-md"
            style={{ background: foreground }}
          />
          <span
            className="h-7 flex-1 rounded-md border"
            style={{
              background: surface,
              borderColor: `${foreground}35`,
            }}
          />
        </div>
      </div>
    </div>
  );
}

function SettingRow({
  icon,
  title,
  description,
  trailing,
}: {
  icon: ReactNode;
  title: string;
  description?: string;
  trailing: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-4 py-5 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-start gap-3.5">
        <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-surface-strong text-ink-soft">
          {icon}
        </span>
        <div>
          <h3 className="text-sm font-semibold text-ink">{title}</h3>
          {description && (
            <p className="mt-1 max-w-2xl text-xs leading-5 text-ink-soft">
              {description}
            </p>
          )}
        </div>
      </div>
      <div className="shrink-0 sm:pl-4">{trailing}</div>
    </div>
  );
}

export function SettingsPage() {
  const { appearance, accent, setAppearance, setAccent } =
    useAppearancePreference();
  const [waveform, setWaveform] =
    useState<WaveformVariant>(readWaveformVariant);
  const [sensitivity, setSensitivity] = useState(readWaveformSensitivity);
  const section = useSettingsSection();

  return (
    <div className="grid min-w-0 grid-cols-[minmax(0,1fr)] gap-7 lg:grid-cols-[13.5rem_minmax(0,1fr)] lg:gap-9">
      <div className="min-w-0">
        <SettingsNavigation section={section} />
      </div>

      <div className="min-w-0">
        {section === "shortcuts" && <><ShortcutSettingsSection /><DictationShortcutSettings /></>}
        {section === "dictation" && <DictationPreferences />}
        {section === "meetings" && <MeetingProfile />}

        {section === "appearance" && (
          <div className="space-y-9">
            <PageHeader title="Appearance" />

            <section aria-labelledby="appearance-heading" className="space-y-4">
              <SectionHeading id="appearance-heading" title="Theme" />
              <fieldset>
                <legend className="sr-only">Choose appearance</legend>
                <div className="grid gap-3 sm:grid-cols-3">
                  {APPEARANCE_MODES.map((option) => (
                    <label
                      key={option.id}
                      className={cn(
                        "group cursor-pointer rounded-card border bg-surface p-3 transition-colors focus-within:outline-3 focus-within:outline-offset-2 focus-within:outline-focus",
                        appearance === option.id
                          ? "border-ink"
                          : "border-line",
                      )}
                    >
                      <input
                        type="radio"
                        name="appearance"
                        value={option.id}
                        checked={appearance === option.id}
                        onChange={() =>
                          setAppearance(option.id as AppearanceMode)
                        }
                        className="sr-only"
                      />
                      <AppearancePreview
                        mode={option}
                        selected={appearance === option.id}
                      />
                      <span className="mt-3 flex items-center justify-between gap-3 px-1 pb-0.5">
                        <span className="text-sm font-medium text-ink">
                          {option.name}
                        </span>
                        <span
                          className={cn(
                            "grid size-5 shrink-0 place-items-center rounded-full border",
                            appearance === option.id
                              ? "border-accent bg-accent text-on-accent"
                              : "border-line-strong bg-surface-raised",
                          )}
                          aria-hidden="true"
                        >
                          {appearance === option.id && (
                            <Check size={12} strokeWidth={3} />
                          )}
                        </span>
                      </span>
                    </label>
                  ))}
                </div>
              </fieldset>
            </section>

            <section aria-labelledby="accent-heading" className="space-y-4">
              <SectionHeading id="accent-heading" title="Accent" />
              <fieldset>
                <legend className="sr-only">Choose accent color</legend>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                  {ACCENT_THEMES.map((option) => (
                    <label
                      key={option.id}
                      className={cn(
                        "flex min-h-14 cursor-pointer items-center gap-3 rounded-full border bg-surface px-4 transition-colors focus-within:outline-3 focus-within:outline-offset-2 focus-within:outline-focus",
                        accent === option.id
                          ? "border-ink"
                          : "border-line hover:border-line-strong",
                      )}
                    >
                      <input
                        type="radio"
                        name="accent"
                        value={option.id}
                        checked={accent === option.id}
                        onChange={() =>
                          setAccent(option.id as AccentTheme)
                        }
                        className="sr-only"
                      />
                      <span
                        className="grid size-6 shrink-0 place-items-center rounded-full border border-black/15"
                        style={{ background: option.color }}
                        aria-hidden="true"
                      >
                        {accent === option.id && (
                          <Check
                            size={13}
                            strokeWidth={3}
                            className={
                              option.id === "mono"
                                ? "text-black"
                                : "text-black/75"
                            }
                          />
                        )}
                      </span>
                      <span className="text-sm font-medium text-ink">
                        {option.name}
                      </span>
                    </label>
                  ))}
                </div>
              </fieldset>
            </section>

            <section aria-labelledby="waveform-heading" className="space-y-4">
              <SectionHeading id="waveform-heading" title="Waveform" />
              <Card className="space-y-5 p-5 sm:p-6">
                <RecorderPill
                  active
                  label="Listening"
                  variant={waveform}
                  sensitivity={sensitivity}
                />
                <div className="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
                  <fieldset>
                    <legend className="sr-only">Choose waveform</legend>
                    <div className="flex rounded-full border border-line bg-canvas-subtle p-1">
                      {WAVEFORM_VARIANTS.map((variant) => (
                        <label
                          key={variant.id}
                          className={cn(
                            "cursor-pointer rounded-full px-3 py-1.5 text-xs font-medium transition-colors",
                            waveform === variant.id
                              ? "bg-surface-raised text-ink"
                              : "text-ink-faint hover:text-ink",
                          )}
                        >
                          <input
                            className="sr-only"
                            type="radio"
                            name="waveform"
                            value={variant.id}
                            checked={waveform === variant.id}
                            onChange={() => {
                              setWaveform(variant.id);
                              writeWaveformVariant(variant.id);
                            }}
                          />
                          {variant.label}
                        </label>
                      ))}
                    </div>
                  </fieldset>

                  <label className="block min-w-40 text-xs font-medium text-ink-faint">
                    Response
                    <input
                      type="range"
                      min="0.7"
                      max="1.3"
                      step="0.1"
                      value={sensitivity}
                      aria-label="Waveform response"
                      onChange={(event) => {
                        const nextSensitivity = Number(event.target.value);
                        setSensitivity(nextSensitivity);
                        writeWaveformSensitivity(nextSensitivity);
                      }}
                      className="mt-3 block w-full accent-[var(--pvw-accent)]"
                    />
                  </label>
                </div>
              </Card>
            </section>
          </div>
        )}

        {section === "privacy" && (
          <div className="space-y-9">
            <PageHeader title="Privacy" />

            <section aria-labelledby="privacy-defaults-heading" className="space-y-4">
              <h2 id="privacy-defaults-heading" className="sr-only">
                Privacy settings
              </h2>
              <Card className="divide-y divide-line px-5">
                <SettingRow
                  icon={<Shield size={16} aria-hidden="true" />}
                  title="Cloud processing"
                  trailing={<Badge tone="success">Off</Badge>}
                />
                <SettingRow
                  icon={<Sparkles size={16} aria-hidden="true" />}
                  title="Analytics"
                  trailing={<Badge tone="success">Off</Badge>}
                />
                <SettingRow
                  icon={<Scissors size={16} aria-hidden="true" />}
                  title="Quick Clip"
                  trailing={<Badge tone="neutral">Clipboard only</Badge>}
                />
              </Card>
            </section>
          </div>
        )}
      </div>
    </div>
  );
}
