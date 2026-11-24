import { describe, expect, it, vi } from "vitest";

import {
  ACCENT_STORAGE_KEY,
  APPEARANCE_STORAGE_KEY,
  isAccentTheme,
  isAppearanceMode,
  readAppearancePreference,
  writeAppearancePreference,
} from "./appearance";

describe("appearance preferences", () => {
  it.each(["system", "light", "dark"])(
    "accepts the supported %s appearance",
    (appearance) => {
      expect(isAppearanceMode(appearance)).toBe(true);
    },
  );

  it.each(["mono", "forest", "indigo", "ocean", "plum", "ember"])(
    "accepts the supported %s accent",
    (accent) => {
      expect(isAccentTheme(accent)).toBe(true);
    },
  );

  it("reads a stored appearance and accent", () => {
    const storage = {
      getItem: vi.fn((key: string) =>
        key === APPEARANCE_STORAGE_KEY ? "dark" : "plum",
      ),
    };

    expect(readAppearancePreference(storage)).toEqual({
      appearance: "dark",
      accent: "plum",
    });
  });

  it.each([
    ["canvas", { appearance: "light", accent: "ember" }],
    ["studio", { appearance: "dark", accent: "mono" }],
    ["grove", { appearance: "light", accent: "forest" }],
    ["signal", { appearance: "light", accent: "ocean" }],
    ["contrast", { appearance: "dark", accent: "mono" }],
  ])("migrates the legacy %s theme", (legacy, expected) => {
    const storage = {
      getItem: vi.fn((key: string) =>
        key === APPEARANCE_STORAGE_KEY ? legacy : null,
      ),
    };

    expect(readAppearancePreference(storage)).toEqual(expected);
  });

  it("fails safely to system and mono", () => {
    expect(
      readAppearancePreference({
        getItem: vi.fn(() => {
          throw new Error("storage denied");
        }),
      }),
    ).toEqual({ appearance: "system", accent: "mono" });
  });

  it("applies and persists both axes", () => {
    const root = { dataset: {} as DOMStringMap };
    const storage = { setItem: vi.fn() };

    writeAppearancePreference(
      { appearance: "light", accent: "ocean" },
      root,
      storage,
    );

    expect(root.dataset.appearance).toBe("light");
    expect(root.dataset.accent).toBe("ocean");
    expect(storage.setItem).toHaveBeenCalledWith(
      APPEARANCE_STORAGE_KEY,
      "light",
    );
    expect(storage.setItem).toHaveBeenCalledWith(ACCENT_STORAGE_KEY, "ocean");
  });

  it("keeps the session preference when persistence is unavailable", () => {
    const root = { dataset: {} as DOMStringMap };

    expect(() =>
      writeAppearancePreference(
        { appearance: "dark", accent: "forest" },
        root,
        {
          setItem: vi.fn(() => {
            throw new Error("quota exceeded");
          }),
        },
      ),
    ).not.toThrow();
    expect(root.dataset.appearance).toBe("dark");
    expect(root.dataset.accent).toBe("forest");
  });
});
