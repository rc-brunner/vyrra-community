import type { ButtonHTMLAttributes } from "react";
import type { LucideIcon } from "lucide-react";

type Props = ButtonHTMLAttributes<HTMLButtonElement> & { label: string; icon: LucideIcon };
export function QuietIcon({ label, icon: Icon, className = "", ...props }: Props) {
  return <button type="button" aria-label={label} title={label} className={`vyrra-icon ${className}`} {...props}>
    <Icon size={16} strokeWidth={1.65} aria-hidden="true" />
  </button>;
}
