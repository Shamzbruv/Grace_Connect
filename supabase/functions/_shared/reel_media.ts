// Shared R2 object removal. Deleting is idempotent by nature on S3-compatible
// storage: removing an object that is already gone returns success, which is
// what makes retrying a partially failed cleanup safe.
import { presignR2Url, R2Config } from "./r2.ts";

export async function deleteR2Object(
  config: R2Config,
  key: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  try {
    const url = await presignR2Url({
      config,
      method: "DELETE",
      key,
      expiresInSeconds: 300,
    });
    const response = await fetch(url, { method: "DELETE" });
    // 204 is a delete; 404 means it was already gone, which is still success
    // for our purposes -- the object is not there, which is the goal.
    if (response.status === 204 || response.status === 404) {
      return { ok: true, status: response.status };
    }
    return {
      ok: false,
      status: response.status,
      error: `R2 delete returned ${response.status}`,
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}
