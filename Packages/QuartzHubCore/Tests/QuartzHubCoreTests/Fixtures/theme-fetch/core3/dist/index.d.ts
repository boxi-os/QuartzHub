declare function slugify(s: string): string;
declare function resolveTheme(spec: string, opts?: Record<string, unknown>): Promise<unknown>;
export { resolveTheme, slugify };
