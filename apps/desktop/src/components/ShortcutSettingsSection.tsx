import {
  useEffect,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
} from "react";
import { Keyboard, Pencil, Scissors, X } from "lucide-react";

import {
  DEFAULT_QUICK_CLIP_GESTURE,
  DEFAULT_SHORTCUT_BINDINGS,
  SHORTCUT_ACTIONS,
  findShortcutConflict,
  formatShortcutGesture,
  formatShortcutGestureSpoken,
  shortcutGestureWarning,
  shortcutKeyFromKeyboardEvent,
  type ShortcutActionDefinition,
  type ShortcutActionId,
  type ShortcutBinding,
  type ShortcutGesture,
  type ShortcutKey,
  type ShortcutKeyLocation,
} from "../lib/shortcuts";
import { cn } from "../lib/cn";
import {
  activateNativeShortcuts,
  configureNativeShortcuts,
  getNativePermissionStatus,
  getNativeRuntimeStatus,
  getNativeShortcutConfiguration,
  requestNativePermission,
  runQuickClip,
  type NativePermissionStatus,
  type NativeRuntimeStatus,
  type NativeShortcutBinding,
  type NativeShortcutSnapshot,
  type QuickClipOutcome,
} from "../lib/native";
import {
  Badge,
  Button,
  Card,
  InlineNotice,
  PageHeader,
} from "./ui";

type TapMachine =
  | { phase: "idle" }
  | { phase: "first-down"; key: ShortcutKey; downAt: number }
  | {
      phase: "waiting-second";
      key: ShortcutKey;
      releasedAt: number;
    }
  | { phase: "second-down"; key: ShortcutKey; downAt: number };

function samePhysicalKey(left: ShortcutKey, right: ShortcutKey) {
  return left.code === right.code && left.location === right.location;
}

function hasUnexpectedHeldModifiers(
  event: ReactKeyboardEvent<HTMLInputElement>,
  key: ShortcutKey,
) {
  const targetModifier = key.kind === "modifier" ? key.code : null;
  return (
    (event.ctrlKey && targetModifier !== "Control") ||
    (event.altKey && targetModifier !== "Alt") ||
    (event.shiftKey && targetModifier !== "Shift") ||
    (event.metaKey && targetModifier !== "Meta")
  );
}

function bindingsForAction(
  bindings: readonly ShortcutBinding[],
  actionId: ShortcutActionId,
) {
  return bindings.filter((binding) => binding.actionId === actionId);
}

function ShortcutKeycap({ gesture }: { gesture: ShortcutGesture }) {
  const spoken = formatShortcutGestureSpoken(gesture);

  return (
    <span
      role="img"
      aria-label={spoken}
      title={spoken}
      className="inline-flex min-h-8 max-w-full items-center rounded-lg border border-line bg-surface-strong px-2.5 font-mono text-xs font-semibold text-ink shadow-sm"
    >
      <span className="truncate" aria-hidden="true">
        {formatShortcutGesture(gesture)}
      </span>
    </span>
  );
}

function ShortcutSwitch({
  checked,
  disabled = false,
  ariaLabel = "Enable Quick Clip",
  onChange,
}: {
  checked: boolean;
  disabled?: boolean;
  ariaLabel?: string;
  onChange: (checked: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative h-7 w-12 shrink-0 rounded-full border transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus",
        checked
          ? "border-accent bg-accent"
          : "border-line-strong bg-surface-strong",
        disabled && "cursor-not-allowed opacity-45",
      )}
    >
      <span
        aria-hidden="true"
        className={cn(
          "absolute top-1 size-[1.12rem] rounded-full bg-surface-raised shadow-sm transition-[left]",
          checked ? "left-[1.55rem]" : "left-1",
        )}
      />
    </button>
  );
}

