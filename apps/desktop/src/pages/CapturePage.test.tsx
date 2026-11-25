import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as service from "../lib/dictation";
import * as native from "../lib/native";
import { WAVEFORM_SENSITIVITY_STORAGE_KEY, WAVEFORM_STORAGE_KEY } from "../lib/waveform";
import { CapturePage } from "./CapturePage";

vi.mock("../lib/native", async original => ({ ...await original<typeof native>(), isNativeDesktop: vi.fn() }));
vi.mock("../lib/dictation", async original => ({ ...await original<typeof service>(), useDictation: vi.fn(), dictate: vi.fn(), installModel: vi.fn() }));
const snapshot: service.DictationSnapshot = { phase: "idle", model: "ready", level: 0, elapsedMs: 0, revision: 0, text: "", error: null, delivery: null };

describe("desktop dictation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    vi.mocked(native.isNativeDesktop).mockReturnValue(true);
    vi.mocked(service.useDictation).mockReturnValue(snapshot);
    vi.mocked(service.dictate).mockResolvedValue(undefined);
  });
  afterEach(() => vi.restoreAllMocks());
  it("only displays listening after the native recorder confirms it", async () => {
    const view = render(<CapturePage />);
    fireEvent.click(screen.getByRole("button", { name: "Start dictation" }));
    expect(service.dictate).toHaveBeenCalledWith("start");
    expect(screen.queryByText("Listening")).not.toBeInTheDocument();
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, phase: "listening", elapsedMs: 2600, level: 0.8 });
    view.rerender(<CapturePage />);
    expect(screen.getByRole("img", { name: "Microphone input level" })).toBeInTheDocument();
    expect(screen.getByText("00:02")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Pause dictation" }));
    expect(service.dictate).toHaveBeenCalledWith("pause");
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, phase: "paused" });
    view.rerender(<CapturePage />);
    fireEvent.click(screen.getByRole("button", { name: "Resume dictation" }));
    fireEvent.click(screen.getByRole("button", { name: "Finish dictation" }));
    expect(service.dictate).toHaveBeenCalledWith("resume");
    expect(service.dictate).toHaveBeenCalledWith("finish");
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, phase: "transcribing" });
    view.rerender(<CapturePage />);
    fireEvent.click(screen.getByRole("button", { name: "Cancel dictation" }));
    await waitFor(() => expect(service.dictate).toHaveBeenCalledWith("cancel"));
  });
  it.each([
    { platform: "MacIntel", shortcut: "Meta+Enter", keys: ["⌘", "↩︎"], modifier: { metaKey: true } },
    { platform: "Win32", shortcut: "Control+Enter", keys: ["Ctrl", "Enter"], modifier: { ctrlKey: true } },
    { platform: "Linux x86_64", shortcut: "Control+Enter", keys: ["Ctrl", "Enter"], modifier: { ctrlKey: true } },
  ])("shows each shortcut key and runs the advertised action on $platform", ({ platform, shortcut, keys, modifier }) => {
    vi.spyOn(navigator, "platform", "get").mockReturnValue(platform);
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, text: "Keep my draft" });
    const view = render(<CapturePage />);
    const button = screen.getByRole("button", { name: "Start dictation" });
    expect(button).toHaveAttribute("aria-keyshortcuts", shortcut);
    expect(Array.from(button.querySelectorAll("kbd"), (key) => key.textContent)).toEqual(keys);
    fireEvent.keyDown(window, {key:"Enter", ...modifier, repeat:true});
    fireEvent.keyDown(window, {key:"Enter", ...modifier, isComposing:true});
    fireEvent.keyDown(screen.getByRole("textbox", {name:"Transcript"}), {key:"Enter", ...modifier});
    expect(service.dictate).not.toHaveBeenCalled();
    fireEvent.keyDown(window, {key:"Enter", ...modifier});
    expect(service.dictate).toHaveBeenCalledTimes(1);
    expect(service.dictate).toHaveBeenCalledWith("start");
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, phase: "listening" });
    view.rerender(<CapturePage />);
    expect(screen.getByRole("button", { name: "Finish dictation" })).toHaveAttribute("aria-keyshortcuts", shortcut);
    fireEvent.keyDown(window, { key: "Enter", ...modifier });
    expect(service.dictate).toHaveBeenLastCalledWith("finish");
  });
  it("keeps web previews and missing models from opening a microphone", () => {
    vi.mocked(native.isNativeDesktop).mockReturnValue(false);
    const view = render(<CapturePage />);
    expect(screen.getByRole("button", { name: "Start dictation" })).toBeDisabled();
    vi.mocked(native.isNativeDesktop).mockReturnValue(true);
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, model: "missing" });
    view.rerender(<CapturePage />);
    expect(screen.getByRole("button", { name: "Start dictation" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Choose local model" })).toBeEnabled();
    expect(service.installModel).not.toHaveBeenCalled();
  });
  it("preserves waveform settings and shows a usable transcript after insertion fails", () => {
    window.localStorage.setItem(WAVEFORM_STORAGE_KEY, "detail");
    window.localStorage.setItem(WAVEFORM_SENSITIVITY_STORAGE_KEY, "1.2");
    vi.mocked(service.useDictation).mockReturnValue({ ...snapshot, revision: 1, text: "Sample.", delivery: false });
    render(<CapturePage />);
    expect(screen.getByRole("img", { name: "Inactive waveform" }).children).toHaveLength(23);
    expect(screen.getByRole("textbox", { name: "Transcript" })).toHaveValue("Sample.");
    expect(screen.getByRole("button", { name: "Copy" })).toBeEnabled();
  });
});
