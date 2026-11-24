export type ShortcutActionId =
  | "quick-clip"
  | "open-capture"
  | "toggle-dictation"
  | "toggle-workspace"
  | "hold-to-transcribe"
  | "command-mode"
  | "hands-free"
  | "start-new-note"
  | "paste-last-transcription";

export interface ShortcutActionDefinition {
  readonly id: ShortcutActionId;
  readonly label: string;
  readonly description: string;
}

export const SHORTCUT_ACTIONS = [
  {
    id: "quick-clip",
    label: "Quick Clip",
    description: "Select a screen region and copy it to the clipboard.",
  },
  {
    id: "open-capture",
    label: "Open Capture",
    description: "Open capture preflight without starting a recording.",
  },
  {
    id: "toggle-dictation",
    label: "Toggle dictation",
    description: "Start or stop dictation after required desktop checks pass.",
  },
  {
    id: "toggle-workspace",
    label: "Show or hide workspace",
    description: "Bring the workspace forward or return to the previous app.",
  },
  {
    id: "hold-to-transcribe",
    label: "Hold to transcribe",
    description:
      "Trigger press-and-hold transcription; release to finish in the future desktop adapter.",
  },
  {
    id: "command-mode",
    label: "Command Mode",
    description:
      "Trigger voice-command processing for the current text context.",
  },
  {
    id: "hands-free",
    label: "Hands-free mode",
    description: "Start or stop dictation without holding the shortcut.",
  },
  {
    id: "start-new-note",
    label: "Start new note",
    description: "Open the meeting-note capture preflight.",
  },
  {
    id: "paste-last-transcription",
    label: "Paste last transcription",
    description:
      "Request insertion of the most recent transcription in the focused app.",
  },
] as const satisfies readonly ShortcutActionDefinition[];

export type ShortcutKeyLocation = "standard" | "left" | "right" | "either";
export type ShortcutKeyKind =
  | "modifier"
  | "printable"
  | "navigation"
  | "function"
  | "control";

export interface ShortcutKey {
  /**
   * A stable physical-key identifier. Modifier variants use their shared
   * family (`Meta`, `Control`, `Shift`, or `Alt`) plus `location`.
   */
  readonly code: string;
  readonly key: string;
  readonly kind: ShortcutKeyKind;
  readonly location: ShortcutKeyLocation;
}

export type ShortcutModifier = "control" | "alt" | "shift" | "meta";

export interface ShortcutChordGesture {
  readonly kind: "chord";
  readonly key: ShortcutKey;
  readonly modifiers: readonly ShortcutModifier[];
}

export interface ShortcutDoubleTapGesture {
  readonly kind: "double-tap";
  readonly key: ShortcutKey;
  readonly intervalMs: number;
  readonly maxPressMs: number;
}

export type ShortcutGesture =
  | ShortcutChordGesture
  | ShortcutDoubleTapGesture;

export interface ShortcutBinding {
  readonly actionId: ShortcutActionId;
  readonly gesture: ShortcutGesture;
}

export interface ShortcutConflict {
  readonly kind: "exact" | "overlap";
  readonly candidate: ShortcutBinding;
  readonly existing: ShortcutBinding;
  readonly canonicalIdentity: string;
}

export interface ExternalShortcutOverlap {
  readonly id: "controlshot" | "hammerspoon-vowen";
  readonly appName: "ControlShot" | "Hammerspoon";
  readonly bundleId:
    | "com.brandonrunner.controlshot"
    | "org.hammerspoon.Hammerspoon";
  readonly message: string;
}

export const DEFAULT_QUICK_CLIP_GESTURE: ShortcutDoubleTapGesture = {
  kind: "double-tap",
  key: {
    code: "Meta",
    key: "Meta",
    kind: "modifier",
    location: "either",
  },
  intervalMs: 350,
  maxPressMs: 250,
};

export const DEFAULT_SHORTCUT_BINDINGS = [
  {
    actionId: "quick-clip",
    gesture: DEFAULT_QUICK_CLIP_GESTURE,
  },
] as const satisfies readonly ShortcutBinding[];

export const PRINTABLE_DOUBLE_TAP_WARNING =
  "Both taps will still reach the focused app and may type there.";