function quickClipFeedback(outcome: QuickClipOutcome) {
  switch (outcome.status) {
    case "success":
      return {
        title: "Quick Clip copied",
        detail: "The selected region is now on the system clipboard.",
        tone: "privacy" as const,
      };
    case "cancelled":
      return {
        title: "Selection cancelled",
        detail: "The clipboard was not changed.",
        tone: "info" as const,
      };
    case "busy":
      return {
        title: "Quick Clip is already open",
        detail: "Finish or cancel the current region selection before trying again.",
        tone: "warning" as const,
      };
    case "permission_not_granted":
      return {
        title: "Screen Recording permission required",
        detail:
          "Allow Vyrra Desktop in System Settings, then return and try again.",
        tone: "warning" as const,
      };
    case "external_conflict":
      return {
        title: "Another Quick Clip owner is active",
        detail:
          "Quit ControlShot or disable its listener before running this action.",
        tone: "warning" as const,
      };
    case "clipboard_replaced":
      return {
        title: "Clipboard changed without an image",
        detail:
          "Vyrra did not accept the capture as complete. Your current clipboard content was left untouched by the app.",
        tone: "warning" as const,
      };
    case "timed_out":
      return {
        title: "Selection timed out",
        detail: "No screenshot was accepted before the native action expired.",
        tone: "warning" as const,
      };
    case "capture_failed":
      return {
        title: "Quick Clip did not complete",
        detail: outcome.clipboardUpdated
          ? "The clipboard changed, but the native capture process did not complete cleanly."
          : "The native capture process failed without updating the clipboard.",
        tone: "warning" as const,
      };
    case "unsupported":
      return {
        title: "Quick Clip is unavailable here",
        detail: "Open this screen in the Vyrra Desktop macOS app.",
        tone: "info" as const,
      };
  }
}

function shortcutKeyFromNative(
  code: string,
  location: ShortcutKeyLocation,
): ShortcutKey {
  const modifier = ["Meta", "Control", "Shift", "Alt"].includes(code);
  const eventCode = modifier
    ? `${code}${location === "right" ? "Right" : "Left"}`
    : code;
  const converted = shortcutKeyFromKeyboardEvent({
    code: eventCode,
    key: code === "Space" ? " " : code,
    location: location === "right" ? 2 : location === "left" ? 1 : 0,
  });

  return converted
    ? { ...converted, code, location }
    : {
        code,
        key: code,
        kind: "control",
        location,
      };
}

function shortcutBindingFromNative(
  binding: NativeShortcutBinding,
): ShortcutBinding {
  return {
    actionId: "quick-clip",
    gesture: {
      kind: "double-tap",
      key: shortcutKeyFromNative(
        binding.gesture.key.code,
        binding.gesture.key.location,
      ),
      intervalMs: binding.gesture.intervalMs,
      maxPressMs: binding.gesture.maxPressMs,
    },
  };
}

function nativeQuickClipBindings(
  bindings: readonly ShortcutBinding[],
  enabled: boolean,
): NativeShortcutBinding[] {
  return bindings.flatMap((binding) =>
    binding.actionId === "quick-clip" &&
    binding.gesture.kind === "double-tap"
      ? [
          {
            actionId: "quick-clip" as const,
            enabled,
            gesture: {
              kind: "double-tap" as const,
              key: {
                code: binding.gesture.key.code,
                location: binding.gesture.key.location,
              },
              intervalMs: binding.gesture.intervalMs,
              maxPressMs: binding.gesture.maxPressMs,
            },
          },
        ]
      : [],
  );
}

