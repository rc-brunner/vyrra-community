import { invoke, isTauri } from "@tauri-apps/api/core";

export type PermissionState = "granted" | "not_granted" | "unsupported";

export type NativePermission = "input_monitoring" | "screen_capture";

export interface NativePermissionStatus {
  inputMonitoring: PermissionState;
  screenCapture: PermissionState;
}

export interface NativeRuntimeStatus {
  shell: "tauri" | "browser";
  version: string;
  platform: string;
  distributionChannel: "development" | "internal" | "browser";
  nativeShortcutsAvailable: boolean;
  quickClipAvailable: boolean;
  audioCaptureAvailable: boolean;
}

export type QuickClipStatus =
  | "success"
  | "cancelled"
  | "busy"
  | "permission_not_granted"
  | "external_conflict"
  | "capture_failed"
  | "clipboard_replaced"
  | "timed_out"
  | "unsupported";

export interface QuickClipOutcome {
  status: QuickClipStatus;
  clipboardUpdated: boolean;
}

export interface NativeShortcutKey {
  code: string;
  location: "standard" | "left" | "right" | "either";
}

export interface NativeShortcutDoubleTapGesture {
  kind: "double-tap";
  key: NativeShortcutKey;
  intervalMs: number;
  maxPressMs: number;
}

export interface NativeShortcutBinding {
  actionId: "quick-clip";
  enabled: boolean;
  gesture: NativeShortcutDoubleTapGesture;
}

export type NativeShortcutListenerState =
  | "active"
  | "starting"
  | "permission_required"
  | "external_conflict"
  | "disabled"
  | "failed"
  | "unsupported";

export interface NativeShortcutSnapshot {
  bindings: NativeShortcutBinding[];
  configuredBindings: number;
  effectiveBindings: number;
  listenerState: NativeShortcutListenerState;
  externalConflict: "control_shot" | null;
}

const BROWSER_RUNTIME_STATUS: NativeRuntimeStatus = {
  shell: "browser",
  version: "prototype",
  platform: "browser",
  distributionChannel: "browser",
  nativeShortcutsAvailable: false,
  quickClipAvailable: false,
  audioCaptureAvailable: false,
};

const UNSUPPORTED_PERMISSIONS: NativePermissionStatus = {
  inputMonitoring: "unsupported",
  screenCapture: "unsupported",
};

const BROWSER_SHORTCUT_SNAPSHOT: NativeShortcutSnapshot = {
  bindings: [],
  configuredBindings: 0,
  effectiveBindings: 0,
  listenerState: "unsupported",
  externalConflict: null,
};

export function isNativeDesktop() {
  return isTauri();
}

export async function getNativeRuntimeStatus(): Promise<NativeRuntimeStatus> {
  if (!isNativeDesktop()) return BROWSER_RUNTIME_STATUS;
  return invoke<NativeRuntimeStatus>("runtime_status");
}

export async function getNativePermissionStatus(): Promise<NativePermissionStatus> {
  if (!isNativeDesktop()) return UNSUPPORTED_PERMISSIONS;
  return invoke<NativePermissionStatus>("native_permission_status");
}

export async function requestNativePermission(
  permission: NativePermission,
): Promise<NativePermissionStatus> {
  if (!isNativeDesktop()) return UNSUPPORTED_PERMISSIONS;
  return invoke<NativePermissionStatus>("request_native_permission", {
    permission,
  });
}

export async function runQuickClip(
  promptForPermission: boolean,
): Promise<QuickClipOutcome> {
  if (!isNativeDesktop()) {
    return { status: "unsupported", clipboardUpdated: false };
  }

  return invoke<QuickClipOutcome>("quick_clip", { promptForPermission });
}

export async function getNativeShortcutConfiguration(): Promise<NativeShortcutSnapshot> {
  if (!isNativeDesktop()) return BROWSER_SHORTCUT_SNAPSHOT;
  return invoke<NativeShortcutSnapshot>("native_shortcut_configuration");
}

export async function configureNativeShortcuts(
  bindings: readonly NativeShortcutBinding[],
): Promise<NativeShortcutSnapshot> {
  if (!isNativeDesktop()) return BROWSER_SHORTCUT_SNAPSHOT;
  return invoke<NativeShortcutSnapshot>("configure_native_shortcuts", {
    bindings,
  });
}

export async function activateNativeShortcuts(): Promise<NativeShortcutSnapshot> {
  if (!isNativeDesktop()) return BROWSER_SHORTCUT_SNAPSHOT;
  return invoke<NativeShortcutSnapshot>("activate_native_shortcuts");
}