const MODIFIER_ORDER = [
  "control",
  "alt",
  "shift",
  "meta",
] as const satisfies readonly ShortcutModifier[];

const MODIFIER_VISIBLE_NAMES: Record<ShortcutModifier, string> = {
  control: "⌃",
  alt: "⌥",
  shift: "⇧",
  meta: "⌘",
};

const MODIFIER_SPOKEN_NAMES: Record<ShortcutModifier, string> = {
  control: "Control",
  alt: "Option",
  shift: "Shift",
  meta: "Command",
};

const MODIFIER_KEYS: Readonly<
  Record<
    string,
    {
      readonly code: "Meta" | "Control" | "Shift" | "Alt";
      readonly key: "Meta" | "Control" | "Shift" | "Alt";
      readonly location: "left" | "right";
    }
  >
> = {
  MetaLeft: { code: "Meta", key: "Meta", location: "left" },
  MetaRight: { code: "Meta", key: "Meta", location: "right" },
  ControlLeft: { code: "Control", key: "Control", location: "left" },
  ControlRight: { code: "Control", key: "Control", location: "right" },
  ShiftLeft: { code: "Shift", key: "Shift", location: "left" },
  ShiftRight: { code: "Shift", key: "Shift", location: "right" },
  AltLeft: { code: "Alt", key: "Alt", location: "left" },
  AltRight: { code: "Alt", key: "Alt", location: "right" },
};

const NAVIGATION_KEYS: Readonly<Record<string, string>> = {
  ArrowUp: "ArrowUp",
  ArrowDown: "ArrowDown",
  ArrowLeft: "ArrowLeft",
  ArrowRight: "ArrowRight",
  Home: "Home",
  End: "End",
  PageUp: "Page Up",
  PageDown: "Page Down",
};

const CONTROL_KEYS: Readonly<Record<string, string>> = {
  Enter: "Enter",
  NumpadEnter: "Numpad Enter",
  Backspace: "Backspace",
  Delete: "Delete",
  Insert: "Insert",
  CapsLock: "Caps Lock",
  ContextMenu: "Context Menu",
};

const PUNCTUATION_KEYS: Readonly<Record<string, string>> = {
  Backquote: "`",
  Minus: "-",
  Equal: "=",
  BracketLeft: "[",
  BracketRight: "]",
  Backslash: "\\",
  Semicolon: ";",
  Quote: "'",
  Comma: ",",
  Period: ".",
  Slash: "/",
  NumpadDecimal: ".",
  NumpadAdd: "+",
  NumpadSubtract: "-",
  NumpadMultiply: "*",
  NumpadDivide: "/",
};

export type ShortcutKeyboardEvent = Pick<
  KeyboardEvent,
  "code" | "key" | "location"
>;

/**
 * Converts the supported browser KeyboardEvent subset into a stable
 * renderer-only key description. Unsupported keys return null.
 */
export function shortcutKeyFromKeyboardEvent(
  event: ShortcutKeyboardEvent,
): ShortcutKey | null {
  const modifier = MODIFIER_KEYS[event.code];
  if (modifier) {
    return {
      ...modifier,
      kind: "modifier",
    };
  }

  const letter = /^Key([A-Z])$/.exec(event.code)?.[1];
  if (letter) {
    return {
      code: event.code,
      key: letter,
      kind: "printable",
      location: "standard",
    };
  }

  const digit = /^Digit([0-9])$/.exec(event.code)?.[1];
  if (digit) {
    return {
      code: event.code,
      key: digit,
      kind: "printable",
      location: "standard",
    };
  }

  const numpadDigit = /^Numpad([0-9])$/.exec(event.code)?.[1];
  if (numpadDigit) {
    return {
      code: event.code,
      key: `Numpad ${numpadDigit}`,
      kind: "printable",
      location: "standard",
    };
  }

  const punctuationKey = PUNCTUATION_KEYS[event.code];
  if (punctuationKey) {
    return {
      code: event.code,
      key: punctuationKey,
      kind: "printable",
      location: "standard",
    };
  }

  if (event.code === "Space") {
    return {
      code: "Space",
      key: " ",
      kind: "printable",
      location: "standard",
    };
  }

  const navigationKey = NAVIGATION_KEYS[event.code];
  if (navigationKey) {
    return {
      code: event.code,
      key: navigationKey,
      kind: "navigation",
      location: "standard",
    };
  }

  const functionKey = /^F([1-9]|1[0-9]|2[0-4])$/.exec(event.code)?.[0];
  if (functionKey) {
    return {
      code: functionKey,
      key: functionKey,
      kind: "function",
      location: "standard",
    };
  }

  const controlKey = CONTROL_KEYS[event.code];
  if (controlKey) {
    return {
      code: event.code,
      key: controlKey,
      kind: "control",
      location: "standard",
    };
  }

  if (
    !event.code ||
    event.code === "Unidentified" ||
    !event.key ||
    event.key === "Unidentified" ||
    event.key === "Dead" ||
    event.key === "Process"
  ) {
    return null;
  }

  return {
    code: event.code,
    key: event.key,
    kind: event.key.length === 1 ? "printable" : "control",
    location: "standard",
  };
}

