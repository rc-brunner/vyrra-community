import {
  useEffect,
  useRef,
  type MouseEvent,
  type ReactNode,
} from "react";
import {
  LibraryBig,
  Mic2,
  Settings2,
} from "lucide-react";

import { cn } from "../lib/cn";
import {
  hrefForRoute,
  type RouteId,
} from "../lib/navigation";
import { BrandMark } from "./BrandMark";

const navigation = [
  {
    id: "capture",
    route: "capture",
    label: "Dictate",
    icon: Mic2,
    href: hrefForRoute("capture"),
  },
  {
    id: "library",
    route: "library",
    label: "Library",
    icon: LibraryBig,
    href: hrefForRoute("library"),
  },
  {
    id: "settings",
    route: "settings",
    label: "Settings",
    icon: Settings2,
    href: hrefForRoute("settings"),
  },
] satisfies ReadonlyArray<{
  id: string;
  route: RouteId;
  label: string;
  icon: typeof Mic2;
  href: string;
}>;

function NavigationItems({
  route,
  mobile = false,
}: {
  route: RouteId;
  mobile?: boolean;
}) {
  return navigation.map(({ id, route: itemRoute, label, icon: Icon, href }) => {
    const active = itemRoute === route;

    return (
      <a
        key={id}
        href={href}
        aria-current={active ? "page" : undefined}
        className={cn(
          "group flex min-h-10 items-center gap-3 rounded-control text-sm font-medium transition-colors focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-focus",
          mobile ? "shrink-0 px-3" : "w-full px-3",
          active
            ? "bg-accent-soft text-ink"
            : "text-ink-soft hover:bg-surface-strong hover:text-ink",
        )}
      >
        <Icon
          size={17}
          strokeWidth={active ? 2.3 : 1.9}
          className={active ? "text-accent" : "text-ink-faint"}
          aria-hidden="true"
        />
        <span>{label}</span>
      </a>
    );
  });
}

function MobileNavigation({
  route,
}: {
  route: RouteId;
}) {
  const navigationRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const navigationElement = navigationRef.current;
    const activeLink = navigationElement?.querySelector<HTMLAnchorElement>(
      'a[aria-current="page"]',
    );

    if (!navigationElement || !activeLink) return;

    navigationElement.scrollLeft = Math.max(
      0,
      activeLink.offsetLeft -
        (navigationElement.clientWidth - activeLink.clientWidth) / 2,
    );
  }, [route]);

  return (
    <nav
      ref={navigationRef}
      aria-label="Primary mobile"
      className="-mx-1 mt-3 flex gap-1 overflow-x-auto pb-1 md:hidden"
    >
      <NavigationItems route={route} mobile />
    </nav>
  );
}

export function AppShell({
  route,
  children,
}: {
  route: RouteId;
  children: ReactNode;
}) {
  const skipToContent = (event: MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    document.getElementById("main-content")?.focus();
  };

  return (
    <div className="min-h-dvh bg-canvas text-ink">
      <a
        href={hrefForRoute(route)}
        onClick={skipToContent}
        className="fixed left-4 top-3 z-50 -translate-y-20 rounded-control bg-accent px-4 py-2 text-sm font-semibold text-on-accent focus:translate-y-0 focus:outline-3 focus:outline-offset-2 focus:outline-focus"
      >
        Skip to content
      </a>

      <aside className="fixed inset-y-0 left-0 z-30 hidden w-[15.5rem] flex-col border-r border-line bg-canvas/95 p-4 backdrop-blur md:flex">
        <div className="px-2 pb-5 pt-1">
          <BrandMark />
        </div>

        <nav aria-label="Primary" className="flex flex-1 flex-col gap-1">
          <NavigationItems route={route} />
        </nav>
      </aside>

      <div className="md:pl-[15.5rem]">
        <header className="sticky top-0 z-20 border-b border-line bg-canvas/90 px-4 py-3 backdrop-blur-xl sm:px-6 md:hidden">
          <div className="mx-auto flex max-w-[92rem] items-center justify-between gap-4">
            <BrandMark compact />
          </div>

          <MobileNavigation route={route} />
        </header>

        <main
          id="main-content"
          tabIndex={-1}
          className="mx-auto min-h-[calc(100dvh-4.15rem)] max-w-[92rem] px-4 py-7 outline-none sm:px-6 sm:py-9 lg:px-9 lg:py-10"
        >
          {children}
        </main>
      </div>
    </div>
  );
}
