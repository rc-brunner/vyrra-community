import { useCallback, useState } from "react";

export const APPEARANCE_STORAGE_KEY = "pvw.appearance.theme";
export const ACCENT_STORAGE_KEY = "pvw.appearance.accent";

export const APPEARANCE_MODES = [
  {
    id: "system",
    name: "System",
    swatches: ["#f5f5f2", "#111113", "#050505"],
  },
  {
    id: "light",
    name: "Light",
    swatches: ["#f5f5f2", "#ffffff", "#111113"],
  },
  {
    id: "dark",
    name: "Dark",
    swatches: ["#050505", "#111113", "#f5f5f2"],
  },
] as const;

export const ACCENT_THEMES = [
  { id: "mono", name: "Mono", color: "#f5f5f2" },
  { id: "forest", name: "Forest", color: "#58a978" },
  { id: "indigo", name: "Indigo", color: "#767bd8" },
  { id: "ocean", name: "Ocean", color: "#6093b6" },
  { id: "plum", name: "Plum", color: "#a979a8" },
  { id: "ember", name: "Ember", color: "#bd7952" },
] as const;

export type AppearanceMode = (typeof APPEARANCE_MODES)[number]["id"];
export type AccentTheme = (typeof ACCENT_THEMES)[number]["id"];

export type AppearancePreference = {
  appearance: AppearanceMode;
  accent: AccentTheme;
};

const legacyPreferences: Record<string, AppearancePreference> = {
  system: { appearance: "system", accent: "mono" },
  canvas: { appearance: "light", accent: "ember" },
  studio: { appearance: "dark", accent: "mono" },
  grove: { appearance: "light", accent: "forest" },
  signal: { appearance: "light", accent: "ocean" },
  contrast: { appearance: "dark", accent: "mono" },
};

export function isAppearanceMode(value: unknown): value is AppearanceMode {
  return APPEARANCE_MODES.some((mode) => mode.id === value);
}

export function isAccentTheme(value: unknown): value is AccentTheme {
  return ACCENT_THEMES.some((accent) => accent.id === value);
}

export function readAppearancePreference(
  storage: Pick<Storage, "getItem"> = window.localStorage,
): AppearancePreference {
  try {
    const storedAppearance = storage.getItem(APPEARANCE_STORAGE_KEY);
    const storedAccent = storage.getItem(ACCENT_STORAGE_KEY);

    if (isAppearanceMode(storedAppearance)) {
      return {
        appearance: storedAppearance,
        accent: isAccentTheme(storedAccent) ? storedAccent : "mono",
      };
    }

    const migratedPreference =
      storedAppearance ? legacyPreferences[storedAppearance] : undefined;

    return (
      migratedPreference ?? { appearance: "system", accent: "mono" }
    );
  } catch {
    return { appearance: "system", accent: "mono" };
  }
}

export function writeAppearancePreference(
  preference: AppearancePreference,
  root: Pick<HTMLElement, "dataset"> = document.documentElement,
  storage: Pick<Storage, "setItem"> = window.localStorage,
): void {
  root.dataset.appearance = preference.appearance;
  root.dataset.accent = preference.accent;

  try {
    storage.setItem(APPEARANCE_STORAGE_KEY, preference.appearance);
    storage.setItem(ACCENT_STORAGE_KEY, preference.accent);
  } catch {
    // The selected appearance still applies for this session.
  }
}

export function useAppearancePreference() {
  const [preference, setPreference] = useState<AppearancePreference>(() =>
    readAppearancePreference(),
  );

  const setAppearance = useCallback(
    (appearance: AppearanceMode) => {
      const nextPreference = { ...preference, appearance };
      writeAppearancePreference(nextPreference);
      setPreference(nextPreference);
    },
    [preference],
  );

  const setAccent = useCallback(
    (accent: AccentTheme) => {
      const nextPreference = { ...preference, accent };
      writeAppearancePreference(nextPreference);
      setPreference(nextPreference);
    },
    [preference],
  );

  return { ...preference, setAppearance, setAccent };
}
