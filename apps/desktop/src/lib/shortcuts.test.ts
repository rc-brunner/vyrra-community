import { describe, expect, it } from "vitest";

import {
  DEFAULT_QUICK_CLIP_GESTURE,
  DEFAULT_SHORTCUT_BINDINGS,
  PRINTABLE_DOUBLE_TAP_WARNING,
  SHORTCUT_ACTIONS,
  canonicalShortcutGestureIdentity,
  findExternalShortcutOverlap,
  findShortcutConflict,
  formatShortcutGesture,
  formatShortcutGestureSpoken,
  isPrintableDoubleTap,
  shortcutGestureWarning,
  shortcutKeyFromKeyboardEvent,
  type ShortcutBinding,
  type ShortcutDoubleTapGesture,
  type ShortcutGesture,
  type ShortcutKeyboardEvent,
} from "./shortcuts";

function keyboardEvent(
  code: string,
  key: string,
  location: number = KeyboardEvent.DOM_KEY_LOCATION_STANDARD,
): ShortcutKeyboardEvent {
  return { code, key, location };
}

function doubleTap(
  code: string,
  key: string,
  location: ShortcutDoubleTapGesture["key"]["location"] = "standard",
  kind: ShortcutDoubleTapGesture["key"]["kind"] = "printable",
): ShortcutDoubleTapGesture {
  return {
    kind: "double-tap",
    key: { code, key, kind, location },
    intervalMs: 350,
    maxPressMs: 250,
  };
}

describe("shortcut action manifest and defaults", () => {
  it("defines the renderer actions, including the five voice-workflow shortcuts", () => {
    expect(SHORTCUT_ACTIONS.map(({ id }) => id)).toEqual([
      "quick-clip",
      "open-capture",
      "toggle-dictation",
      "toggle-workspace",
      "hold-to-transcribe",
      "command-mode",
      "hands-free",
      "start-new-note",
      "paste-last-transcription",
    ]);

    for (const action of SHORTCUT_ACTIONS) {
      expect(action.label).not.toBe("");
      expect(action.description).not.toBe("");
    }
  });

  it("defaults Quick Clip to either Command key with bounded timing", () => {
    expect(DEFAULT_QUICK_CLIP_GESTURE).toEqual({
      kind: "double-tap",
      key: {
        code: "Meta",
        key: "Meta",
        kind: "modifier",
        location: "either",
      },
      intervalMs: 350,
      maxPressMs: 250,
    });
    expect(DEFAULT_SHORTCUT_BINDINGS).toEqual([
      {
        actionId: "quick-clip",
        gesture: DEFAULT_QUICK_CLIP_GESTURE,
      },
    ]);
  });
});

describe("keyboard event mapping", () => {
  it("keeps left and right modifier keys distinct", () => {
    expect(
      shortcutKeyFromKeyboardEvent(
        keyboardEvent(
          "MetaLeft",
          "Meta",
          KeyboardEvent.DOM_KEY_LOCATION_LEFT,
        ),
      ),
    ).toMatchObject({ code: "Meta", location: "left", kind: "modifier" });
    expect(
      shortcutKeyFromKeyboardEvent(
        keyboardEvent(
          "MetaRight",
          "Meta",
          KeyboardEvent.DOM_KEY_LOCATION_RIGHT,
        ),
      ),
    ).toMatchObject({ code: "Meta", location: "right", kind: "modifier" });
    expect(
      shortcutKeyFromKeyboardEvent(
        keyboardEvent("ControlLeft", "Control"),
      ),
    ).toMatchObject({ code: "Control", location: "left" });
    expect(
      shortcutKeyFromKeyboardEvent(
        keyboardEvent("ControlRight", "Control"),
      ),
    ).toMatchObject({ code: "Control", location: "right" });
  });

  it.each([
    ["ShiftLeft", "Shift", "Shift", "left"],
    ["ShiftRight", "Shift", "Shift", "right"],
    ["AltLeft", "Alt", "Alt", "left"],
    ["AltRight", "Alt", "Alt", "right"],
  ])("maps %s", (code, key, expectedCode, expectedLocation) => {
    expect(shortcutKeyFromKeyboardEvent(keyboardEvent(code, key))).toMatchObject(
      {
        code: expectedCode,
        location: expectedLocation,
        kind: "modifier",
      },
    );
  });

  it.each([
    ["KeyK", "k", "K", "printable"],
    ["Digit7", "7", "7", "printable"],
    ["Slash", "/", "/", "printable"],
    ["Numpad3", "3", "Numpad 3", "printable"],
    ["Space", " ", " ", "printable"],
    ["ArrowUp", "ArrowUp", "ArrowUp", "navigation"],
    ["ArrowLeft", "ArrowLeft", "ArrowLeft", "navigation"],
    ["Home", "Home", "Home", "navigation"],
    ["Backspace", "Backspace", "Backspace", "control"],
    ["F12", "F12", "F12", "function"],
    ["Enter", "Enter", "Enter", "control"],
  ])("maps supported key %s", (code, key, expectedKey, expectedKind) => {
    expect(shortcutKeyFromKeyboardEvent(keyboardEvent(code, key))).toMatchObject(
      {
        code,
        key: expectedKey,
        kind: expectedKind,
        location: "standard",
      },
    );
  });

  it("rejects unsupported keys deterministically", () => {
    expect(
      shortcutKeyFromKeyboardEvent(keyboardEvent("Unidentified", "Dead")),
    ).toBeNull();
  });

  it("keeps identified platform keys available as physical-key fallbacks", () => {
    expect(
      shortcutKeyFromKeyboardEvent(
        keyboardEvent("AudioVolumeUp", "AudioVolumeUp"),
      ),
    ).toEqual({
      code: "AudioVolumeUp",
      key: "AudioVolumeUp",
      kind: "control",
      location: "standard",
    });
  });
});

