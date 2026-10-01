import { presignR2Url, type R2Config } from "./r2.ts";

export const RESET_CONFIRMATION = "DELETE ALL DATA EXCEPT MY DEVELOPER ACCOUNT";

export function validateResetRequest(body: Record<string, unknown>): boolean {
  return body.confirmation === RESET_CONFIRMATION &&
    typeof body.password === "string" && body.password.length > 0 && body.password.length <= 1024;
}

// R2 returns URL-encoded object names, so XML entities / embedded markup cannot
// alter a key. We keep the parser deliberately specific to ListObjectsV2.
export function parseResetObjectKeys(xml: string): string[] {
  if (!xml.includes("<ListBucketResult") || !xml.includes("</ListBucketResult>")) {
    throw new Error("R2 listing was not a bucket result.");
  }
  const keys = [...xml.matchAll(/<Key>([^<]*)<\/Key>/g)].map(match => decodeURIComponent(match[1]));
  const count = xml.match(/<KeyCount>(\d+)<\/KeyCount>/)?.[1];
  const encoded = xml.includes('<EncodingType>url</EncodingType>');
  const truncated = xml.match(/<IsTruncated>(true|false)<\/IsTruncated>/)?.[1];
  if (!encoded || count === undefined || Number(count) !== keys.length ||
      truncated === undefined || (truncated === 'true' && keys.length === 0)) {
    throw new Error('Incomplete R2 listing.');
  }
  if (keys.some(key => !key || key.includes("\0"))) throw new Error("Invalid R2 object key.");
  if (keys.length > 50) throw new Error("Unexpected R2 batch size.");
  return keys;
}

export async function listResetObjects(config: R2Config, fetcher = fetch): Promise<string[]> {
  const url = await presignR2Url({ config, method: "GET", key: "", listObjects: true, expiresInSeconds: 60 });
  const response = await fetcher(url, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error("R2 object listing failed.");
  return parseResetObjectKeys(await response.text());
}
