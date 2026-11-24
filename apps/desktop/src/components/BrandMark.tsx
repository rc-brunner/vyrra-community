import vyrraIcon from "../../../../assets/brand/vyrra-icon.svg?url";

export function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex min-w-0 items-center gap-3">
      <img
        src={vyrraIcon}
        alt=""
        className="size-9 shrink-0 rounded-xl border border-line object-cover"
      />
      {!compact && (
        <span className="min-w-0">
          <span className="block truncate text-[0.69rem] font-semibold uppercase tracking-[0.15em] text-ink-faint">
            Vyrra
          </span>
          <span className="block truncate text-[0.93rem] font-semibold text-ink">
            Desktop
          </span>
        </span>
      )}
      {compact && <span className="sr-only">Vyrra Desktop</span>}
    </div>
  );
}