function canonicalModifiers(
  modifiers: readonly ShortcutModifier[],
): readonly ShortcutModifier[] {
  const present = new Set(modifiers);
  return MODIFIER_ORDER.filter((modifier) => present.has(modifier));
}

function canonicalKeyIdentity(key: ShortcutKey): string {
  return `${key.code.toLowerCase()}:${key.location}`;
}

/**
 * Returns the action-independent identity of a gesture. Timing values tune a
 * double tap but do not make two bindings on the same key distinguishable.
 */
export function canonicalShortcutGestureIdentity(
  gesture: ShortcutGesture,
): string {
  const keyIdentity = canonicalKeyIdentity(gesture.key);

  if (gesture.kind === "double-tap") {
    return `double-tap|${keyIdentity}`;
  }

  return `chord|${canonicalModifiers(gesture.modifiers).join("+")}|${keyIdentity}`;
}

function keyScopesOverlap(left: ShortcutKey, right: ShortcutKey): boolean {
  if (left.code !== right.code) return false;
  if (left.location === right.location) return true;

  const canMatchEitherSide =
    left.kind === "modifier" && right.kind === "modifier";

  return (
    canMatchEitherSide &&
    (left.location === "either" || right.location === "either")
  );
}

function gesturesOverlap(
  left: ShortcutGesture,
  right: ShortcutGesture,
): boolean {
  if (left.kind !== right.kind) return false;
  if (!keyScopesOverlap(left.key, right.key)) return false;

  if (left.kind === "double-tap" && right.kind === "double-tap") {
    return true;
  }

  if (left.kind === "chord" && right.kind === "chord") {
    return (
      canonicalModifiers(left.modifiers).join("+") ===
      canonicalModifiers(right.modifiers).join("+")
    );
  }

  return false;
}

/**
 * Finds the first other binding that would receive the same gesture. The
 * binding currently being edited can be excluded by object identity. An
 * either-side modifier overlaps its left- and right-side forms.
 */
export function findShortcutConflict(
  candidate: ShortcutBinding,
  bindings: readonly ShortcutBinding[],
  excludedBinding: ShortcutBinding | null = null,
): ShortcutConflict | null {
  const candidateIdentity = canonicalShortcutGestureIdentity(
    candidate.gesture,
  );

  for (const existing of bindings) {
    if (existing === excludedBinding) continue;

    const existingIdentity = canonicalShortcutGestureIdentity(
      existing.gesture,
    );
    if (candidateIdentity === existingIdentity) {
      return {
        kind: "exact",
        candidate,
        existing,
        canonicalIdentity: candidateIdentity,
      };
    }

    if (gesturesOverlap(candidate.gesture, existing.gesture)) {
      return {
        kind: "overlap",
        candidate,
        existing,
        canonicalIdentity: candidateIdentity,
      };
    }
  }

  return null;
}

function modifierFromKey(key: ShortcutKey): ShortcutModifier | null {
  switch (key.code) {
    case "Meta":
      return "meta";
    case "Control":
      return "control";
    case "Shift":
      return "shift";
    case "Alt":
      return "alt";
    default:
      return null;
  }
}

function visibleKeyName(key: ShortcutKey): string {
  const modifier = modifierFromKey(key);
  if (modifier) return MODIFIER_VISIBLE_NAMES[modifier];

  switch (key.code) {
    case "ArrowUp":
      return "↑";
    case "ArrowDown":
      return "↓";
    case "ArrowLeft":
      return "←";
    case "ArrowRight":
      return "→";
    case "Space":
      return "Space";
    case "Enter":
      return "Enter";
    default:
      return key.key;
  }
}

