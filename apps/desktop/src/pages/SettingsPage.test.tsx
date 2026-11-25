import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  ACCENT_STORAGE_KEY,
  APPEARANCE_STORAGE_KEY,
} from "../lib/appearance";
import {
  WAVEFORM_SENSITIVITY_STORAGE_KEY,
  WAVEFORM_STORAGE_KEY,
} from "../lib/waveform";
import { SettingsPage } from "./SettingsPage";

describe("release settings", () => {
  beforeEach(() => {
    window.location.hash = "#/settings/appearance";
    window.localStorage.clear();
    delete document.documentElement.dataset.appearance;
    delete document.documentElement.dataset.accent;
  });

  afterEach(() => {
    window.location.hash = "";
  });

  it("loads and changes appearance and accent independently", async () => {
    window.localStorage.setItem(APPEARANCE_STORAGE_KEY, "dark");
    window.localStorage.setItem(ACCENT_STORAGE_KEY, "plum");
    const user = userEvent.setup();

    render(<SettingsPage />);

    expect(screen.getByRole("radio", { name: "Dark" })).toBeChecked();
    expect(screen.getByRole("radio", { name: "Plum" })).toBeChecked();

    await user.click(screen.getByRole("radio", { name: "Light" }));
    await user.click(screen.getByRole("radio", { name: "Ocean" }));

    expect(document.documentElement.dataset.appearance).toBe("light");
    expect(document.documentElement.dataset.accent).toBe("ocean");
    expect(window.localStorage.getItem(APPEARANCE_STORAGE_KEY)).toBe("light");
    expect(window.localStorage.getItem(ACCENT_STORAGE_KEY)).toBe("ocean");
  });

  it("supports keyboard accent selection", async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);
    const forest = screen.getByRole("radio", { name: "Forest" });

    forest.focus();
    await user.keyboard(" ");

    expect(forest).toBeChecked();
    expect(document.documentElement.dataset.accent).toBe("forest");
  });

  it("keeps waveform customization in appearance", async () => {
    const user = userEvent.setup();
    render(<SettingsPage />);

    await user.click(screen.getByRole("radio", { name: "Detail" }));
    fireEvent.change(
      screen.getByRole("slider", { name: "Waveform response" }),
      { target: { value: "1.2" } },
    );

    expect(screen.getByRole("radio", { name: "Detail" })).toBeChecked();
    expect(window.localStorage.getItem(WAVEFORM_STORAGE_KEY)).toBe("detail");
    expect(window.localStorage.getItem(WAVEFORM_SENSITIVITY_STORAGE_KEY))
      .toBe("1.2");
    expect(
      screen.getByRole("img", { name: "Animated waveform preview" }).children,
    ).toHaveLength(23);
  });

  it("exposes dictation preferences alongside shortcuts, appearance, and privacy", () => {
    render(<SettingsPage />);

    const navigation = screen.getByRole("navigation", {
      name: "Settings sections",
    });
    expect(navigation.querySelectorAll("a")).toHaveLength(5);
    expect(screen.getByRole("link", { name: "Dictation" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Shortcuts" }))
      .toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Appearance" }))
      .toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Privacy" }))
      .toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Features" }))
      .not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Sync" }))
      .not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Personalization" }))
      .not.toBeInTheDocument();
  });

  it.each(["personalization", "capabilities", "sync"])(
    "falls back from hidden settings/%s to shortcuts",
    (section) => {
      window.location.hash = `#/settings/${section}`;
      render(<SettingsPage />);

      expect(
        screen.getByRole("heading", { level: 1, name: "Shortcuts" }),
      ).toBeInTheDocument();
      expect(screen.getByRole("link", { name: "Shortcuts" }))
        .toHaveAttribute("aria-current", "page");
    },
  );

  it("uses short, customer-facing privacy language", () => {
    window.location.hash = "#/settings/privacy";
    render(<SettingsPage />);

    expect(screen.getByText("Cloud processing")).toBeInTheDocument();
    expect(screen.getByText("Analytics")).toBeInTheDocument();
    expect(screen.getByText("Clipboard only")).toBeInTheDocument();
    expect(screen.queryByText(/adapter/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/prototype/i)).not.toBeInTheDocument();
  });
});
