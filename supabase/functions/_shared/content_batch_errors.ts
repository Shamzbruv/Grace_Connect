/** The final fallback provider decides whether a retry can help today. */
export function contentQuotaExhausted(diagnostic: unknown): boolean {
  if (typeof diagnostic !== "string") return false;
  const fallback = diagnostic.toLowerCase().lastIndexOf("gemini:");
  const finalProvider = fallback < 0 ? diagnostic : diagnostic.slice(fallback);
  return /RESOURCE_EXHAUSTED|quota exceeded|exceeded your current quota|depleted your monthly included credits|HTTP 429/i
    .test(finalProvider);
}

export function contentBatchFailure(name: string, diagnostic: unknown): string {
  return contentQuotaExhausted(diagnostic)
    ? "[quota] AI request quota reached. Preparation will resume automatically after a 24-hour cooldown."
    : `${name} did not complete. Check its generation run.`;
}