function ShortcutRecorder({
  action,
  bindings,
  excludedBinding,
  initialGesture,
  returnFocus,
  onClose,
  onSave,
}: {
  action: ShortcutActionDefinition;
  bindings: readonly ShortcutBinding[];
  excludedBinding: ShortcutBinding | null;
  initialGesture: ShortcutGesture | null;
  returnFocus: HTMLElement | null;
  onClose: () => void;
  onSave: (gesture: ShortcutGesture) => void;
}) {
  const [candidate, setCandidate] = useState<ShortcutGesture | null>(
    initialGesture?.kind === "double-tap" ? initialGesture : null,
  );
  const [captureStatus, setCaptureStatus] = useState(
    initialGesture?.kind === "double-tap" ? "Current shortcut" : "Ready",
  );
  const captureRef = useRef<HTMLInputElement>(null);
  const dialogRef = useRef<HTMLElement>(null);
  const tapMachine = useRef<TapMachine>({ phase: "idle" });
  const tapTimer = useRef<number | null>(null);

  const clearTapTimer = () => {
    if (tapTimer.current !== null) {
      window.clearTimeout(tapTimer.current);
      tapTimer.current = null;
    }
  };

  const resetTapMachine = () => {
    clearTapTimer();
    tapMachine.current = { phase: "idle" };
  };

  const cancelPendingTap = (message: string) => {
    if (tapMachine.current.phase === "idle") return;
    resetTapMachine();
    setCaptureStatus(message);
  };

  useEffect(() => {
    captureRef.current?.focus();
    return clearTapTimer;
  }, []);

  const close = () => {
    resetTapMachine();
    onClose();
    window.setTimeout(() => returnFocus?.focus(), 0);
  };

  const startFirstTap = (key: ShortcutKey, now: number) => {
    clearTapTimer();
    tapMachine.current = { phase: "first-down", key, downAt: now };
    setCaptureStatus("Tap again");
  };

  const handleDoubleTapKeyDown = (
    event: ReactKeyboardEvent<HTMLInputElement>,
    key: ShortcutKey,
  ) => {
    if (event.repeat) return;

    event.preventDefault();
    const now = event.timeStamp;
    const machine = tapMachine.current;

    if (
      machine.phase === "waiting-second" &&
      samePhysicalKey(machine.key, key) &&
      now - machine.releasedAt <= DEFAULT_QUICK_CLIP_GESTURE.intervalMs
    ) {
      clearTapTimer();
      tapMachine.current = { phase: "second-down", key, downAt: now };
      setCaptureStatus("Release to record");
      return;
    }

    startFirstTap(key, now);
  };

  const handleDoubleTapKeyUp = (
    event: ReactKeyboardEvent<HTMLInputElement>,
    key: ShortcutKey,
  ) => {
    event.preventDefault();
    const now = event.timeStamp;
    const machine = tapMachine.current;

    if (
      machine.phase === "first-down" &&
      samePhysicalKey(machine.key, key)
    ) {
      if (now - machine.downAt > DEFAULT_QUICK_CLIP_GESTURE.maxPressMs) {
        resetTapMachine();
        setCaptureStatus("Use two quick taps");
        return;
      }

      tapMachine.current = {
        phase: "waiting-second",
        key,
        releasedAt: now,
      };
      setCaptureStatus("Tap again");
      tapTimer.current = window.setTimeout(() => {
        tapMachine.current = { phase: "idle" };
        setCaptureStatus("Too slow — try again");
      }, DEFAULT_QUICK_CLIP_GESTURE.intervalMs);
      return;
    }

    if (
      machine.phase === "second-down" &&
      samePhysicalKey(machine.key, key)
    ) {
      if (now - machine.downAt > DEFAULT_QUICK_CLIP_GESTURE.maxPressMs) {
        resetTapMachine();
        setCaptureStatus("Use two quick taps");
        return;
      }

      resetTapMachine();
      setCandidate({
        kind: "double-tap",
        key,
        intervalMs: DEFAULT_QUICK_CLIP_GESTURE.intervalMs,
        maxPressMs: DEFAULT_QUICK_CLIP_GESTURE.maxPressMs,
      });
      setCaptureStatus("Recorded");
    }
  };

  const onCaptureKeyDown = (
    event: ReactKeyboardEvent<HTMLInputElement>,
  ) => {
    if (event.key === "Tab") {
      cancelPendingTap("Tap sequence cancelled when focus moved.");
      return;
    }
    if (event.key === "Escape") return;

    const key = shortcutKeyFromKeyboardEvent(event.nativeEvent);
    if (!key) {
      event.preventDefault();
      setCaptureStatus("Choose another key");
      resetTapMachine();
      return;
    }

    if (hasUnexpectedHeldModifiers(event, key)) {
      event.preventDefault();
      resetTapMachine();
      setCaptureStatus("Release the other keys");
      return;
    }

    handleDoubleTapKeyDown(event, key);
  };

  const onCaptureKeyUp = (event: ReactKeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Tab") return;
    const key = shortcutKeyFromKeyboardEvent(event.nativeEvent);
    if (key) handleDoubleTapKeyUp(event, key);
  };

  const candidateBinding = candidate
    ? { actionId: action.id, gesture: candidate }
    : null;
  const conflict = candidateBinding
    ? findShortcutConflict(candidateBinding, bindings, excludedBinding)
    : null;
  const conflictingAction = conflict
    ? SHORTCUT_ACTIONS.find(
        (definition) => definition.id === conflict.existing.actionId,
      )
    : null;
  const gestureWarning = candidate
    ? shortcutGestureWarning(candidate)
    : null;
  const describedBy = [
    "shortcut-capture-status",
    conflict ? "shortcut-conflict" : null,
    gestureWarning ? "shortcut-typing-warning" : null,
  ]
    .filter(Boolean)
    .join(" ");

  const handleDialogKeyDown = (
    event: ReactKeyboardEvent<HTMLDivElement>,
  ) => {
    if (event.key === "Escape") {
      event.preventDefault();
      close();
      return;
    }

    if (event.key !== "Tab") return;

    const focusable = Array.from(
      dialogRef.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])',
      ) ?? [],
    );
    const first = focusable[0];
    const last = focusable.at(-1);
    if (!first || !last) return;

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 grid place-items-center overflow-y-auto bg-ink/45 p-3 backdrop-blur-sm sm:p-6"
      onKeyDown={handleDialogKeyDown}
      onPointerDownCapture={() => cancelPendingTap("Ready")}
    >
      <section
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="shortcut-dialog-title"
        className="my-auto w-full max-w-lg rounded-card border border-line-strong bg-surface-raised p-5 text-ink shadow-lifted sm:p-6"
      >
        <header className="flex items-center justify-between gap-4">
          <div>
            <h2
              id="shortcut-dialog-title"
              className="text-xl font-semibold tracking-[-0.02em]"
            >
              {action.label}
            </h2>
            <p className="mt-1 text-sm text-ink-soft">Double-tap any key.</p>
          </div>
          <button
            type="button"
            onClick={close}
            aria-label="Close shortcut editor"
            className="grid size-10 shrink-0 place-items-center rounded-control text-ink-soft hover:bg-surface-strong hover:text-ink focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus"
          >
            <X size={18} aria-hidden="true" />
          </button>
        </header>

        <label
          htmlFor="shortcut-capture"
          className="sr-only"
        >
          Shortcut
        </label>
        <div className="relative mt-6">
          <Keyboard
            size={18}
            aria-hidden="true"
            className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-ink-faint"
          />
          <input
            ref={captureRef}
            id="shortcut-capture"
            readOnly
            value={candidate ? formatShortcutGesture(candidate) : ""}
            placeholder="Press twice"
            aria-describedby={describedBy}
            onKeyDown={onCaptureKeyDown}
            onKeyUp={onCaptureKeyUp}
            onBlur={() => cancelPendingTap("Ready")}
            className="h-16 w-full rounded-control border border-line-strong bg-surface pl-12 pr-4 text-center font-mono text-base font-semibold text-ink outline-none placeholder:font-sans placeholder:font-normal placeholder:text-ink-faint focus:border-accent focus:outline-3 focus:outline-offset-2 focus:outline-focus"
          />
        </div>
        <p
          id="shortcut-capture-status"
          className="mt-2 min-h-5 text-center text-xs font-medium text-ink-soft"
          aria-live="polite"
        >
          {captureStatus}
        </p>

        <div className="mt-3 space-y-2">
          {conflict && (
            <p
              id="shortcut-conflict"
              className="rounded-control border border-danger/35 bg-danger-soft px-3 py-2 text-xs leading-5 text-danger"
              role="alert"
            >
              Already assigned to {conflictingAction?.label ?? "another action"}.
            </p>
          )}
          {gestureWarning && (
            <p
              id="shortcut-typing-warning"
              className="rounded-control border border-warning/35 bg-warning-soft px-3 py-2 text-xs leading-5 text-warning"
            >
              This key may still act normally in other apps.
            </p>
          )}
        </div>

        <footer className="mt-6 flex justify-end gap-2 border-t border-line pt-4">
          <Button variant="quiet" onClick={close}>
            Cancel
          </Button>
          <Button
            disabled={!candidate || Boolean(conflict)}
            onClick={() => {
              if (!candidate || conflict) return;
              onSave(candidate);
              close();
            }}
          >
            Save shortcut
          </Button>
        </footer>
      </section>
    </div>
  );
}

