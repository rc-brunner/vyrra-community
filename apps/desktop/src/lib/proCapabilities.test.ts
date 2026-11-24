import { describe, expect, it } from "vitest";

import {
  CAPABILITY_CATEGORIES,
  CAPABILITY_REFERENCE_URL,
  CURRENT_CAPABILITIES,
  DOCUMENTED_PRO_EXTENSIONS,
  ROADMAP_CAPABILITIES,
  VENDOR_SERVICE_REFERENCES,
} from "./proCapabilities";

const EXPECTED_CURRENT_IDS_BY_CATEGORY = {
  transcription: [
    "transcription-local-models",
    "transcription-cloud-models",
    "transcription-language-coverage",
    "transcription-windows-gpu",
    "transcription-history",
    "transcription-manual-files",
    "transcription-realtime-preview",
    "transcription-speaker-diarization",
    "transcription-translate-english",
    "transcription-parallel-queue",
    "transcription-structured-exports",
    "transcription-document-exports",
  ],
  "meeting-notes": [
    "meeting-unlimited-recording",
    "meeting-auto-detect",
    "meeting-pause-resume",
    "meeting-mute-background",
    "meeting-speaker-diarization",
    "meeting-built-in-summary",
    "meeting-custom-summary-templates",
    "meeting-custom-instructions",
    "meeting-chat",
    "meeting-import-media",
  ],
  ai: [
    "ai-byok-enhancement",
    "ai-command-mode",
    "ai-per-app-tones",
    "ai-memory",
    "ai-global-instructions",
    "ai-dictionary-corrections",
    "ai-multiple-api-providers",
  ],
  productivity: [
    "productivity-custom-shortcut",
    "productivity-alternative-shortcuts",
    "productivity-dictionary-threads",
    "productivity-text-expander",
    "productivity-workflows",
    "productivity-workflow-webhooks-scripts",
    "productivity-custom-utilities",
    "productivity-data-portability",
  ],
  integrations: [
    "integration-obsidian",
    "integration-webhooks",
    "integration-cloud-sync",
  ],
} as const;

describe("current capability inventory", () => {
  it("covers every row in the current comparison matrix exactly once", () => {
    expect(CURRENT_CAPABILITIES).toHaveLength(40);

    for (const [category, expectedIds] of Object.entries(
      EXPECTED_CURRENT_IDS_BY_CATEGORY,
    )) {
      expect(
        CURRENT_CAPABILITIES.filter(
          (capability) => capability.category === category,
        ).map((capability) => capability.id),
      ).toEqual(expectedIds);
    }
  });

  it("distinguishes baseline rows from advanced parity", () => {
    expect(
      CURRENT_CAPABILITIES.filter(
        (capability) => capability.parity === "baseline",
      ),
    ).toHaveLength(10);
    expect(
      CURRENT_CAPABILITIES.filter(
        (capability) => capability.parity === "advanced",
      ),
    ).toHaveLength(30);
  });

  it("uses unique, UI-safe IDs and complete display metadata", () => {
    const allIds = [
      ...CURRENT_CAPABILITIES.map(({ id }) => id),
      ...DOCUMENTED_PRO_EXTENSIONS.map(({ id }) => id),
      ...ROADMAP_CAPABILITIES.map(({ id }) => id),
      ...VENDOR_SERVICE_REFERENCES.map(({ id }) => id),
    ];

    expect(new Set(allIds).size).toBe(allIds.length);

    for (const capability of CURRENT_CAPABILITIES) {
      expect(capability.id).toMatch(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
      expect(capability.title.trim()).not.toBe("");
      expect(capability.description.trim()).not.toBe("");
      expect(capability.deliveryDetail.trim()).not.toBe("");
      expect(capability.sourceUrl).toBe(CAPABILITY_REFERENCE_URL);
    }
  });

  it("isolates documented extensions that are broader than the pricing matrix", () => {
    expect(DOCUMENTED_PRO_EXTENSIONS).toHaveLength(3);
    const currentIds = new Set<string>(
      CURRENT_CAPABILITIES.map(({ id }) => id),
    );

    for (const extension of DOCUMENTED_PRO_EXTENSIONS) {
      expect(currentIds.has(extension.id)).toBe(false);
      expect(extension.sourceUrl).toMatch(/^https:\/\/docs\.vowen\.ai\//);
      expect(extension.sourceNote.trim()).not.toBe("");
      expect(["prototype", "adapter-required", "planned"]).toContain(
        extension.delivery,
      );
    }
  });

  it("keeps delivery claims within the honest prototype vocabulary", () => {
    const allowedDeliveryStates = new Set([
      "prototype",
      "adapter-required",
      "planned",
    ]);

    for (const capability of CURRENT_CAPABILITIES) {
      expect(allowedDeliveryStates.has(capability.delivery)).toBe(true);
    }

    expect(
      CURRENT_CAPABILITIES.filter(
        (capability) => capability.delivery === "prototype",
    ).map(({ id }) => id),
    ).toEqual([
      "productivity-custom-shortcut",
      "productivity-alternative-shortcuts",
      "productivity-workflows",
    ]);
  });

  it("maps every current row to a declared category and product route", () => {
    const categoryIds = new Set(
      CAPABILITY_CATEGORIES.map((category) => category.id),
    );
    const targets = new Set([
      "library",
      "meetings",
      "automations",
      "models",
      "settings",
    ]);

    for (const capability of CURRENT_CAPABILITIES) {
      expect(categoryIds.has(capability.category)).toBe(true);
      expect(capability.category).not.toBe("perks");
      expect(targets.has(capability.target)).toBe(true);
    }
  });
});

describe("non-product reference inventory", () => {
  it("keeps vendor service promises reference-only", () => {
    expect(VENDOR_SERVICE_REFERENCES).toHaveLength(4);
    const currentIds = new Set<string>(
      CURRENT_CAPABILITIES.map(({ id }) => id),
    );

    for (const reference of VENDOR_SERVICE_REFERENCES) {
      expect(reference.category).toBe("perks");
      expect(reference.status).toBe("reference-only");
      expect(reference.sourceUrl).toBe(CAPABILITY_REFERENCE_URL);
      expect(currentIds.has(reference.id)).toBe(false);
    }
  });

  it("keeps all nine future items outside the current capability set", () => {
    expect(ROADMAP_CAPABILITIES).toHaveLength(9);
    const currentIds = new Set<string>(
      CURRENT_CAPABILITIES.map(({ id }) => id),
    );

    for (const item of ROADMAP_CAPABILITIES) {
      expect(item.status).toBe("roadmap");
      expect("delivery" in item).toBe(false);
      expect(currentIds.has(item.id)).toBe(false);
      expect(item.sourceUrl).toBe(CAPABILITY_REFERENCE_URL);
    }
  });
});
