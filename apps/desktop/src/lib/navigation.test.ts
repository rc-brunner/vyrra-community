import { describe, expect, it } from "vitest";

import {
  hrefForRoute,
  isRouteId,
  routeFromHash,
} from "./navigation";

describe("navigation", () => {
  it.each([
    ["#/capture", "capture"],
    ["#capture", "capture"],
    ["#/models", "models"],
    ["#/settings/privacy", "settings"],
    ["#/library/item", "library"],
  ] as const)("parses %s as the %s route", (hash, expected) => {
    expect(routeFromHash(hash)).toBe(expected);
  });

  it.each(["", "#", "#/", "#/unknown", "#/Capture"])(
    "falls back to dictation for an unsupported hash: %s",
    (hash) => {
      expect(routeFromHash(hash)).toBe("capture");
    },
  );

  it("validates release route identifiers and generates canonical hashes", () => {
    expect(isRouteId("library")).toBe(true);
    expect(isRouteId("meetings")).toBe(true);
    expect(hrefForRoute("library")).toBe("#/library");
  });
});
