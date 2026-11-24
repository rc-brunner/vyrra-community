import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  activateNativeShortcuts,
  configureNativeShortcuts,
  getNativePermissionStatus,
  getNativeRuntimeStatus,
  getNativeShortcutConfiguration,
  requestNativePermission,
  runQuickClip,
} from "../lib/native";
import { ShortcutSettingsSection } from "./ShortcutSettingsSection";

vi.mock("../lib/native", () => ({
  activateNativeShortcuts: vi.fn(),
  configureNativeShortcuts: vi.fn(),
  getNativePermissionStatus: vi.fn(),
  getNativeRuntimeStatus: vi.fn(),
  getNativeShortcutConfiguration: vi.fn(),
  requestNativePermission: vi.fn(),
  runQuickClip: vi.fn(),
}));

const mockedActivateShortcuts = vi.mocked(activateNativeShortcuts);
const mockedConfigureShortcuts = vi.mocked(configureNativeShortcuts);
const mockedRuntimeStatus = vi.mocked(getNativeRuntimeStatus);
const mockedPermissionStatus = vi.mocked(getNativePermissionStatus);
const mockedShortcutConfiguration = vi.mocked(
  getNativeShortcutConfiguration,
);
const mockedRequestPermission = vi.mocked(requestNativePermission);
const mockedRunQuickClip = vi.mocked(runQuickClip);

