import axe from "axe-core";
import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { App } from "./App";
import { ROUTES } from "./lib/navigation";

describe("prototype accessibility structure", () => {
  it.each(ROUTES)("%s has no automated axe violations", async (route) => {
    window.location.hash = `#/${route}`;
    const { container } = render(<App />);
    const results = await axe.run(container, {
      rules: {
        // jsdom cannot calculate rendered color contrast; token contrast has a
        // separate deterministic test.
        "color-contrast": { enabled: false },
      },
    });

    expect(
      results.violations.map((violation) => ({
        id: violation.id,
        targets: violation.nodes.map((node) => node.target),
      })),
    ).toEqual([]);
  });

  it.each(["appearance", "privacy"])(
    "settings/%s has no automated axe violations",
    async (section) => {
      window.location.hash = `#/settings/${section}`;
      const { container } = render(<App />);
      const results = await axe.run(container, {
        rules: {
          "color-contrast": { enabled: false },
        },
      });

      expect(
        results.violations.map((violation) => ({
          id: violation.id,
          targets: violation.nodes.map((node) => node.target),
        })),
      ).toEqual([]);
    },
  );
});
