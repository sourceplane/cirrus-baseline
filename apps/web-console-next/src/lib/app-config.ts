// Instance identity for the web console (saas-bootstrap-factory BF3 seam).
//
// Branding strings, deployment hostnames, contact addresses, and storage-key
// namespaces live here so a new instance of the starter retargets one file.
// Do not add behavior — values and trivial derivations only.
//
// RUNTIME, NOT BUILD (saas-console-artifact CA1). Every value below can be
// overridden per request by the Worker's `vars` (wrangler.jsonc), which the
// OpenNext runtime copies into `process.env`. So one build of the console can
// serve any product and any environment: the root layout resolves the config
// on the server and hands it to the client through <AppConfigProvider>. The
// literals here are the fallback — what a deploy with no `vars` gets — and are
// what the rebrand rewrites, so they stay this tree's own identity.

export interface AppConfig {
  /** Product/brand name shown across the console. */
  productName: string;
  /** Marketing-facing product description (document metadata). */
  productDescription: string;
  /** The Cloudflare account's workers.dev subdomain serving this instance. */
  workersDevSubdomain: string;
  /** api-edge worker name without its `-<env>` suffix. */
  apiWorkerPrefix: string;
  /** Namespace prefix for console localStorage keys. */
  storagePrefix: string;
  /** Sales contact surfaced by the billing upgrade UX. */
  salesEmail: string;
  /** The single environment this deploy serves; unset offers every target. */
  deployEnv: string | undefined;
}

// `process.env.NEXT_PUBLIC_DEPLOY_ENV` is inlined at build time and must stay
// verbatim. The local declaration lets the node-types-free test compiler type
// this file; it shadows harmlessly under the app build.
declare const process: { env: Record<string, string | undefined> } | undefined;

const BUILD_DEPLOY_ENV: string | undefined =
  typeof process !== "undefined" ? process.env.NEXT_PUBLIC_DEPLOY_ENV || undefined : undefined;

/** This tree's own identity: what a deploy with no runtime `vars` serves. */
export const DEFAULT_APP_CONFIG: AppConfig = {
  productName: "cirrus-baseline",
  productDescription: "Next-gen control plane for your projects, environments, and entitlements.",
  workersDevSubdomain: "rahulvarghesepullely",
  apiWorkerPrefix: "cirrus-baseline-api-edge",
  storagePrefix: "cirrus-baseline.next",
  salesEmail: "sales@sourceplane.ai",
  deployEnv: BUILD_DEPLOY_ENV,
};

/** The Worker `vars` that override each field at runtime. */
export const RUNTIME_KEYS: Record<keyof AppConfig, string> = {
  productName: "CONSOLE_PRODUCT_NAME",
  productDescription: "CONSOLE_PRODUCT_DESCRIPTION",
  workersDevSubdomain: "CONSOLE_WORKERS_DEV_SUBDOMAIN",
  apiWorkerPrefix: "CONSOLE_API_WORKER_PREFIX",
  storagePrefix: "CONSOLE_STORAGE_PREFIX",
  salesEmail: "CONSOLE_SALES_EMAIL",
  deployEnv: "CONSOLE_DEPLOY_ENV",
};

/**
 * The config for one request: each field from its runtime var when that is a
 * non-empty string, else the default. Pure, so it is unit-testable.
 */
export function resolveAppConfig(
  env: Record<string, string | undefined>,
  defaults: AppConfig = DEFAULT_APP_CONFIG,
): AppConfig {
  const pick = (key: keyof AppConfig): string | undefined => {
    const value = env[RUNTIME_KEYS[key]];
    return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
  };
  return {
    productName: pick("productName") ?? defaults.productName,
    productDescription: pick("productDescription") ?? defaults.productDescription,
    workersDevSubdomain: pick("workersDevSubdomain") ?? defaults.workersDevSubdomain,
    apiWorkerPrefix: pick("apiWorkerPrefix") ?? defaults.apiWorkerPrefix,
    storagePrefix: pick("storagePrefix") ?? defaults.storagePrefix,
    salesEmail: pick("salesEmail") ?? defaults.salesEmail,
    deployEnv: pick("deployEnv") ?? defaults.deployEnv,
  };
}

let current: AppConfig = DEFAULT_APP_CONFIG;

/**
 * The config in force. On the server it is resolved from the request's
 * environment on every call, so a server component never depends on the root
 * layout having rendered first. In the browser it is what <Providers> installed
 * from the layout's resolution.
 */
export function appConfig(): AppConfig {
  if (typeof window === "undefined" && typeof process !== "undefined") {
    return resolveAppConfig(process.env);
  }
  return current;
}

/** Install the resolved config in the browser. Idempotent; called by <Providers> on render. */
export function setAppConfig(config: AppConfig): void {
  current = config;
}

/** Browser/document title of the console. */
export function consoleTitle(config: AppConfig = appConfig()): string {
  return `${config.productName} Console`;
}

/** api-edge workers.dev URL for a given environment name. */
export function apiEdgeWorkersDevUrl(environment: string, config: AppConfig = appConfig()): string {
  return `https://${config.apiWorkerPrefix}-${environment}.${config.workersDevSubdomain}.workers.dev`;
}
