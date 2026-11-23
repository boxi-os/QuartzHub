declare function slugify(s: string): string;
declare function resolveTheme(spec: string, opts?: Record<string, unknown>): Promise<unknown>;
declare function resolveSnippet(spec: string, opts?: Record<string, unknown>): Promise<string>;
declare function parseStyleSettings(css: string): { sections: unknown[]; errors: string[] };
export { parseStyleSettings, resolveSnippet, resolveTheme, slugify };
