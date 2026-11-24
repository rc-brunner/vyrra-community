import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { CapabilityCoverageSection } from "./CapabilityCoverageSection";

describe("capability coverage", () => {
  it("renders the complete current matrix and documented extensions", () => {
    render(<CapabilityCoverageSection />);

    expect(screen.getByText("43 capabilities mapped")).toBeInTheDocument();
    expect(screen.getByText("30")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Transcription" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Documented extensions" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Cloud sync across three devices"),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Read-only context connectors"),
    ).toBeInTheDocument();
  });

  it("filters foundation and advanced rows without mixing roadmap items", async () => {
    const user = userEvent.setup();
    render(<CapabilityCoverageSection />);

    await user.click(
      screen.getByRole("button", { name: "Foundation" }),
    );

    expect(screen.getByText("Local transcription models")).toBeInTheDocument();
    expect(
      screen.queryByText("Cloud sync across three devices"),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Documented extensions" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByText("Reference roadmap").closest("details"),
    ).not.toHaveAttribute("open");
  });

  it("searches titles, details, and product areas with an honest empty state", async () => {
    const user = userEvent.setup();
    render(<CapabilityCoverageSection />);
    const search = screen.getByRole("searchbox", {
      name: "Search capabilities",
    });

    await user.type(search, "Obsidian");
    expect(screen.getByText("Obsidian integration")).toBeInTheDocument();
    expect(
      screen.queryByText("Meeting detection"),
    ).not.toBeInTheDocument();

    await user.clear(search);
    await user.type(search, "not a real capability");
    expect(
      screen.getByRole("heading", {
        name: "No capabilities match “not a real capability”",
      }),
    ).toBeInTheDocument();
  });
});
