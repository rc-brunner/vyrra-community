import { WritingTools } from "../components/WritingTools";
import { useEffect, useRef, useState } from "react";
import {
  Bookmark,
  Box,
  Download,
  LoaderCircle,
  ClipboardCopy,
  Ellipsis,
  FileAudio2,
  Mic,
  Pause,
  Play,
  Square,
  X,
} from "lucide-react";

import { QuietIcon } from "../components/QuietIcon";
import { RecorderPill } from "../components/RecorderPill";
import { Button, Card, PageHeader, ShortcutHint } from "../components/ui";
import {
  dictate,
  importAudio,
  installModel,
  message,
  saveEntry,
  useDictation,
} from "../lib/dictation";
import { speechModels } from "../lib/models";
import { isNativeDesktop } from "../lib/native";
import { readWaveformSensitivity, readWaveformVariant } from "../lib/waveform";

function elapsed(ms: number) {
  const seconds = Math.floor(ms / 1000);
  return [Math.floor(seconds / 60), seconds % 60]
    .map((v) => String(v).padStart(2, "0"))
    .join(":");
}

function Transcript({ text }: { text: string }) {
  const [draft, setDraft] = useState(text);
  const [saved, setSaved] = useState<number | null>(null);
  const [notice, setNotice] = useState("");
  const [saving, setSaving] = useState(false);
  return (
    <Card className="space-y-4 p-5 sm:p-7">
      <label
        className="block text-sm font-semibold text-ink"
        htmlFor="dictation-result"
      >
        Transcript
      </label>
      <textarea
        id="dictation-result"
        rows={4}
        value={draft}
        onChange={(e) => {
          setDraft(e.target.value);
          setNotice("");
        }}
        className="w-full resize-y rounded-control border border-line bg-canvas-subtle p-3 text-ink"
      />
      <div className="flex flex-wrap items-center gap-2">
        <WritingTools source={draft} apply={setDraft} />
        <QuietIcon
          icon={ClipboardCopy}
          label="Copy"
          disabled={!draft.trim()}
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(draft);
              setNotice("Copied.");
            } catch {
              setNotice(
                "Select the transcript and copy it with your keyboard.",
              );
            }
          }}
        />
        <QuietIcon
          icon={Bookmark}
          label="Save to Library"
          aria-pressed={saved !== null}
          disabled={saving || !draft.trim()}
          onClick={async () => {
            setSaving(true);
            try {
              setSaved(await saveEntry(draft, saved));
              setNotice("Saved on this device.");
            } catch (err) {
              setNotice(message(err));
            } finally {
              setSaving(false);
            }
          }}
        />
        <QuietIcon
          icon={X}
          label="Clear transcript"
          onClick={() => {
            void dictate("clear").catch((err) => setNotice(message(err)));
          }}
        />
      </div>
      {notice && (
        <p role="status" className="text-sm text-ink-soft">
          {notice}
        </p>
      )}
    </Card>
  );
}

