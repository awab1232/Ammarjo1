/**
 * Resolves any image/asset reference to a fully-qualified public URL.
 *
 * Behaviour:
 *   * Absolute URLs (`http://…`, `https://…`, `data:…`) are returned unchanged.
 *   * Empty / nullish values return an empty string.
 *   * Relative paths are prefixed with `PUBLIC_BASE_URL` (env var) so that
 *     production clients never see internal dev origins in relative-path
 *     resolution.
 *
 * `PUBLIC_BASE_URL` is expected to be the HTTPS origin of this backend
 * (no trailing slash), e.g. `https://api.ammarjo.org`.
 */
export function resolvePublicUrl(raw: string | null | undefined): string {
  if (raw == null) return '';
  const value = String(raw).trim();
  if (value === '') return '';

  // Already absolute (http, https, data, blob) — pass through untouched.
  if (/^(?:https?:|data:|blob:)/i.test(value)) return value;

  const base = (process.env.PUBLIC_BASE_URL ?? '').trim().replace(/\/+$/, '');
  if (base === '') {
    // No public base configured — return the relative path as-is so the
    // client can decide what to do with it.
    return value;
  }

  return `${base}/${value.replace(/^\/+/, '')}`;
}