describe("canonical identity and conflicts", () => {
  it("canonicalizes chord modifier order and duplicates", () => {
    const key = shortcutKeyFromKeyboardEvent(keyboardEvent("KeyK", "k"));
    expect(key).not.toBeNull();
    if (!key) return;

    const first: ShortcutGesture = {
      kind: "chord",
      key,
      modifiers: ["meta", "shift", "meta"],
    };
    const second: ShortcutGesture = {
      kind: "chord",
      key,
      modifiers: ["shift", "meta"],
    };

    expect(canonicalShortcutGestureIdentity(first)).toBe(
      canonicalShortcutGestureIdentity(second),
    );
  });

  it("distinguishes left and right double taps", () => {
    const left = doubleTap("Meta", "Meta", "left", "modifier");
    const right = doubleTap("Meta", "Meta", "right", "modifier");

    expect(canonicalShortcutGestureIdentity(left)).not.toBe(
      canonicalShortcutGestureIdentity(right),
    );
    expect(
      findShortcutConflict(
        { actionId: "quick-clip", gesture: left },
        [{ actionId: "open-capture", gesture: right }],
      ),
    ).toBeNull();
  });

  it("finds an exact duplicate owned by another action", () => {
    const gesture = doubleTap("KeyK", "K");
    const existing: ShortcutBinding = {
      actionId: "open-capture",
      gesture,
    };

    expect(
      findShortcutConflict(
        { actionId: "quick-clip", gesture },
        [existing],
      ),
    ).toMatchObject({
      kind: "exact",
      existing,
      canonicalIdentity: "double-tap|keyk:standard",
    });
  });

  it("finds an exact duplicate inside the same action", () => {
    const gesture = doubleTap("KeyK", "K");
    const existing: ShortcutBinding = {
      actionId: "hold-to-transcribe",
      gesture,
    };

    expect(
      findShortcutConflict(
        { actionId: "hold-to-transcribe", gesture },
        [existing],
      ),
    ).toMatchObject({
      kind: "exact",
      existing,
    });
  });

  it("excludes only the binding currently being edited", () => {
    const gesture = doubleTap("KeyK", "K");
    const currentBinding: ShortcutBinding = {
      actionId: "hold-to-transcribe",
      gesture,
    };
    const duplicateBinding: ShortcutBinding = {
      actionId: "hold-to-transcribe",
      gesture,
    };

    expect(
      findShortcutConflict(
        { actionId: "hold-to-transcribe", gesture },
        [currentBinding],
        currentBinding,
      ),
    ).toBeNull();
    expect(
      findShortcutConflict(
        { actionId: "hold-to-transcribe", gesture },
        [currentBinding, duplicateBinding],
        currentBinding,
      ),
    ).toMatchObject({
      kind: "exact",
      existing: duplicateBinding,
    });
  });

  it("treats an either-side modifier as overlapping each side", () => {
    const existing: ShortcutBinding = {
      actionId: "quick-clip",
      gesture: DEFAULT_QUICK_CLIP_GESTURE,
    };

    expect(
      findShortcutConflict(
        {
          actionId: "open-capture",
          gesture: doubleTap("Meta", "Meta", "left", "modifier"),
        },
        [existing],
      ),
    ).toMatchObject({ kind: "overlap", existing });
    expect(
      findShortcutConflict(
        {
          actionId: "toggle-workspace",
          gesture: doubleTap("Meta", "Meta", "right", "modifier"),
        },
        [existing],
      ),
    ).toMatchObject({ kind: "overlap", existing });
  });
});

