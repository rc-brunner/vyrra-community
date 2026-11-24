import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ShortcutSettingsSection } from "./ShortcutSettingsSection";

describe("shortcut settings release surface", () => {
  it("explains the browser boundary without exposing dead controls", async () => {
    render(<ShortcutSettingsSection />);

    expect(
      await screen.findByText("Quick Clip needs macOS"),
    ).toBeInTheDocument();
    expect(screen.getByText("Screenshot to clipboard")).toBeInTheDocument();
    expect(screen.getByText("Unavailable")).toBeInTheDocument();
    expect(screen.queryByRole("switch")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Test" }))
      .not.toBeInTheDocument();
  });

  it("does not expose future actions or development fixtures", async () => {
    render(<ShortcutSettingsSection />);

    await screen.findByText("Quick Clip needs macOS");
    for (const name of [
      "Open Capture",
      "Toggle dictation",
      "Hold to transcribe",
      "Command Mode",
      "Hands-free mode",
      "Start new note",
      "Paste last transcription",
    ]) {
      expect(screen.queryByRole("heading", { name }))
        .not.toBeInTheDocument();
    }
    expect(screen.queryByText(/development-machine/i))
      .not.toBeInTheDocument();
    expect(screen.queryByText(/prototype/i)).not.toBeInTheDocument();
  });
});
