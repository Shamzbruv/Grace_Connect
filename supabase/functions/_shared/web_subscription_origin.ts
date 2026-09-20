// graceconnect.love is the live site. The .app entries predate it and no
// longer resolve at all, so on their own this list would have rejected every
// real request from the actual website.
const defaultOrigins = [
  "https://graceconnect.love",
  "https://www.graceconnect.love",
  "https://graceconnect.app",
  "https://www.graceconnect.app",
  "https://graceconnect-app.onrender.com",
];

export function webSubscriptionOrigins(configured?: string): Set<string> {
  const configuredOrigins = String(configured ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([...defaultOrigins, ...configuredOrigins]);
}

export function isAllowedWebSubscriptionOrigin(
  origin: string | null,
  configured?: string,
): boolean {
  if (!origin) return false;
  if (webSubscriptionOrigins(configured).has(origin)) return true;
  return /^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d{1,5})?$/.test(origin);
}
