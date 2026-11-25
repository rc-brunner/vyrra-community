import type { CSSProperties, ReactNode } from "react";

import { cn } from "../lib/cn";
import {
  WAVEFORM_VARIANTS,
  type WaveformVariant,
} from "../lib/waveform";
import { StatusDot } from "./ui";

const heights = [22, 38, 56, 34, 68, 44, 78, 52, 84, 46, 72, 36, 62, 42, 76, 48, 66, 32, 58, 40, 70, 34, 50];

function waveformDefinition(variant: WaveformVariant) {
  return (
    WAVEFORM_VARIANTS.find((candidate) => candidate.id === variant) ??
    WAVEFORM_VARIANTS[1]
  );
}

export function RecorderPill({
  active,
  paused = false,
  label,
  elapsed = "00:00",
  variant = "flow",
  sensitivity = 1,
  level,
  action,
}: {
  active: boolean;
  paused?: boolean;
  label: string;
  elapsed?: string;
  variant?: WaveformVariant;
  sensitivity?: number;
  level?: number;
  action?: ReactNode;
}) {
  const definition = waveformDefinition(variant);
  const bars = heights.slice(0, definition.barCount);
  const response = Math.min(1.3, Math.max(0.7, sensitivity));

  return (
    <div className="recorder-strip flex min-h-16 w-full items-center gap-4 rounded-full border border-line bg-surface-raised px-3 py-2 sm:px-4">
      <div className="flex min-w-20 shrink-0 items-center gap-2">
        <StatusDot tone={active ? "success" : "neutral"} />
        <span className="text-xs font-medium text-ink-soft">{label}</span>
      </div>

      <div
        className="flex h-10 min-w-0 flex-1 items-center justify-center gap-[3px] overflow-hidden px-1"
        aria-label={active ? (level === undefined ? "Animated waveform preview" : "Microphone input level") : "Inactive waveform"}
        role="img"
      >
        {bars.map((height, index) => {
          const style = {
            "--vyrra-wave-height": `${level === undefined ? Math.max(7, Math.round(height * 0.38 * response)) : Math.max(3, Math.round(height * 0.40 * response * Math.sqrt(level)))}px`,
            "--vyrra-wave-delay": `${-(index * 0.075)}s`,
            "--vyrra-wave-duration": `${(definition.duration + (index % 4) * 0.07) / response}s`,
          } as CSSProperties;

          return (
            <span
              key={`${variant}-${index}`}
              className={cn(
                "vyrra-wave-bar w-[3px] shrink-0 rounded-full bg-ink",
                active && !paused && level === undefined && "vyrra-wave-bar-active",
                paused && "opacity-45",
                !active && "opacity-25",
              )}
              style={style}
            />
          );
        })}
      </div>

      <span className="shrink-0 font-mono text-xs font-medium tabular-nums text-ink-soft">
        {elapsed}
      </span>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}