export function CapturePage() {
  const state = useDictation();
  const native = isNativeDesktop();
  const [error, setError] = useState("");
  const [choosing, setChoosing] = useState(false);
  const [optionsOpen, setOptionsOpen] = useState(false);
  const primary = useRef<HTMLButtonElement>(null);
  const mac = /Mac|iPhone|iPad/.test(navigator.platform);
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (
        event.key !== "Enter" ||
        event.repeat ||
        event.isComposing ||
        event.altKey ||
        event.shiftKey ||
        event.metaKey !== mac ||
        event.ctrlKey === mac ||
        !primary.current ||
        primary.current.disabled ||
        (event.target instanceof Element &&
          event.target.closest(
            "input, textarea, select, [contenteditable=true], [role=dialog], [role=listbox]",
          ))
      )
        return;
      event.preventDefault();
      primary.current.click();
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [mac]);
  const listening = state.phase === "listening";
  const paused = state.phase === "paused";
  const ready = native && state.model === "ready";
  const busy = state.phase !== "idle";
  const model = speechModels.find((m) => m.id === state.activeModel);
  const recording = listening || paused;
  const settingUp = state.model === "installing" || state.model === "checking";
  const label = {
    idle: native && !ready ? "Set up" : "Ready",
    starting: "Starting",
    listening: "Listening",
    paused: "Paused",
    transcribing: "Transcribing",
  }[state.phase];

  async function run(action: () => Promise<void>, dialog = false) {
    setError("");
    if (dialog) setChoosing(true);
    try {
      await action();
    } catch (err) {
      setError(message(err));
    } finally {
      if (dialog) setChoosing(false);
    }
  }

  return (
    <div className="space-y-9">
      <PageHeader title="Speak naturally." />
      <section aria-label="Dictation" className="mx-auto max-w-4xl space-y-4">
        <Card className="space-y-4 p-5 sm:p-7">
          <RecorderPill
            active={listening}
            paused={paused}
            label={label}
            elapsed={elapsed(state.elapsedMs)}
            level={state.level}
            variant={readWaveformVariant()}
            sensitivity={readWaveformSensitivity()}
            action={
              <div className="recorder-actions flex items-center gap-1">
                {(!busy || recording) && (
                  <button
                    ref={primary}
                    type="button"
                    className="vyrra-button recorder-primary"
                    disabled={!ready || choosing}
                    aria-label={
                      recording ? "Finish dictation" : "Start dictation"
                    }
                    aria-keyshortcuts={mac ? "Meta+Enter" : "Control+Enter"}
                    onClick={() =>
                      void run(() => dictate(recording ? "finish" : "start"))
                    }
                  >
                    {recording ? (
                      <Square
                        size={13}
                        fill="currentColor"
                        aria-hidden="true"
                      />
                    ) : (
                      <Mic size={15} aria-hidden="true" />
                    )}
                    {recording ? "Finish" : "Dictate"}
                    <ShortcutHint>{mac ? "⌘ ↵" : "Ctrl ↵"}</ShortcutHint>
                  </button>
                )}
                {recording && (
                  <QuietIcon
                    label={paused ? "Resume dictation" : "Pause dictation"}
                    icon={paused ? Play : Pause}
                    onClick={() =>
                      void run(() => dictate(paused ? "resume" : "pause"))
                    }
                  />
                )}
                {busy && (
                  <QuietIcon
                    label="Cancel dictation"
                    icon={X}
                    onClick={() => void run(() => dictate("cancel"))}
                  />
                )}
              </div>
            }
          />
          {!native ? (
            <p className="text-sm text-ink-soft">
              Open Vyrra Desktop to use your microphone or transcribe a file.
            </p>
          ) : state.model !== "ready" ? (
            <div className="space-y-3">
              <p role="status" className="text-sm text-ink-soft">
                {state.model === "missing"
                  ? "Install Whisper base once to dictate offline. The model download is 148 MB."
                  : state.model === "checking"
                    ? "Checking the local speech model…"
                    : "Installing the speech model…"}
              </p>
              <div className="flex flex-wrap items-center gap-2">
                <Button
                  disabled={choosing || settingUp}
                  aria-busy={settingUp}
                  className={settingUp ? "vyrra-busy" : ""}
                  onClick={() => void run(() => installModel(false), true)}
                >
                  {settingUp ? (
                    <LoaderCircle size={14} />
                  ) : (
                    <Download size={14} />
                  )}
                  Download speech model
                </Button>
                <Button
                  variant="secondary"
                  disabled={choosing || settingUp}
                  onClick={() => void run(() => installModel(true), true)}
                >
                  Choose local model
                </Button>
                <a className="model-route" href="#/models">
                  <Box size={14} />
                  Browse models
                </a>
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap items-center justify-between gap-2">
              <a className="model-route" href="#/models">
                <Box size={14} />
                {model
                  ? `Whisper ${model.name}${model.languages === 1 ? " · English" : ""}`
                  : "Speech models"}
              </a>
              <QuietIcon
                icon={Ellipsis}
                label="More audio options"
                aria-expanded={optionsOpen}
                aria-controls="audio-options"
                disabled={busy || choosing}
                onClick={() => setOptionsOpen(!optionsOpen)}
              />
              <div
                id="audio-options"
                hidden={!optionsOpen}
                className="w-full border-t border-line pt-2"
              >
                <Button
                  variant="quiet"
                  disabled={busy || choosing}
                  onClick={() => {
                    setOptionsOpen(false);
                    void run(importAudio, true);
                  }}
                >
                  <FileAudio2 size={16} /> Transcribe WAV
                </Button>
                <Button
                  variant="quiet"
                  disabled={busy || choosing}
                  onClick={() => {
                    setOptionsOpen(false);
                    void run(() => dictate("check"));
                  }}
                >
                  <Mic size={16} /> Test mic for 5 seconds
                </Button>
              </div>
            </div>
          )}
          {(error || state.error) && (
            <p role="alert" className="text-sm text-danger">
              {error || state.error}
            </p>
          )}
          {state.delivery !== null && (
            <p role="status" className="text-xs text-ink-soft">
              {state.delivery
                ? "Inserted in the original text field."
                : mac
                  ? "Your transcript is ready to copy below. For direct insertion, allow Vyrra in Accessibility settings and keep the text field focused."
                  : "Your transcript is ready to copy below."}
            </p>
          )}
        </Card>
        {state.text && <Transcript key={state.revision} text={state.text} />}
      </section>
    </div>
  );
}
