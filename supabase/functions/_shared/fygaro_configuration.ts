import {
  type FygaroCheckoutConfig,
  fygaroPaymentConfigFromEnv,
  type FygaroWebhookConfig,
  fygaroWebhookConfigFromEnv,
} from "./fygaro.ts";

type ConfigClient = {
  rpc: (name: string) => PromiseLike<{ data: unknown; error: unknown }>;
};
export type PaymentConfiguration = {
  enabled: boolean;
  checkout: FygaroCheckoutConfig | null;
  webhook: FygaroWebhookConfig;
};

/** Vault takes precedence, including an explicit pause; database failures fail closed. */
export async function loadFygaroConfiguration(
  client: ConfigClient,
): Promise<PaymentConfiguration> {
  const { data, error } = await client.rpc("fygaro_runtime_configuration");
  if (error) throw new Error("Payment configuration could not be loaded.");
  if (data == null) {
    const webhook = fygaroWebhookConfigFromEnv();
    return { enabled: true, checkout: fygaroPaymentConfigFromEnv(), webhook };
  }
  return parseFygaroConfiguration(data);
}

export function parseFygaroConfiguration(
  data: unknown,
  now = Date.now(),
): PaymentConfiguration {
  const row = data as {
    enabled?: unknown;
    credentials?: Record<string, unknown>;
  };
  const value = row?.credentials;
  if (!value || typeof value !== "object") {
    throw new Error("Payment credentials are not configured.");
  }
  const text = (key: string) =>
    typeof value[key] === "string" ? (value[key] as string).trim() : "";
  const hookId = text("webhook_key_id"),
    hookSecret = text("webhook_secret_key");
  if (!hookId || !hookSecret) {
    throw new Error("Payment webhook verification is not configured.");
  }
  const secrets: Record<string, string> = { [hookId]: hookSecret };
  if (
    text("previous_webhook_key_id") && text("previous_webhook_secret_key") &&
    Date.parse(text("previous_webhook_expires_at")) > now
  ) {
    secrets[text("previous_webhook_key_id")] = text(
      "previous_webhook_secret_key",
    );
  }
  const enabled = row.enabled === true;
  const checkout = enabled
    ? {
      buttonUrl: text("button_url"),
      keyId: text("key_id"),
      secret: text("secret_key"),
    }
    : null;
  if (
    checkout && (!checkout.buttonUrl || !checkout.keyId || !checkout.secret)
  ) throw new Error("Payment checkout is not configured.");
  return { enabled, checkout, webhook: { secrets } };
}

export async function requireFygaroCheckout(
  client: ConfigClient,
): Promise<FygaroCheckoutConfig> {
  const config = await loadFygaroConfiguration(client);
  if (!config.enabled || !config.checkout) {
    throw new Error("Subscription checkout is not configured or is paused.");
  }
  return config.checkout;
}
