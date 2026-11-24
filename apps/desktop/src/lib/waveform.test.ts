import { describe, expect, it, vi } from "vitest";

import {
  WAVEFORM_SENSITIVITY_STORAGE_KEY,
  WAVEFORM_STORAGE_KEY,
  isWaveformVariant,
  readWaveformVariant,
  readWaveformSensitivity,
  writeWaveformSensitivity,
  writeWaveformVariant,
} from "./waveform";

describe("waveform preferences", () => {
  it.each(["calm", "flow", "detail"])("accepts %s", (variant) => {
    expect(isWaveformVariant(variant)).toBe(true);
  });

  it("falls back to flow for unknown or inaccessible storage", () => {
    expect(
      readWaveformVariant({ getItem: vi.fn().mockReturnValue("unknown") }),
    ).toBe("flow");
    expect(
      readWaveformVariant({
        getItem: vi.fn(() => {
          throw new Error("storage denied");
        }),
      }),
    ).toBe("flow");
  });

  it("persists a supported selection", () => {
    const storage = { setItem: vi.fn() };
    writeWaveformVariant("calm", storage);
    expect(storage.setItem).toHaveBeenCalledWith(
      WAVEFORM_STORAGE_KEY,
      "calm",
    );
  });

  it("bounds and persists waveform response", () => {
    const storage = { setItem: vi.fn() };
    writeWaveformSensitivity(1.6, storage);

    expect(storage.setItem).toHaveBeenCalledWith(
      WAVEFORM_SENSITIVITY_STORAGE_KEY,
      "1.3",
    );
    expect(
      readWaveformSensitivity({
        getItem: vi.fn().mockReturnValue("0.9"),
      }),
    ).toBe(0.9);
  });
});
