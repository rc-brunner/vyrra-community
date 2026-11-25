import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  AudioLines,
  Check,
  ChevronRight,
  CirclePlay,
  Download,
  ExternalLink,
  FolderOpen,
  Globe2,
  Keyboard,
  Languages,
  LoaderCircle,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { QuietIcon } from "../components/QuietIcon";
import { Button, ShortcutButton } from "../components/ui";
import { message } from "../lib/dictation";
import { isNativeDesktop } from "../lib/native";
import {
  formatSize,
  modelAction,
  modelStatus,
  speechModels,
  writer,
  writerStatus,
  type ModelJob,
  type ModelStatus,
  type WriterStatus,
} from "../lib/models";

type Action = Parameters<typeof modelAction>[1];
type Model = { id: string; name: string; bytes: number };
type Device = { speech: ModelStatus; writing: WriterStatus };
const sources = [
  {
    id: "whisper",
    name: "Whisper weights",
    url: "https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1",
  },
  {
    id: "qwen",
    name: "Qwen weights",
    url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/tree/91cad51170dc346986eccefdc2dd33a9da36ead9",
  },
  {
    id: "tokenizer",
    name: "Qwen tokenizer",
    url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/blob/989aa7980e4cf806f80c7fef2b1adb7bc71aa306/tokenizer.json",
  },
] as const;

function ModelRow({
  model,
  group,
  active,
  installed,
  job,
  disabled,
  onAction,
}: {
  model: Model;
  group: string;
  active: boolean;
  installed: boolean;
  job: ModelJob | null;
  disabled: boolean;
  onAction: (id: string, action: Action) => Promise<void>;
}) {
  const [confirm, setConfirm] = useState(false);
  const writing = model.id === writer.id;
  const name = writing ? model.name : `Whisper ${model.name}`;
  const fullName = writing ? name : `${name}, ${group}`;
  const mainRef = useRef<HTMLDivElement>(null);
  const transfer = job?.stage === "transferring" || job?.stage === "importing";
  const percent = job
    ? Math.min(100, Math.floor((job.received / model.bytes) * 100))
    : 0;
  const state = job
    ? {
        choosing: "Choose file",
        importing: "Importing",
        transferring: "Downloading",
        verifying: "Verifying",
      }[job.stage]
    : active
      ? "In use"
      : installed
        ? "Downloaded"
        : "";
  const mainLabel = job
    ? `${state} ${fullName}`
    : active
      ? `${fullName} in use`
      : installed
        ? writing
          ? `${name} downloaded`
          : `Use ${fullName}`
        : `Download ${fullName}`;
  const settled = active || (writing && installed);
  const Icon = writing ? Keyboard : AudioLines;
  const undoConfirm = () => {
    setConfirm(false);
    requestAnimationFrame(() =>
      mainRef.current
        ?.querySelector<HTMLButtonElement>(".model-secondary button")
        ?.focus(),
    );
  };
  return (
    <div
      className="model-row"
      data-active={active}
      ref={mainRef}
      onKeyDown={(e) => {
        if (confirm && e.key === "Escape") {
          e.preventDefault();
          undoConfirm();
        }
      }}
    >
      <span className="model-glyph" aria-hidden="true">
        <Icon size={17} strokeWidth={1.65} />
      </span>
      <div className="model-copy">
        <span className="model-name">{name}</span>
        <span className="model-meta">
          {confirm ? (
            "Remove from this device?"
          ) : (
            <>
              {formatSize(model.bytes)}
              {state && (
                <>
                  {" "}
                  · {state}
                  {job && transfer ? ` ${percent}%` : ""}
                </>
              )}
              {!state && model.id === "base" && " · Default"}
            </>
          )}
        </span>
      </div>
      <div className="model-controls">
        {confirm ? (
          <>
            <QuietIcon
              label={`Keep ${fullName}`}
              icon={X}
              autoFocus
              onClick={undoConfirm}
            />
            <QuietIcon
              label={`Confirm removal of ${fullName}`}
              icon={Trash2}
              className="model-remove"
              onClick={() => {
                setConfirm(false);
                void onAction(model.id, "remove").finally(() =>
                  mainRef.current
                    ?.querySelector<HTMLButtonElement>(".model-primary button")
                    ?.focus(),
                );
              }}
            />
          </>
        ) : (
          <>
            <span className="model-secondary" data-busy={Boolean(job)}>
              {job ? (
                <QuietIcon
                  label={`Cancel setup for ${fullName}`}
                  icon={X}
                  disabled={job.stage === "choosing"}
                  onClick={() => void onAction(model.id, "cancel")}
                />
              ) : installed ? (
                <QuietIcon
                  label={`Remove ${fullName}`}
                  icon={Trash2}
                  disabled={disabled}
                  onClick={() => setConfirm(true)}
                />
              ) : (
                <QuietIcon
                  label={`Import ${fullName}`}
                  icon={FolderOpen}
                  disabled={disabled}
                  onClick={() => void onAction(model.id, "import")}
                />
              )}
            </span>
            <span className="model-primary">
              <QuietIcon
                label={mainLabel}
                icon={
                  job
                    ? LoaderCircle
                    : settled
                      ? Check
                      : installed
                        ? CirclePlay
                        : Download
                }
                className={job ? "vyrra-busy" : settled ? "model-check" : ""}
                aria-busy={Boolean(job)}
                aria-disabled={disabled || Boolean(job) || settled}
                disabled={disabled && !job && !settled}
                onClick={() => {
                  if (!disabled && !job && !settled)
                    void onAction(model.id, installed ? "use" : "download");
                }}
              />
            </span>
          </>
        )}
      </div>
    </div>
  );
}