function spokenKeyName(key: ShortcutKey): string {
  const modifier = modifierFromKey(key);
  if (modifier) return MODIFIER_SPOKEN_NAMES[modifier];

  switch (key.code) {
    case "ArrowUp":
      return "Up Arrow";
    case "ArrowDown":
      return "Down Arrow";
    case "ArrowLeft":
      return "Left Arrow";
    case "ArrowRight":
      return "Right Arrow";
    case "Space":
      return "Space";
    case "Enter":
      return "Enter";
    default:
      return key.key;
  }
}

function visibleLocatedKeyName(key: ShortcutKey): string {
  const name = visibleKeyName(key);
  if (key.location === "standard") return name;
  if (key.location === "either") return `${name} (either side)`;
  return `${key.location === "left" ? "Left" : "Right"} ${name}`;
}

function spokenLocatedKeyName(key: ShortcutKey): string {
  const name = spokenKeyName(key);
  if (key.location === "standard") return name;
  if (key.location === "either") return `${name} on either side`;
  return `${key.location} ${name}`;
}

export function formatShortcutGesture(gesture: ShortcutGesture): string {
  if (gesture.kind === "double-tap") {
    return `Double-tap ${visibleLocatedKeyName(gesture.key)}`;
  }

  const modifiers = canonicalModifiers(gesture.modifiers)
    .map((modifier) => MODIFIER_VISIBLE_NAMES[modifier])
    .join("");
  return `${modifiers}${visibleLocatedKeyName(gesture.key)}`;
}

export function formatShortcutGestureSpoken(
  gesture: ShortcutGesture,
): string {
  if (gesture.kind === "double-tap") {
    return `Double-tap ${spokenLocatedKeyName(gesture.key)}`;
  }

  return [
    ...canonicalModifiers(gesture.modifiers).map(
      (modifier) => MODIFIER_SPOKEN_NAMES[modifier],
    ),
    spokenLocatedKeyName(gesture.key),
  ].join(" plus ");
}

export function isPrintableDoubleTap(
  gesture: ShortcutGesture,
): boolean {
  return gesture.kind === "double-tap" && gesture.key.kind === "printable";
}

export function shortcutGestureWarning(
  gesture: ShortcutGesture,
): string | null {
  if (gesture.kind !== "double-tap" || gesture.key.kind === "modifier") {
    return null;
  }

  return isPrintableDoubleTap(gesture)
    ? PRINTABLE_DOUBLE_TAP_WARNING
    : `Both ${spokenKeyName(gesture.key)} presses will still reach the focused app and may activate it.`;
}

/**
 * Reports the known possible overlap with the separate ControlShot utility.
 * It deliberately says "may": this pure renderer helper does not inspect
 * whether that process is currently installed, running, or enabled.
 */
export function findExternalShortcutOverlap(
  gesture: ShortcutGesture,
): ExternalShortcutOverlap | null {
  const isControlShotGesture =
    gesture.kind === "double-tap" &&
    gesture.key.kind === "modifier" &&
    (gesture.key.code === "Meta" || gesture.key.code === "Control") &&
    (gesture.key.location === "left" ||
      gesture.key.location === "right" ||
      gesture.key.location === "either");

  if (isControlShotGesture) {
    return {
      id: "controlshot",
      appName: "ControlShot",
      bundleId: "com.brandonrunner.controlshot",
      message:
        "A development-machine audit observed ControlShot using double-Command or double-Control.",
    };
  }

  const isHammerspoonVowenGesture =
    gesture.kind === "double-tap" &&
    gesture.key.kind === "modifier" &&
    gesture.key.code === "Shift" &&
    (gesture.key.location === "left" ||
      gesture.key.location === "right" ||
      gesture.key.location === "either");

  return isHammerspoonVowenGesture
    ? {
        id: "hammerspoon-vowen",
        appName: "Hammerspoon",
        bundleId: "org.hammerspoon.Hammerspoon",
        message:
          "A development-machine audit observed a Hammerspoon double-Shift rule for Vowen.",
      }
    : null;
}
