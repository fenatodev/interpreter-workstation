const DEFAULT_REDACTED_VALUE = '[REDACTED]';

const BINARY_FIELD_NAMES = new Set([
  'blob',
  'data',
  'base64',
  'imageData',
  'audioData',
]);

/**
 * Redact credential-shaped substrings while preserving surrounding text.
 *
 * This intentionally does not redact filesystem paths or ordinary identifiers.
 * It is safe to apply to model-visible tool text, diagnostics, window titles,
 * URLs, and structured metadata.
 */
export function redactSensitiveText(
  text: string,
  replacement = DEFAULT_REDACTED_VALUE,
): string {
  let redacted = text;

  redacted = redacted.replace(
    /((?:["'`]?)(?:api[_-]?key|x-api-key|access[_-]?token|refresh[_-]?token|auth[_-]?token|oauth[_-]?token|authorization|client[_-]?secret|session[_-]?token|password|secret|experimental[_-]?bearer[_-]?token|bearer[_-]?token|jwt)(?:["'`]?)\s*[:=]\s*)(["'`]?)[^"'`,\s}\]]+\2/gi,
    (_match, prefix: string, quote: string) => `${prefix}${quote}${replacement}${quote}`,
  );

  redacted = redacted.replace(
    /\bBearer\s+[A-Za-z0-9._~+/=-]+\b/gi,
    `Bearer ${replacement}`,
  );
  redacted = redacted.replace(/\bsk-ant-[A-Za-z0-9_-]+\b/g, replacement);
  redacted = redacted.replace(/\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b/g, replacement);

  // Some desktop titles/file names normalize or visually separate an sk-style
  // credential as "sk <token>" or "sk_<token>". Keep the threshold long enough
  // to avoid redacting ordinary prose such as "sk test".
  redacted = redacted.replace(
    /\bsk(?:[ _]+)(?:proj[ _-]+)?[A-Za-z0-9_-]{20,}\b/gi,
    replacement,
  );

  redacted = redacted.replace(
    /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+\b/g,
    replacement,
  );
  redacted = redacted.replace(
    /([?&](?:access_token|refresh_token|api_key|apikey|token)=)[^&\s]+/gi,
    `$1${replacement}`,
  );

  return redacted;
}

/**
 * Recursively redact model-visible structured values while leaving binary
 * payload fields untouched.
 */
export function redactSensitiveValue<T>(value: T, parentKey?: string): T {
  if (typeof value === 'string') {
    if (parentKey && BINARY_FIELD_NAMES.has(parentKey)) {
      return value;
    }
    return redactSensitiveText(value) as T;
  }

  if (Array.isArray(value)) {
    return value.map((entry) => redactSensitiveValue(entry)) as T;
  }

  if (!value || typeof value !== 'object') {
    return value;
  }

  const output: Record<string, unknown> = {};
  for (const [key, nestedValue] of Object.entries(value as Record<string, unknown>)) {
    output[key] = redactSensitiveValue(nestedValue, key);
  }
  return output as T;
}
