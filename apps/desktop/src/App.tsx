import { useEffect, useState } from "react";

import { AppShell } from "./components/AppShell";
import { routeFromHash, type RouteId } from "./lib/navigation";
import { CapturePage } from "./pages/CapturePage";
import { LibraryPage } from "./pages/LibraryPage";
import { SettingsPage } from "./pages/SettingsPage";

const routeTitles: Record<RouteId, string> = {
  capture: "Dictate",
  library: "Library",
  settings: "Settings",
};

function useHashRoute(): RouteId {
  const [route, setRoute] = useState<RouteId>(() =>
    routeFromHash(window.location.hash),
  );

  useEffect(() => {
    const onHashChange = () => setRoute(routeFromHash(window.location.hash));
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  return route;
}

function CurrentPage({ route }: { route: RouteId }) {
  switch (route) {
    case "capture":
      return <CapturePage />;
    case "library":
      return <LibraryPage />;
    case "settings":
      return <SettingsPage />;
    default:
      return <CapturePage />;
  }
}

export function App() {
  const route = useHashRoute();

  useEffect(() => {
    document.title = `${routeTitles[route]} · Vyrra Desktop`;
    const mainContent = document.getElementById("main-content");
    mainContent?.focus({ preventScroll: true });
    document.documentElement.scrollTop = 0;
    document.body.scrollTop = 0;

    const resetScroll = () => {
      document.documentElement.scrollTop = 0;
      document.body.scrollTop = 0;
      if (window.scrollY > 0) {
        window.scrollTo({ top: 0, left: 0, behavior: "auto" });
      }
    };
    const scrollTimer = window.setTimeout(resetScroll, 0);

    return () => {
      window.clearTimeout(scrollTimer);
    };
  }, [route]);

  return (
    <AppShell route={route}>
      <CurrentPage route={route} />
    </AppShell>
  );
}
