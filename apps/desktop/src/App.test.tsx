import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { App } from "./App";

describe("release navigation", () => {
  beforeEach(() => {
    window.location.hash = "#/capture";
  });

  afterEach(() => {
    window.location.hash = "";
  });

  it("renders the initial hash route", () => {
    window.location.hash = "#/library";

    render(<App />);

    expect(
      screen.getByRole("heading", {
        level: 1,
        name: "Library",
      }),
    ).toBeInTheDocument();
    expect(document.title).toBe("Library · Vyrra Desktop");
    expect(
      screen.getAllByRole("link", { name: "Library" })[0],
    ).toHaveAttribute("aria-current", "page");
  });

  it("updates the page and title when the hash changes", async () => {
    window.location.hash = "#/library";
    render(<App />);

    window.location.hash = "#/capture";
    fireEvent(window, new HashChangeEvent("hashchange"));

    expect(
      await screen.findByRole("heading", {
        level: 1,
        name: "Speak naturally.",
      }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(document.title).toBe("Dictate · Vyrra Desktop"),
    );
    expect(
      screen.getAllByRole("link", { name: "Dictate" })[0],
    ).toHaveAttribute("aria-current", "page");
  });

  it("makes the model catalog reachable from primary navigation", () => {
    render(<App />);

    const primary = screen.getByRole("navigation", { name: "Primary" });
    expect(primary.querySelector('a[href="#/models"]')).toHaveTextContent("Models");
    expect(screen.getAllByRole("link", { name: "Dictate" })[0])
      .toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Library" })[0])
      .toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Settings" })[0])
      .toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Personalize" }))
      .not.toBeInTheDocument();
  });

  it("routes an unknown hash to dictation", () => {
    window.location.hash = "#/not-a-real-route";

    render(<App />);

    expect(
      screen.getByRole("heading", {
        level: 1,
        name: "Speak naturally.",
      }),
    ).toBeInTheDocument();
    expect(document.title).toBe("Dictate · Vyrra Desktop");
  });

  it("skips to main content without corrupting the active hash route", () => {
    window.location.hash = "#/settings";
    render(<App />);

    fireEvent.click(screen.getByRole("link", { name: "Skip to content" }));

    expect(window.location.hash).toBe("#/settings");
    expect(screen.getByRole("main")).toHaveFocus();
    expect(
      screen.getByRole("heading", {
        level: 1,
        name: "Shortcuts",
      }),
    ).toBeInTheDocument();
  });
});
