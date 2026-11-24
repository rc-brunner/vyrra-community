export const WAVEFORM_VARIANTS = [
  { id: "calm", label: "Calm", barCount: 13, duration: 1.45 },
  { id: "flow", label: "Flow", barCount: 17, duration: 1.05 },
  { id: "detail", label: "Detail", barCount: 23, duration: 0.82 },
] as const;

export type WaveformVariant = (typeof WAVEFORM_VARIANTS)[number]["id"];

export const WAVEFORM_STORAGE_KEY = "pvw.capture.waveform";
export const WAVEFORM_SENSITIVITY_STORAGE_KEY =
  "pvw.capture.waveform-sensitivity";

export function isWaveformVariant(value: unknown): value is WaveformVariant {
  return WAVEFORM_VARIANTS.some((variant) => variant.id === value);
}

export function readWaveformVariant(
  storage: Pick<Storage, "getItem"> = window.localStorage,
): WaveformVariant {
  try {
    const stored = storage.getItem(WAVEFORM_STORAGE_KEY);
    return isWaveformVariant(stored) ? stored : "flow";
  } catch {
    return "flow";
  }
}

export function writeWaveformVariant(
  variant: WaveformVariant,
  storage: Pick<Storage, "setItem"> = window.localStorage,
): void {
  try {
    storage.setItem(WAVEFORM_STORAGE_KEY, variant);
  } catch {
    // The waveform selection remains active for this session.
  }
}

export function readWaveformSensitivity(
  storage: Pick<Storage, "getItem"> = window.localStorage,
): number {
  try {
    const stored = Number(storage.getItem(WAVEFORM_SENSITIVITY_STORAGE_KEY));
    return Number.isFinite(stored) && stored >= 0.7 && stored <= 1.3
      ? stored
      : 1;
  } catch {
    return 1;
  }
}

export function writeWaveformSensitivity(
  sensitivity: number,
  storage: Pick<Storage, "setItem"> = window.localStorage,
): void {
  const bounded = Math.min(1.3, Math.max(0.7, sensitivity));

  try {
    storage.setItem(WAVEFORM_SENSITIVITY_STORAGE_KEY, String(bounded));
  } catch {
    // The response setting remains active for this session.
  }
}
