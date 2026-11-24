import type { ButtonHTMLAttributes, HTMLAttributes, ReactNode } from "react";
import { ArrowRight, CircleAlert, Info, LockKeyhole } from "lucide-react";

import { cn } from "../lib/cn";

type ButtonVariant = "primary" | "secondary" | "quiet" | "danger";

const buttonVariantClasses: Record<ButtonVariant, string> = {
  primary: "bg-accent text-on-accent hover:bg-accent-hover",
  secondary:
    "border border-line-strong bg-surface-raised text-ink hover:bg-surface-strong",
  quiet: "text-ink-soft hover:bg-surface-strong hover:text-ink",
  danger: "bg-danger text-surface-raised hover:opacity-90",
};

export function Button({
  variant = "primary",
  className,
  type = "button",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
}) {
  return (
    <button
      type={type}
      className={cn(
        "inline-flex min-h-10 items-center justify-center gap-2 rounded-full px-4 text-sm font-semibold transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:opacity-45",
        buttonVariantClasses[variant],
        className,
      )}
      {...props}
    />
  );
}

export function ActionLink({
  href,
  children,
  variant = "primary",
  className,
}: {
  href: string;
  children: ReactNode;
  variant?: Exclude<ButtonVariant, "danger">;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={cn(
        "inline-flex min-h-10 items-center justify-center gap-2 rounded-full px-4 text-sm font-semibold transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus",
        buttonVariantClasses[variant],
        className,
      )}
    >
      {children}
    </a>
  );
}

export function TextLink({
  href,
  children,
  className,
}: {
  href: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={cn(
        "inline-flex min-h-10 items-center gap-2 rounded-control px-1 text-sm font-semibold text-accent underline-offset-4 hover:underline focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus",
        className,
      )}
    >
      {children}
      <ArrowRight size={15} aria-hidden="true" />
    </a>
  );
}

export function Card({
  className,
  ...props
}: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-card border border-line bg-surface",
        className,
      )}
      {...props}
    />
  );
}

type BadgeTone =
  | "neutral"
  | "accent"
  | "success"
  | "warning"
  | "danger"
  | "info";

export function Badge({
  children,
  tone = "neutral",
  className,
}: {
  children: ReactNode;
  tone?: BadgeTone;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex min-h-6 items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[0.69rem] font-bold uppercase tracking-[0.08em]",
        tone === "neutral" &&
          "border-line bg-surface-strong text-ink-soft",
        tone === "accent" && "border-accent/30 bg-accent-soft text-ink",
        tone === "success" &&
          "border-success/30 bg-success-soft text-success",
        tone === "warning" &&
          "border-warning/30 bg-warning-soft text-warning",
        tone === "danger" && "border-danger/30 bg-danger-soft text-danger",
        tone === "info" && "border-info/30 bg-info-soft text-info",
        className,
      )}
    >
      {children}
    </span>
  );
}

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <header className="flex flex-col gap-5 border-b border-line pb-7 sm:flex-row sm:items-end sm:justify-between">
      <div className="max-w-3xl">
        {eyebrow && (
          <p className="mb-2 text-xs font-bold uppercase tracking-[0.14em] text-ink-faint">
            {eyebrow}
          </p>
        )}
        <h1 className="text-balance text-3xl font-semibold tracking-[-0.035em] text-ink sm:text-[2.45rem] sm:leading-[1.08]">
          {title}
        </h1>
        {description && (
          <p className="mt-3 max-w-2xl text-pretty text-sm leading-6 text-ink-soft sm:text-[0.95rem]">
            {description}
          </p>
        )}
      </div>
      {actions && <div className="shrink-0">{actions}</div>}
    </header>
  );
}

export function SectionHeading({
  id,
  title,
  description,
  action,
}: {
  id?: string;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex items-end justify-between gap-4">
      <div>
        <h2
          id={id}
          className="text-lg font-semibold tracking-[-0.02em] text-ink"
        >
          {title}
        </h2>
        {description && (
          <p className="mt-1 text-sm leading-5 text-ink-soft">{description}</p>
        )}
      </div>
      {action}
    </div>
  );
}

export function InlineNotice({
  tone = "info",
  title,
  children,
}: {
  tone?: "info" | "warning" | "privacy";
  title: string;
  children: ReactNode;
}) {
  const Icon = tone === "warning" ? CircleAlert : tone === "privacy" ? LockKeyhole : Info;

  return (
    <div
      className={cn(
        "flex gap-3 rounded-card border p-4",
        tone === "warning" && "border-warning/35 bg-warning-soft",
        tone === "info" && "border-info/35 bg-info-soft",
        tone === "privacy" && "border-success/35 bg-success-soft",
      )}
      role="note"
    >
      <Icon
        className={cn(
          "mt-0.5 shrink-0",
          tone === "warning" && "text-warning",
          tone === "info" && "text-info",
          tone === "privacy" && "text-success",
        )}
        size={18}
        aria-hidden="true"
      />
      <div>
        <p className="text-sm font-semibold text-ink">{title}</p>
        <div className="mt-1 text-sm leading-5 text-ink-soft">{children}</div>
      </div>
    </div>
  );
}

export function StatusDot({
  tone,
}: {
  tone: "success" | "warning" | "danger" | "neutral";
}) {
  return (
    <span
      className={cn(
        "size-2 shrink-0 rounded-full",
        tone === "success" && "bg-success",
        tone === "warning" && "bg-warning",
        tone === "danger" && "bg-danger",
        tone === "neutral" && "bg-ink-faint",
      )}
      aria-hidden="true"
    />
  );
}

export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon: ReactNode;
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <Card className="grid min-h-64 place-items-center p-8 text-center">
      <div className="max-w-md">
        <span className="mx-auto grid size-12 place-items-center rounded-2xl bg-surface-strong text-ink-soft">
          {icon}
        </span>
        <h2 className="mt-4 text-lg font-semibold text-ink">{title}</h2>
        <p className="mt-2 text-sm leading-6 text-ink-soft">{description}</p>
        {action && <div className="mt-5">{action}</div>}
      </div>
    </Card>
  );
}
