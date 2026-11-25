import { useState } from "react";
import { Download, FolderOpen, LoaderCircle, Sparkles, X } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { Button } from "./ui";
import { QuietIcon } from "./QuietIcon";
import { message, panelSound } from "../lib/dictation";

type WritingTask = "rewrite" | "draft" | "meetingNotes" | "ask";
export function WritingTools({
  source,
  apply,
  initial = "rewrite",
}: {
  source: string;
  apply?: (text: string) => void;
  initial?: WritingTask;
}) {
  const [open, setOpen] = useState(false),
    [ready, setReady] = useState<boolean>(),
    [busy, setBusy] = useState(false),
    [installing, setInstalling] = useState<"download" | "import" | null>(null),
    [task, setTask] = useState(initial),
    [instruction, setInstruction] = useState(""),
    [answer, setAnswer] = useState(""),
    [error, setError] = useState("");
  async function status() {
    const s = await invoke<{ installed: boolean }>("writing_status");
    setReady(s.installed);
  }
  async function run(action: () => Promise<unknown>) {
    setError("");
    setBusy(true);
    try {
      await action();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  async function install(offline: boolean) {
    setInstalling(offline ? "import" : "download");
    try { await run(async () => { await invoke("writing_install", {offline}); await status(); }); }
    finally { setInstalling(null); }
  }
  return (
    <div>
      <QuietIcon
        icon={Sparkles}
        label="Local writing tools"
        aria-expanded={open}
        onClick={() => {
          panelSound(open); setOpen(!open);
          if (!open) void status().catch((e) => setError(message(e)));
        }}
      />
      {open && (
        <section
          aria-label="Local writing tools"
          className="quiet-panel mt-2 space-y-3 rounded-control border border-line p-3"
        >
          {ready === false ? (
            <div className="flex flex-wrap items-center gap-2 text-sm text-ink-soft">
              <a href="#/models" className="model-route">Qwen 2.5 · 1.12 GB</a>
              <QuietIcon icon={installing === "download" ? LoaderCircle : Download} className={installing === "download" ? "vyrra-busy" : ""}
                disabled={busy} aria-busy={installing === "download"} label="Download local writing model" onClick={() => void install(false)} />
              <QuietIcon icon={installing === "import" ? LoaderCircle : FolderOpen} className={installing === "import" ? "vyrra-busy" : ""}
                disabled={busy} aria-busy={installing === "import"} label="Choose writing model folder" onClick={() => void install(true)} />
            </div>
          ) : (
            ready && (
              <>
                <select
                  aria-label="Writing task"
                  className="sound-trigger"
                  value={task}
                  disabled={busy}
                  onChange={(e) => {
                    setTask(e.target.value as WritingTask);
                    setAnswer("");
                  }}
                >
                  <option value="rewrite">Edit text</option>
                  <option value="draft">Draft</option>
                  <option value="meetingNotes">Meeting notes</option>
                  <option value="ask">Ask a question</option>
                </select>
                {task !== "meetingNotes" && (
                  <input
                    aria-label="Writing instruction"
                    className="w-full rounded-control border border-line bg-canvas-subtle p-2 text-sm"
                    placeholder={
                      task === "ask"
                        ? "Ask about this transcript…"
                        : "What would you like to write?"
                    }
                    value={instruction}
                    onChange={(e) => setInstruction(e.target.value)}
                  />
                )}
                <div className="flex items-center gap-2">
                  <Button
                    variant="secondary"
                    disabled={
                      busy ||
                      (task !== "meetingNotes" && !instruction.trim()) ||
                      (task !== "draft" && !source.trim())
                    }
                    onClick={() =>
                      void run(async () =>
                        setAnswer(
                          await invoke<string>("writing_run", {
                            task,
                            instruction,
                            source: task === "ask" ? `[1] ${source}` : source,
                          }),
                        ),
                      )
                    }
                  >
                    Run locally
                  </Button>
                  {busy && (
                    <QuietIcon
                      icon={X}
                      label="Cancel writing"
                      onClick={() =>
                        void invoke("writing_cancel").catch((e) =>
                          setError(message(e)),
                        )
                      }
                    />
                  )}
                </div>
                {answer && (
                  <div className="space-y-2">
                    <p className="whitespace-pre-wrap text-sm text-ink">
                      {answer}
                    </p>
                    {apply && (
                      <Button
                        variant="quiet"
                        onClick={() => {
                          apply(answer);
                          setAnswer("");
                        }}
                      >
                        Use this text
                      </Button>
                    )}
                  </div>
                )}
              </>
            )
          )}
          {busy && (
            <p role="status" className="text-xs text-ink-soft">
              Working locally…
            </p>
          )}
          {error && (
            <p role="alert" className="text-xs text-ink-soft">
              {error}
            </p>
          )}
        </section>
      )}
    </div>
  );
}