describe("native Quick Clip settings", () => {
  beforeEach(() => {
    mockedActivateShortcuts.mockReset();
    mockedConfigureShortcuts.mockReset();
    mockedRuntimeStatus.mockReset();
    mockedPermissionStatus.mockReset();
    mockedShortcutConfiguration.mockReset();
    mockedRequestPermission.mockReset();
    mockedRunQuickClip.mockReset();

    mockedRuntimeStatus.mockResolvedValue({
      shell: "tauri",
      version: "0.1.0",
      platform: "macos",
      distributionChannel: "development",
      nativeShortcutsAvailable: false,
      quickClipAvailable: true,
      audioCaptureAvailable: false,
    });
    mockedPermissionStatus.mockResolvedValue({
      inputMonitoring: "not_granted",
      screenCapture: "not_granted",
    });
    mockedShortcutConfiguration.mockResolvedValue({
      bindings: [],
      configuredBindings: 0,
      effectiveBindings: 0,
      listenerState: "disabled",
      externalConflict: null,
    });
  });

  it("requests permission on the user's action and runs Quick Clip", async () => {
    const user = userEvent.setup();
    mockedRequestPermission.mockResolvedValue({
      inputMonitoring: "not_granted",
      screenCapture: "granted",
    });
    mockedRunQuickClip.mockResolvedValue({
      status: "success",
      clipboardUpdated: true,
    });

    render(<ShortcutSettingsSection />);

    const tryButton = await screen.findByRole("button", {
      name: "Test",
    });
    await waitFor(() => expect(tryButton).toBeEnabled());
    await user.click(tryButton);

    expect(mockedRequestPermission).toHaveBeenCalledWith("screen_capture");
    expect(mockedRunQuickClip).toHaveBeenCalledWith(false);
    expect(
      await screen.findAllByText(
        "The selected region is now on the system clipboard.",
      ),
    ).not.toHaveLength(0);
  });

  it("does not invoke capture when permission remains denied", async () => {
    const user = userEvent.setup();
    mockedRequestPermission.mockResolvedValue({
      inputMonitoring: "not_granted",
      screenCapture: "not_granted",
    });

    render(<ShortcutSettingsSection />);

    const tryButton = await screen.findByRole("button", {
      name: "Test",
    });
    await waitFor(() => expect(tryButton).toBeEnabled());
    await user.click(tryButton);

    expect(mockedRunQuickClip).not.toHaveBeenCalled();
    expect(
      await screen.findAllByText(/Allow Vyrra Desktop in System Settings/i),
    ).not.toHaveLength(0);
  });

  it("loads, saves, permits, and activates native Quick Clip double taps", async () => {
    const user = userEvent.setup();
    mockedRuntimeStatus.mockResolvedValue({
      shell: "tauri",
      version: "0.1.0",
      platform: "macos",
      distributionChannel: "development",
      nativeShortcutsAvailable: true,
      quickClipAvailable: true,
      audioCaptureAvailable: false,
    });
    mockedShortcutConfiguration.mockResolvedValue({
      bindings: [
        {
          actionId: "quick-clip",
          enabled: true,
          gesture: {
            kind: "double-tap",
            key: { code: "Meta", location: "either" },
            intervalMs: 350,
            maxPressMs: 250,
          },
        },
      ],
      configuredBindings: 1,
      effectiveBindings: 1,
      listenerState: "permission_required",
      externalConflict: null,
    });
    mockedConfigureShortcuts.mockResolvedValue({
      bindings: [
        {
          actionId: "quick-clip",
          enabled: true,
          gesture: {
            kind: "double-tap",
            key: { code: "KeyK", location: "standard" },
            intervalMs: 350,
            maxPressMs: 250,
          },
        },
      ],
      configuredBindings: 1,
      effectiveBindings: 1,
      listenerState: "permission_required",
      externalConflict: null,
    });
    mockedRequestPermission.mockResolvedValue({
      inputMonitoring: "granted",
      screenCapture: "not_granted",
    });
    mockedActivateShortcuts.mockResolvedValue({
      bindings: [
        {
          actionId: "quick-clip",
          enabled: true,
          gesture: {
            kind: "double-tap",
            key: { code: "KeyK", location: "standard" },
            intervalMs: 350,
            maxPressMs: 250,
          },
        },
      ],
      configuredBindings: 1,
      effectiveBindings: 1,
      listenerState: "active",
      externalConflict: null,
    });

    render(<ShortcutSettingsSection />);

    expect(
      await screen.findByRole("switch", { name: "Enable Quick Clip" }),
    ).toHaveAttribute("aria-checked", "true");
    expect(
      screen.getByRole("img", {
        name: "Double-tap Command on either side",
      }),
    ).toBeInTheDocument();

    await user.click(
      screen.getByRole("button", { name: "Edit Quick Clip shortcut" }),
    );
    const capture = screen.getByRole("textbox", {
      name: "Shortcut",
    });
    expect(screen.queryByText("Gesture type")).not.toBeInTheDocument();
    expect(screen.queryByText("Modifier side")).not.toBeInTheDocument();
    expect(
      screen.queryByRole("radio", { name: "Key combination" }),
    ).not.toBeInTheDocument();
    for (let index = 0; index < 2; index += 1) {
      fireEvent.keyDown(capture, { key: "k", code: "KeyK" });
      fireEvent.keyUp(capture, { key: "k", code: "KeyK" });
    }
    await user.click(screen.getByRole("button", { name: "Save shortcut" }));

    await waitFor(() =>
      expect(mockedConfigureShortcuts).toHaveBeenCalledWith([
        {
          actionId: "quick-clip",
          enabled: true,
          gesture: {
            kind: "double-tap",
            key: { code: "KeyK", location: "standard" },
            intervalMs: 350,
            maxPressMs: 250,
          },
        },
      ]),
    );
    expect(mockedRequestPermission).toHaveBeenCalledWith("input_monitoring");
    await waitFor(() =>
      expect(mockedActivateShortcuts).toHaveBeenCalledOnce(),
    );
    expect(
      await screen.findByText(/native quick clip double-tap listener active/i),
    ).toBeInTheDocument();
  });

  it("keeps shortcut editing to one double-tap field", async () => {
    const user = userEvent.setup();
    mockedRuntimeStatus.mockResolvedValue({
      shell: "tauri",
      version: "0.1.0",
      platform: "macos",
      distributionChannel: "development",
      nativeShortcutsAvailable: true,
      quickClipAvailable: true,
      audioCaptureAvailable: false,
    });
    mockedPermissionStatus.mockResolvedValue({
      inputMonitoring: "granted",
      screenCapture: "not_granted",
    });
    mockedShortcutConfiguration.mockResolvedValue({
      bindings: [
        {
          actionId: "quick-clip",
          enabled: true,
          gesture: {
            kind: "double-tap",
            key: { code: "Meta", location: "either" },
            intervalMs: 350,
            maxPressMs: 250,
          },
        },
      ],
      configuredBindings: 1,
      effectiveBindings: 1,
      listenerState: "active",
      externalConflict: null,
    });

    render(<ShortcutSettingsSection />);

    await screen.findByRole("switch", { name: "Enable Quick Clip" });
    await user.click(
      screen.getByRole("button", { name: "Edit Quick Clip shortcut" }),
    );
    expect(
      screen.getByRole("heading", { name: "Quick Clip", level: 2 }),
    ).toBeInTheDocument();
    expect(screen.getByText("Double-tap any key.")).toBeInTheDocument();
    expect(
      screen.getByRole("textbox", { name: "Shortcut" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Gesture type")).not.toBeInTheDocument();
    expect(screen.queryByText("Modifier side")).not.toBeInTheDocument();
    expect(
      screen.queryByRole("radio", { name: "Key combination" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByText(/raw keystrokes are not logged/i),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByText(/temporary renderer state/i),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Save shortcut" }),
    ).toBeEnabled();

    await user.click(
      screen.getByRole("button", { name: "Close shortcut editor" }),
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("persists native disable", async () => {
    const user = userEvent.setup();
    mockedRuntimeStatus.mockResolvedValue({
      shell: "tauri",
      version: "0.1.0",
      platform: "macos",
      distributionChannel: "development",
      nativeShortcutsAvailable: true,
      quickClipAvailable: true,
      audioCaptureAvailable: false,
    });
    const loadedBinding = {
      actionId: "quick-clip" as const,
      enabled: true,
      gesture: {
        kind: "double-tap" as const,
        key: { code: "KeyK", location: "standard" as const },
        intervalMs: 350,
        maxPressMs: 250,
      },
    };
    mockedShortcutConfiguration.mockResolvedValue({
      bindings: [loadedBinding],
      configuredBindings: 1,
      effectiveBindings: 1,
      listenerState: "active",
      externalConflict: null,
    });
    mockedPermissionStatus.mockResolvedValue({
      inputMonitoring: "granted",
      screenCapture: "not_granted",
    });
    mockedConfigureShortcuts
      .mockResolvedValueOnce({
        bindings: [{ ...loadedBinding, enabled: false }],
        configuredBindings: 0,
        effectiveBindings: 0,
        listenerState: "disabled",
        externalConflict: null,
      })
      .mockResolvedValueOnce({
        bindings: [],
        configuredBindings: 0,
        effectiveBindings: 0,
        listenerState: "disabled",
        externalConflict: null,
      });

    render(<ShortcutSettingsSection />);

    const quickClipSwitch = await screen.findByRole("switch", {
      name: "Enable Quick Clip",
    });
    await user.click(quickClipSwitch);

    await waitFor(() =>
      expect(mockedConfigureShortcuts).toHaveBeenNthCalledWith(1, [
        { ...loadedBinding, enabled: false },
      ]),
    );
    expect(mockedActivateShortcuts).not.toHaveBeenCalled();
    expect(quickClipSwitch).toHaveAttribute("aria-checked", "false");
  });
});
