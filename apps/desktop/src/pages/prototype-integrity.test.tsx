import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { MeetingsPage } from "./MeetingsPage";
import { ModelsPage } from "./ModelsPage";
import { LibraryPage } from "./LibraryPage";
import { AutomationsPage } from "./AutomationsPage";
import { TodayPage } from "./TodayPage";

describe("truthful prototype capability boundaries", () => {
  it("shows the real catalog and keeps device operations inside the native app", () => {
    render(<ModelsPage />);
    expect(screen.getByRole("heading", { name: "Models" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Download Whisper Small, Multilingual" })).toBeDisabled();
    expect(screen.getByRole("link", {name: "Whisper weights"})).toHaveAttribute("href", expect.stringContaining("huggingface.co/ggerganov/whisper.cpp"));
    expect(screen.getByText("Open Vyrra Desktop to install models on this device.")).toBeInTheDocument();
  });

  it("renders a genuine empty meeting history instead of fake data", () => {
    render(<MeetingsPage />);

    expect(screen.getByRole("heading", {name:"No meetings yet"})).toBeInTheDocument();
    expect(screen.getByRole("button", {name:"Schedule a meeting"})).toBeDisabled();
    expect(screen.queryByText("State fixture")).not.toBeInTheDocument();
  });

  it("keeps the dashboard recent-meeting section honest", () => {
    render(<TodayPage />);

    expect(
      screen.getByRole("heading", { name: "No sessions yet" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Preview mode")).toBeInTheDocument();
    expect(screen.getByText("Your recordings will appear here."))
      .toBeInTheDocument();
  });

  it("keeps an unavailable library simple and free of dead controls", () => {
    render(<LibraryPage />);

    expect(screen.queryByText("Not connected")).not.toBeInTheDocument();
    expect(screen.queryByRole("searchbox", { name: "Search library" }))
      .not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Import" }))
      .not.toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Nothing here yet" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Your transcripts will appear here."),
    ).toBeInTheDocument();
  });

  it("keeps command tools distinct and external execution closed", () => {
    render(<AutomationsPage />);

    expect(screen.getByText("Command workspace")).toBeInTheDocument();
    expect(screen.getByText("Voice workflows")).toBeInTheDocument();
    expect(screen.getByText("Text expansions")).toBeInTheDocument();
    expect(screen.getByText("Custom utilities")).toBeInTheDocument();
    expect(screen.getByText("Webhook delivery")).toBeInTheDocument();
    expect(
      screen.getByText(/Provider output cannot silently replace/i),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "New automation" }),
    ).toBeDisabled();
  });
});
