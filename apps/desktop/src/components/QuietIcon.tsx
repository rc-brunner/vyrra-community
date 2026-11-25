import {
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
} from "react";
import { createPortal } from "react-dom";
import type { LucideIcon } from "lucide-react";

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  label: string;
  icon: LucideIcon;
};
export function QuietIcon({
  label,
  icon: Icon,
  className = "",
  ...props
}: Props) {
  const id = useId();
  const button = useRef<HTMLButtonElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [anchor, setAnchor] = useState<DOMRect | null>(null);
  const hide = () => {
    clearTimeout(timer.current);
    setAnchor(null);
  };
  const show = (delay: number) => {
    clearTimeout(timer.current);
    timer.current = setTimeout(
      () => setAnchor(button.current?.getBoundingClientRect() ?? null),
      delay,
    );
  };
  useEffect(() => () => clearTimeout(timer.current), []);
  useEffect(() => {
    if (!anchor) return;
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape") hide();
    };
    window.addEventListener("keydown", escape);
    window.addEventListener("resize", hide);
    window.addEventListener("scroll", hide, true);
    return () => {
      window.removeEventListener("keydown", escape);
      window.removeEventListener("resize", hide);
      window.removeEventListener("scroll", hide, true);
    };
  }, [anchor]);
  return (
    <>
      <button
        type="button"
        {...props}
        ref={button}
        aria-label={label}
        aria-describedby={anchor ? id : undefined}
        className={`vyrra-icon ${className}`}
        onPointerEnter={(event) => {
          if (event.pointerType !== "touch") show(350);
          props.onPointerEnter?.(event);
        }}
        onPointerLeave={(event) => {
          hide();
          props.onPointerLeave?.(event);
        }}
        onFocus={(event) => {
          if (event.currentTarget.matches(":focus-visible")) show(0);
          props.onFocus?.(event);
        }}
        onBlur={(event) => {
          hide();
          props.onBlur?.(event);
        }}
        onPointerDown={(event) => {
          hide();
          props.onPointerDown?.(event);
        }}
      >
        <Icon size={16} strokeWidth={1.65} aria-hidden="true" />
      </button>
      {anchor &&
        createPortal(
          <span
            id={id}
            role="tooltip"
            className="vyrra-tip"
            style={{
              left: Math.max(
                8,
                Math.min(
                  anchor.left,
                  window.innerWidth - Math.min(240, label.length * 7 + 18),
                ),
              ),
              top:
                anchor.bottom + 34 < window.innerHeight
                  ? anchor.bottom + 5
                  : anchor.top - 30,
            }}
          >
            {label}
          </span>,
          document.body,
        )}
    </>
  );
}
