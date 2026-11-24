export const ROUTES = [
  "capture",
  "library",
  "settings",
] as const;

export type RouteId = (typeof ROUTES)[number];

export function isRouteId(value: string): value is RouteId {
  return ROUTES.includes(value as RouteId);
}

export function routeFromHash(hash: string): RouteId {
  const candidate = hash.replace(/^#\/?/, "").split("/")[0] ?? "";
  return isRouteId(candidate) ? candidate : "capture";
}

export function hrefForRoute(route: RouteId): string {
  return `#/${route}`;
}
