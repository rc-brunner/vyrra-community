import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { Check, ChevronDown, Volume2 } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { QuietIcon } from "./QuietIcon";
import { type Sound, message } from "../lib/dictation";

const choices = {
  classic: "Classic",
  soft: "Soft click",
  felt: "Felt thud",
  off: "Off",
} as const;
const sounds = Object.keys(choices) as Sound[];
export function SoundPicker({
  value,
  onChange, disabled,
}: {
  value: Sound;
  disabled?: boolean;
  onChange: (value: Sound) => void;
}) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(value);
  const [previewing, setPreviewing] = useState(false);
  const [error, setError] = useState("");
  const button = useRef<HTMLButtonElement>(null);
  const container = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const id = useId();
  useEffect(() => {
    if (!open) return;
    list.current?.focus();
    const outside = (event: PointerEvent) => {
      if (!container.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, [open]);
  const close = () => {
    setOpen(false);
    button.current?.focus();
  };
  const select = (sound: Sound) => {
    onChange(sound);
    close();
  };
  function key(event: KeyboardEvent) {
    const i = sounds.indexOf(active);
    switch (event.key) {
      case "ArrowDown":
        setActive(sounds[(i + 1) % sounds.length]!);
        break;
      case "ArrowUp":
        setActive(sounds[(i + sounds.length - 1) % sounds.length]!);
        break;
      case "Home":
        setActive(sounds[0]!);
        break;
      case "End":
        setActive("off");
        break;
      case "Escape":
        close();
        break;
      case "Enter":
      case " ":
        select(active);
        break;
      case "Tab":
        return;
      default:
        return;
    }
    event.preventDefault();
  }
  async function preview() {
    setPreviewing(true);
    setError("");
    try {
      await invoke("dictation_preview_sound", { sound: value });
    } catch (reason) {
      setError(message(reason));
    } finally {
      setPreviewing(false);
    }
  }
  return (
    <div>
      <div className="flex items-center justify-between gap-2">
        <span id={`${id}-label`} className="text-sm font-semibold text-ink">
          Dictation sound
        </span>
        <div
          ref={container}
          className="relative flex items-center gap-1"
          onBlur={(event) => {
            if (!event.currentTarget.contains(event.relatedTarget))
              setOpen(false);
          }}
        >
          <QuietIcon
            icon={Volume2}
            label="Preview start and finish sounds"
            disabled={value === "off" || previewing}
            onClick={() => void preview()}
          />
          <button
            type="button"
            disabled={disabled}
            className="sound-trigger"
            ref={button}
            aria-haspopup="listbox"
            aria-expanded={open}
            aria-controls={open ? id : undefined}
            aria-label={`Dictation sound, ${choices[value]}`}
            onClick={() => {
              setActive(value);
              setOpen(!open);
            }}
            onKeyDown={(event) => {
              if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                event.preventDefault();
                setActive(value);
                setOpen(true);
              }
            }}
          >
            {choices[value]}
            <ChevronDown size={13} aria-hidden="true" />
          </button>
          {open && (
            <div
              ref={list}
              id={id}
              role="listbox"
              tabIndex={-1}
              aria-labelledby={`${id}-label`}
              aria-activedescendant={`${id}-${active}`}
              className="sound-menu"
              onKeyDown={key}
            >
              {sounds.map((sound) => (
                <div
                  role="option"
                  key={sound}
                  id={`${id}-${sound}`}
                  aria-selected={value === sound}
                  data-active={active === sound}
                  onPointerMove={() => setActive(sound)}
                  onClick={() => select(sound)}
                >
                  {choices[sound]}
                  {value === sound && <Check size={14} aria-hidden="true" />}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
      {error && (
        <p role="alert" className="text-xs text-ink-soft">
          {error}
        </p>
      )}
    </div>
  );
}
