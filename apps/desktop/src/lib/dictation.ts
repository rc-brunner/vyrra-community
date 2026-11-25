import { useSyncExternalStore } from "react";
import { invoke } from "@tauri-apps/api/core";
import { isNativeDesktop } from "./native";

export type Phase =
  | "idle"
  | "starting"
  | "listening"
  | "paused"
  | "transcribing";
export type DictationAction =
  | "start"
  | "check"
  | "pause"
  | "resume"
  | "finish"
  | "cancel"
  | "clear";
export interface DictationSnapshot {
  phase: Phase;
  model: "missing" | "checking" | "installing" | "ready";
  elapsedMs: number;
  level: number;
  text: string;
  revision: number;
  error: string | null;
  delivery: boolean | null;
}
export type Sound = "studio" | "porcelain" | "classic" | "soft" | "felt" | "off";
export interface SpeechOptions {
  sound: Sound;
  panelSounds: boolean;
  language: string | null;
  translateToEnglish: boolean;
  vocabulary: string[];
  snippets: { phrase: string; text: string }[];
}
export interface Entry {
  id: number;
  createdAt: number;
  text: string;
  pinned: boolean;
  archived: boolean;
}

const initial: DictationSnapshot = {
  phase: "idle",
  model: "checking",
  elapsedMs: 0,
  level: 0,
  text: "",
  revision: 0,
  error: null,
  delivery: null,
};
let current = initial;
let pending: Promise<void> | undefined;
let timer: ReturnType<typeof setTimeout> | undefined;
const listeners = new Set<() => void>();

export function message(error: unknown): string {
  return typeof error === "string"
    ? error
    : error instanceof Error
      ? error.message
      : "The desktop service could not complete this action.";
}

function refresh(): Promise<void> {
  if (pending) return pending;
  const since = current.revision;
  pending = invoke<DictationSnapshot>("dictation_status", {since})
    .then((data) => {
      current = data.revision === since ? {...data, text:current.text} : data;
    })
    .catch((error: unknown) => {
      current = { ...current, error: message(error) };
    })
    .finally(() => {
      pending = undefined;
      for (const notify of listeners) notify();
    });
  return pending;
}

async function poll() {
  await refresh();
  if (listeners.size) {
    const active = current.phase !== "idle" || current.model === "installing";
    timer = setTimeout(
      () => {
        void poll();
      },
      active ? 125 : 750,
    );
  }
}

function subscribe(notify: () => void) {
  if (!isNativeDesktop()) return () => {};
  listeners.add(notify);
  if (listeners.size === 1 && !pending) void poll();
  return () => {
    listeners.delete(notify);
    if (!listeners.size) clearTimeout(timer);
  };
}

export function useDictation() {
  return useSyncExternalStore(subscribe, () => current);
}

async function change(command: string, args?: Record<string, unknown>) {
  try {
    await invoke(command, args);
  } finally {
    await refresh();
  }
}
export const dictate = (action: DictationAction) =>
  change("dictation_action", { action });
export const installModel = (offline: boolean) =>
  change("dictation_install", { offline });
export const importAudio = () => change("dictation_import");
export const speechOptions = () => invoke<SpeechOptions>("dictation_options");
export const updateOptions = (options: SpeechOptions) =>
  invoke<void>("dictation_set_options", { options });
export const readEntries = () => invoke<Entry[]>("dictation_entries");
export const saveEntry = (text: string, id: number | null = null) =>
  invoke<number>("dictation_save", { id, text });
export const deleteEntry = (id: number) =>
  invoke<void>("dictation_delete", { id });
export const markEntry = (
  id: number,
  changes: { pinned?: boolean; archived?: boolean },
) =>
  invoke<void>("dictation_mark", {
    id,
    pinned: changes.pinned ?? null,
    archived: changes.archived ?? null,
  });

export const panelSound = (closing: boolean) => { if (isNativeDesktop()) void invoke("panel_sound",{closing}).catch(()=>{}); };