export function ShortcutSettingsSection() {
  const [bindings, setBindings] = useState<ShortcutBinding[]>(() =>
    DEFAULT_SHORTCUT_BINDINGS.map((binding) => ({ ...binding })),
  );
  const [quickClipEnabled, setQuickClipEnabled] = useState(true);
  const [editingTarget, setEditingTarget] = useState<{
    actionId: ShortcutActionId;
    binding: ShortcutBinding | null;
  } | null>(null);
  const [returnFocus, setReturnFocus] = useState<HTMLElement | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const [nativeRuntime, setNativeRuntime] =
    useState<NativeRuntimeStatus | null>(null);
  const [nativePermissions, setNativePermissions] =
    useState<NativePermissionStatus | null>(null);
  const [nativeBridgeFailed, setNativeBridgeFailed] = useState(false);
  const [nativeShortcutSnapshot, setNativeShortcutSnapshot] =
    useState<NativeShortcutSnapshot | null>(null);
  const [nativeShortcutSaving, setNativeShortcutSaving] = useState(false);
  const [nativeShortcutError, setNativeShortcutError] = useState<string | null>(
    null,
  );
  const [quickClipRunning, setQuickClipRunning] = useState(false);
  const [quickClipResult, setQuickClipResult] =
    useState<ReturnType<typeof quickClipFeedback> | null>(null);

  useEffect(() => {
    let cancelled = false;

    Promise.all([
      getNativeRuntimeStatus(),
      getNativePermissionStatus(),
      getNativeShortcutConfiguration(),
    ]).then(
      ([runtime, permissions, shortcutSnapshot]) => {
        if (cancelled) return;
        setNativeRuntime(runtime);
        setNativePermissions(permissions);
        setNativeShortcutSnapshot(shortcutSnapshot);
        setAnnouncement(
          runtime.quickClipAvailable
            ? "Quick Clip settings loaded."
            : "",
        );

        if (
          runtime.shell === "tauri" &&
          runtime.nativeShortcutsAvailable
        ) {
          const loadedQuickClipBindings =
            shortcutSnapshot.bindings.map(shortcutBindingFromNative);
          setBindings((current) => [
            ...current.filter(
              (binding) => binding.actionId !== "quick-clip",
            ),
            ...loadedQuickClipBindings,
          ]);
          setQuickClipEnabled(
            shortcutSnapshot.bindings.some((binding) => binding.enabled),
          );
        }
      },
      () => {
        if (cancelled) return;
        setNativeBridgeFailed(true);
      },
    );

    return () => {
      cancelled = true;
    };
  }, []);

  const quickClipBindings = bindingsForAction(bindings, "quick-clip");
  const quickClipActive = quickClipEnabled && quickClipBindings.length > 0;
  const runtimePending = nativeRuntime === null && !nativeBridgeFailed;
  const nativeShellDetected = nativeRuntime?.shell === "tauri";
  const nativeQuickClipAvailable =
    nativeShellDetected && nativeRuntime.quickClipAvailable;
  const nativeShortcutsAvailable =
    nativeShellDetected && nativeRuntime.nativeShortcutsAvailable;
  const editingAction = editingTarget
    ? SHORTCUT_ACTIONS.find(
        (action) => action.id === editingTarget.actionId,
      ) ?? null
    : null;

  const beginEditing = (
    actionId: ShortcutActionId,
    binding: ShortcutBinding | null,
    trigger: HTMLButtonElement,
  ) => {
    setReturnFocus(trigger);
    setEditingTarget({ actionId, binding });
  };

  const saveBinding = (
    actionId: ShortcutActionId,
    gesture: ShortcutGesture,
    replacedBinding: ShortcutBinding | null,
  ) => {
    const nextBindings = replacedBinding
      ? bindings.map((binding) =>
          binding === replacedBinding ? { actionId, gesture } : binding,
        )
      : [...bindings, { actionId, gesture }];

    if (actionId === "quick-clip" && nativeShortcutsAvailable) {
      void persistQuickClipBindings(
        nextBindings,
        true,
        gesture.kind === "double-tap"
          ? `${replacedBinding ? "Updated" : "Added"} native Quick Clip double-tap.`
          : `${replacedBinding ? "Updated" : "Added"} Quick Clip key combination for this session.`,
      );
      return;
    }

    setBindings(nextBindings);
    if (actionId === "quick-clip") setQuickClipEnabled(true);
    const action = SHORTCUT_ACTIONS.find((item) => item.id === actionId);
    setAnnouncement(
      `${action?.label ?? "Shortcut"} ${replacedBinding ? "updated" : "added"}.`,
    );
  };

  const persistQuickClipBindings = async (
    nextBindings: ShortcutBinding[],
    enabled: boolean,
    successMessage: string,
  ) => {
    setNativeShortcutSaving(true);
    setNativeShortcutError(null);
    let configurationSaved = false;

    try {
      let snapshot = await configureNativeShortcuts(
        nativeQuickClipBindings(nextBindings, enabled),
      );
      configurationSaved = true;
      setBindings(nextBindings);
      setQuickClipEnabled(enabled);
      setNativeShortcutSnapshot(snapshot);

      if (snapshot.configuredBindings > 0) {
        let permissions = nativePermissions;
        if (
          snapshot.listenerState === "permission_required" ||
          permissions?.inputMonitoring !== "granted"
        ) {
          permissions = await requestNativePermission("input_monitoring");
          setNativePermissions(permissions);
        }

        if (permissions.inputMonitoring === "granted") {
          snapshot = await activateNativeShortcuts();
          setNativeShortcutSnapshot(snapshot);
        }
      }

      const activationDetail =
        snapshot.listenerState === "active"
          ? " Native Quick Clip double-tap listener active."
          : snapshot.listenerState === "external_conflict"
            ? " Native double-tap saved, but another shortcut owner is active."
            : snapshot.listenerState === "permission_required"
              ? " Native double-tap saved; Input Monitoring permission is still required."
              : "";
      setAnnouncement(`${successMessage}${activationDetail}`);
    } catch {
      const detail = configurationSaved
        ? "The shortcut was saved, but its native listener could not be activated."
        : "The Quick Clip shortcut could not be saved.";
      setNativeShortcutError(detail);
      setAnnouncement(detail);
    } finally {
      setNativeShortcutSaving(false);
    }
  };

  const setQuickClipEnabledState = (checked: boolean) => {
    if (!nativeShortcutsAvailable) return;

    void persistQuickClipBindings(
      bindings,
      checked,
      `Quick Clip ${checked ? "enabled" : "disabled"}.`,
    );
  };

  const tryQuickClip = async () => {
    if (!nativeQuickClipAvailable || !quickClipActive || quickClipRunning) {
      return;
    }

    setQuickClipRunning(true);
    setQuickClipResult(null);
    setAnnouncement("Quick Clip is opening the macOS region selector.");

    try {
      let permissions = nativePermissions;
      if (permissions?.screenCapture !== "granted") {
        permissions = await requestNativePermission("screen_capture");
        setNativePermissions(permissions);
      }

      if (permissions.screenCapture !== "granted") {
        const feedback = quickClipFeedback({
          status: "permission_not_granted",
          clipboardUpdated: false,
        });
        setQuickClipResult(feedback);
        setAnnouncement(feedback.detail);
        return;
      }

      const outcome = await runQuickClip(false);
      const feedback = quickClipFeedback(outcome);
      setQuickClipResult(feedback);
      setAnnouncement(feedback.detail);
    } catch {
      const feedback = {
        title: "Native bridge unavailable",
        detail:
          "Vyrra could not start Quick Clip. Close and reopen the desktop app before trying again.",
        tone: "warning" as const,
      };
      setQuickClipResult(feedback);
      setAnnouncement(feedback.detail);
    } finally {
      setQuickClipRunning(false);
    }
  };

  return (
    <div className="space-y-8">
      <PageHeader
        title="Shortcuts"
      />

      {runtimePending && (
        <InlineNotice tone="info" title="Checking Quick Clip">
          One moment.
        </InlineNotice>
      )}

      {!runtimePending && !nativeQuickClipAvailable && (
        <InlineNotice
          tone={nativeBridgeFailed ? "warning" : "info"}
          title={
            nativeBridgeFailed
              ? "Quick Clip unavailable"
              : "Quick Clip needs macOS"
          }
        >
          {nativeBridgeFailed
            ? "Restart Vyrra to reconnect."
            : "Open this screen in the Vyrra macOS app."}
        </InlineNotice>
      )}

      <section aria-labelledby="shortcut-list-heading" className="space-y-4">
        <h2 id="shortcut-list-heading" className="sr-only">
          Keyboard shortcuts
        </h2>
        <Card className="overflow-hidden">
          <div className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
            <div className="flex min-w-0 items-start gap-4">
              <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-accent-soft text-accent">
                <Scissors size={20} aria-hidden="true" />
              </span>
              <div className="min-w-0">
                <h3 className="text-sm font-semibold text-ink">Quick Clip</h3>
                <p className="mt-1 text-xs text-ink-soft">
                  Screenshot to clipboard
                </p>
              </div>
            </div>

            <div className="flex flex-wrap items-center justify-end gap-2">
              {nativeQuickClipAvailable ? (
                quickClipBindings.map((binding, index) => (
                  <ShortcutKeycap
                    key={`${formatShortcutGesture(binding.gesture)}-${index}`}
                    gesture={binding.gesture}
                  />
                ))
              ) : (
                <Badge tone="neutral">Unavailable</Badge>
              )}

              {nativeShortcutsAvailable && (
                <button
                  type="button"
                  aria-label="Edit Quick Clip shortcut"
                  onClick={(event) =>
                    beginEditing(
                      "quick-clip",
                      quickClipBindings[0] ?? null,
                      event.currentTarget,
                    )
                  }
                  className="grid size-9 shrink-0 place-items-center rounded-control text-ink-soft hover:bg-surface-strong hover:text-ink focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus"
                >
                  <Pencil size={15} aria-hidden="true" />
                </button>
              )}

              {nativeQuickClipAvailable && (
                <Button
                  variant="secondary"
                  disabled={!quickClipActive || quickClipRunning}
                  title={
                    quickClipActive
                      ? "Select a region and copy it to the system clipboard"
                      : "Enable Quick Clip before testing it"
                  }
                  onClick={tryQuickClip}
                  className="min-h-9 shrink-0 px-3"
                >
                  {quickClipRunning ? "Testing…" : "Test"}
                </Button>
              )}

              {nativeShortcutsAvailable && (
                <ShortcutSwitch
                  checked={quickClipActive}
                  disabled={
                    quickClipBindings.length === 0 || nativeShortcutSaving
                  }
                  onChange={setQuickClipEnabledState}
                />
              )}

              {nativeShortcutSaving && (
                <span className="text-[0.68rem] text-ink-faint">Saving…</span>
              )}
            </div>
          </div>
        </Card>

        {quickClipResult && (
          <InlineNotice
            tone={quickClipResult.tone}
            title={quickClipResult.title}
          >
            {quickClipResult.detail}
          </InlineNotice>
        )}

        {nativeShortcutError && (
          <InlineNotice tone="warning" title="Shortcut update failed">
            {nativeShortcutError}
          </InlineNotice>
        )}

        {nativeShortcutsAvailable &&
          nativeShortcutSnapshot?.listenerState === "permission_required" && (
            <InlineNotice
              tone="warning"
              title="Input Monitoring needed"
            >
              Allow Vyrra in System Settings, then try again.
            </InlineNotice>
          )}

        {nativeShortcutsAvailable &&
          nativeShortcutSnapshot?.externalConflict === "control_shot" && (
            <InlineNotice tone="warning" title="Shortcut conflict">
              Quit ControlShot or choose another key.
            </InlineNotice>
          )}
      </section>

      {announcement && (
        <p className="sr-only" aria-live="polite">
          {announcement}
        </p>
      )}

      {editingAction && (
        <ShortcutRecorder
          action={editingAction}
          bindings={bindings}
          excludedBinding={editingTarget?.binding ?? null}
          initialGesture={editingTarget?.binding?.gesture ?? null}
          returnFocus={returnFocus}
          onClose={() => setEditingTarget(null)}
          onSave={(gesture) =>
            saveBinding(
              editingAction.id,
              gesture,
              editingTarget?.binding ?? null,
            )
          }
        />
      )}
    </div>
  );
}