describe("gesture formatting and warnings", () => {
  it("formats either-side and located modifier double taps visibly and aloud", () => {
    expect(formatShortcutGesture(DEFAULT_QUICK_CLIP_GESTURE)).toBe(
      "Double-tap ⌘ (either side)",
    );
    expect(formatShortcutGestureSpoken(DEFAULT_QUICK_CLIP_GESTURE)).toBe(
      "Double-tap Command on either side",
    );

    const leftControl = doubleTap(
      "Control",
      "Control",
      "left",
      "modifier",
    );
    expect(formatShortcutGesture(leftControl)).toBe("Double-tap Left ⌃");
    expect(formatShortcutGestureSpoken(leftControl)).toBe(
      "Double-tap left Control",
    );
  });

  it("formats chord modifiers in one canonical order", () => {
    const gesture: ShortcutGesture = {
      kind: "chord",
      key: {
        code: "ArrowUp",
        key: "ArrowUp",
        kind: "navigation",
        location: "standard",
      },
      modifiers: ["meta", "control", "shift"],
    };

    expect(formatShortcutGesture(gesture)).toBe("⌃⇧⌘↑");
    expect(formatShortcutGestureSpoken(gesture)).toBe(
      "Control plus Shift plus Command plus Up Arrow",
    );
  });

  it("recognizes and explains printable double taps", () => {
    const letter = doubleTap("KeyA", "A");
    const space = doubleTap("Space", " ");

    expect(isPrintableDoubleTap(letter)).toBe(true);
    expect(isPrintableDoubleTap(space)).toBe(true);
    expect(shortcutGestureWarning(letter)).toBe(
      PRINTABLE_DOUBLE_TAP_WARNING,
    );
    expect(shortcutGestureWarning(DEFAULT_QUICK_CLIP_GESTURE)).toBeNull();
  });

  it("warns when a non-printable double tap passes through", () => {
    const enter = doubleTap(
      "Enter",
      "Enter",
      "standard",
      "control",
    );

    expect(shortcutGestureWarning(enter)).toBe(
      "Both Enter presses will still reach the focused app and may activate it.",
    );
  });
});

describe("known external overlaps", () => {
  it.each([
    doubleTap("Meta", "Meta", "left", "modifier"),
    doubleTap("Meta", "Meta", "right", "modifier"),
    DEFAULT_QUICK_CLIP_GESTURE,
    doubleTap("Control", "Control", "left", "modifier"),
    doubleTap("Control", "Control", "right", "modifier"),
    doubleTap("Control", "Control", "either", "modifier"),
  ])("reports possible ControlShot overlap for $key.code $key.location", (gesture) => {
    expect(findExternalShortcutOverlap(gesture)).toMatchObject({
      id: "controlshot",
      appName: "ControlShot",
      bundleId: "com.brandonrunner.controlshot",
    });
  });

  it("reports the audited Hammerspoon overlap but ignores chords", () => {
    expect(
      findExternalShortcutOverlap(
        doubleTap("Shift", "Shift", "either", "modifier"),
      ),
    ).toMatchObject({
      id: "hammerspoon-vowen",
      appName: "Hammerspoon",
    });
    expect(
      findExternalShortcutOverlap({
        kind: "chord",
        key: {
          code: "KeyK",
          key: "K",
          kind: "printable",
          location: "standard",
        },
        modifiers: ["meta"],
      }),
    ).toBeNull();
  });
});
