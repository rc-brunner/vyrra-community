import { invoke, isTauri } from "@tauri-apps/api/core";
import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  activateNativeShortcuts,
  configureNativeShortcuts,
  getNativePermissionStatus,
  getNativeRuntimeStatus,
  getNativeShortcutConfiguration,
  requestNativePermission,
  runQuickClip,
} from "./native";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
  isTauri: vi.fn(),
}));

const mockedInvoke = vi.mocked(invoke);
const mockedIsTauri = vi.mocked(isTauri);

describe("native desktop bridge", () => {
  beforeEach(() => {
    mockedInvoke.mockReset();
    mockedIsTauri.mockReset();
  });

  it("returns truthful browser fallbacks without issuing IPC", async () => {
    mockedIsTauri.mockReturnValue(false);

    await expect(getNativeRuntimeStatus()).resolves.toMatchObject({
      shell: "browser",
      nativeShortcutsAvailable: false,
      quickClipAvailable: false,
      audioCaptureAvailable: false,
    });
    await expect(getNativePermissionStatus()).resolves.toEqual({
      inputMonitoring: "unsupported",
      screenCapture: "unsupported",
    });
    await expect(runQuickClip(true)).resolves.toEqual({
      status: "unsupported",
      clipboardUpdated: false,
    });
    await expect(getNativeShortcutConfiguration()).resolves.toMatchObject({
      bindings: [],
      configuredBindings: 0,
      effectiveBindings: 0,
      listenerState: "unsupported",
    });
    await expect(configureNativeShortcuts([])).resolves.toMatchObject({
      bindings: [],
      listenerState: "unsupported",
    });
    await expect(activateNativeShortcuts()).resolves.toMatchObject({
      bindings: [],
      listenerState: "unsupported",
    });

    expect(mockedInvoke).not.toHaveBeenCalled();
  });

  it("uses the bounded Tauri command surface", async () => {
    mockedIsTauri.mockReturnValue(true);
    mockedInvoke
      .mockResolvedValueOnce({
        shell: "tauri",
        version: "0.1.0",
        platform: "macos",
        distributionChannel: "development",
        nativeShortcutsAvailable: false,
        quickClipAvailable: true,
        audioCaptureAvailable: false,
      })
      .mockResolvedValueOnce({
        inputMonitoring: "not_granted",
        screenCapture: "not_granted",
      })
      .mockResolvedValueOnce({
        inputMonitoring: "not_granted",
        screenCapture: "granted",
      })
      .mockResolvedValueOnce({
        status: "success",
        clipboardUpdated: true,
      })
      .mockResolvedValueOnce({
        bindings: [],
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
      })
      .mockResolvedValueOnce({
        bindings: [],
        configuredBindings: 0,
        effectiveBindings: 0,
        listenerState: "disabled",
        externalConflict: null,
      });

    await getNativeRuntimeStatus();
    await getNativePermissionStatus();
    await requestNativePermission("screen_capture");
    await runQuickClip(false);
    await getNativeShortcutConfiguration();
    await configureNativeShortcuts([]);
    await activateNativeShortcuts();

    expect(mockedInvoke.mock.calls).toEqual([
      ["runtime_status"],
      ["native_permission_status"],
      [
        "request_native_permission",
        { permission: "screen_capture" },
      ],
      ["quick_clip", { promptForPermission: false }],
      ["native_shortcut_configuration"],
      ["configure_native_shortcuts", { bindings: [] }],
      ["activate_native_shortcuts"],
    ]);
  });
});