const groups = [
  {
    label: "Multilingual",
    icon: Globe2,
    models: speechModels.filter((m) => m.languages > 1),
  },
  {
    label: "English only",
    icon: Languages,
    models: speechModels.filter((m) => m.languages === 1),
  },
  { label: "Writing", icon: Keyboard, models: [writer] },
];

export function ModelsPage() {
  const native = isNativeDesktop();
  const [device, setDevice] = useState<Device>();
  const [loadError, setLoadError] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [announcement, setAnnouncement] = useState("");
  const [pending, setPending] = useState<{ id: string; action: Action } | null>(
    null,
  );
  const [finding, setFinding] = useState(false);
  const [query, setQuery] = useState("");
  const findButton = useRef<HTMLButtonElement>(null);
  const input = useRef<HTMLInputElement>(null);
  const mounted = useRef(false);
  const sequence = useRef(0);
  const refresh = useCallback(async () => {
    const request = ++sequence.current;
    try {
      const [speech, writing] = await Promise.all([
        modelStatus(),
        writerStatus(),
      ]);
      if (mounted.current && request === sequence.current) {
        setDevice({ speech, writing });
        setLoadError("");
      }
      return { speech, writing };
    } catch (e) {
      if (mounted.current && request === sequence.current)
        setLoadError(message(e));
    }
  }, []);
  useEffect(() => {
    mounted.current = true;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout>;
    async function poll() {
      await refresh();
      if (!stopped) timer = setTimeout(() => void poll(), 500);
    }
    if (native) void poll();
    return () => {
      stopped = true;
      mounted.current = false;
      clearTimeout(timer);
    };
  }, [native, refresh]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (
        event.key !== "/" ||
        event.metaKey ||
        event.ctrlKey ||
        event.altKey ||
        event.isComposing ||
        (event.target instanceof Element &&
          event.target.closest(
            "input, textarea, select, [contenteditable=true]",
          ))
      )
        return;
      event.preventDefault();
      setFinding(true);
      input.current?.focus();
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  useEffect(() => {
    if (finding) input.current?.focus();
  }, [finding]);
  function closeFind() {
    setFinding(false);
    setQuery("");
    requestAnimationFrame(() => findButton.current?.focus());
  }
  async function act(id: string, action: Action) {
    setError("");
    setNotice("");
    setAnnouncement("");
    if (action !== "cancel") setPending({ id, action });
    try {
      await modelAction(id, action);
      if (action === "remove") setNotice("Model removed.");
      if (["use", "download", "import"].includes(action)) {
        const installed = await refresh();
        if (id === writer.id && installed?.writing.installed)
          setAnnouncement("Writing model downloaded.");
        else if (id === installed?.speech.active) {
          const model = speechModels.find((m) => m.id === id);
          if (model)
            setAnnouncement(
              `Whisper ${model.name}, ${model.languages === 1 ? "English only" : "Multilingual"}, is in use.`,
            );
        }
      }
    } catch (e) {
      if (message(e) === "Model setup canceled.") setNotice(message(e));
      else setError(message(e));
    } finally {
      await refresh();
      if (action !== "cancel") setPending(null);
    }
  }
  const term = query.trim().toLowerCase();
  const visibleGroups = groups
    .map((group) => ({
      ...group,
      models: group.models.filter((m) =>
        `${group.label} ${m.id === writer.id ? "Qwen" : "Whisper"} ${m.name} ${m.id}`
          .toLowerCase()
          .includes(term),
      ),
    }))
    .filter((group) => group.models.length);
  return (
    <div className="model-page">
      <header className="model-header">
        <div>
          <h1 className="vyrra-page-title">Models</h1>
          <p>Download once. Dictate and write offline.</p>
        </div>
        {finding ? (
          <div className="model-search">
            <Search size={14} aria-hidden="true" />
            <input
              ref={input}
              type="search"
              aria-label="Find a model"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Find a model"
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  e.preventDefault();
                  closeFind();
                }
              }}
            />
            <QuietIcon label="Close search" icon={X} onClick={closeFind} />
          </div>
        ) : (
          <ShortcutButton
            ref={findButton}
            className="model-find"
            shortcut="/"
            onClick={() => setFinding(true)}
          >
            Find
          </ShortcutButton>
        )}
      </header>
      {!native && (
        <p className="model-note">
          Open Vyrra Desktop to install models on this device.
        </p>
      )}
      {native && !device && !loadError && (
        <p role="status" className="model-note">
          Checking installed models…
        </p>
      )}
      {device && !device.speech.idle && (
        <p role="status" className="model-note">
          Finish dictation to change speech models.
        </p>
      )}
      {(error || loadError) && (
        <p role="alert" className="model-error">
          {error || loadError}
        </p>
      )}
      <div role="status" className={notice ? "model-note" : "sr-only"}>
        {notice || announcement}
      </div>
      {visibleGroups.map(({ label, icon: Icon, models: visible }) => {
        return (
          <section key={label} aria-label={label} className="model-group">
            <h2>
              <Icon size={14} aria-hidden="true" />
              {label}
            </h2>
            <div className="model-grid">
              {visible.map((model) => {
                const writing = model.id === writer.id;
                const waiting =
                  pending?.id === model.id &&
                  ["download", "import", "use"].includes(pending.action);
                const speechJob = device?.speech.job;
                const job =
                  writing && device?.writing.installing
                    ? {
                        id: model.id,
                        stage:
                          device.writing.received >= device.writing.bytes
                            ? ("verifying" as const)
                            : pending?.action === "import"
                              ? ("importing" as const)
                              : ("transferring" as const),
                        received: device.writing.received,
                      }
                    : speechJob?.id === model.id
                      ? speechJob
                      : waiting
                        ? {
                            id: model.id,
                            stage:
                              pending?.action === "use"
                                ? ("verifying" as const)
                                : pending?.action === "import"
                                  ? ("choosing" as const)
                                  : ("transferring" as const),
                            received: 0,
                          }
                        : null;
                return (
                  <ModelRow
                    key={model.id}
                    model={model}
                    group={label}
                    job={job}
                    installed={
                      writing
                        ? Boolean(device?.writing.installed)
                        : Boolean(device?.speech.installed.includes(model.id))
                    }
                    active={!writing && device?.speech.active === model.id}
                    disabled={
                      !device ||
                      Boolean(loadError) ||
                      Boolean(pending) ||
                      (writing
                        ? device.writing.busy
                        : !device.speech.idle || Boolean(speechJob))
                    }
                    onAction={act}
                  />
                );
              })}
            </div>
          </section>
        );
      })}
      {!visibleGroups.length && (
        <p className="model-note">No matching models.</p>
      )}
      <details className="model-sources">
        <summary>
          <ChevronRight size={14} aria-hidden="true" />
          Sources &amp; files
        </summary>
        <div>
          {sources.map((source) => (
            <a
              key={source.id}
              href={source.url}
              target="_blank"
              rel="noreferrer"
              onClick={(event) => {
                if (native) {
                  event.preventDefault();
                  void invoke("model_source", { source: source.id }).catch(
                    (e) => setError(message(e)),
                  );
                }
              }}
            >
              {source.name}
              <ExternalLink size={12} aria-hidden="true" />
            </a>
          ))}
          {native && (
            <Button
              variant="quiet"
              onClick={() =>
                void invoke("model_source", { source: "folder" }).catch((e) =>
                  setError(message(e)),
                )
              }
            >
              <FolderOpen size={14} />
              Open models folder
            </Button>
          )}
        </div>
      </details>
    </div>
  );
}
