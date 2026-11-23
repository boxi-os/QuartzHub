// Stand-in for @quartz-themes/core 3 (ThemeFetchTests): resolveTheme answers like core and puts
// what it was called with into `source`, so the test sees spec, cwd and options. Writes into the
// cache folder as core does. Never touches the network.
import fs from "node:fs";
import path from "node:path";

export async function resolveTheme(spec, opts = {}) {
  if (spec === "Minmal")
    throw new Error('theme "Minmal" is not in Obsidian\'s community theme registry. Did you mean: "Minimal", "Mia", "Mimir"?');
  let fetchFailed = null;
  if (opts.fetch) {
    try {
      await opts.fetch("https://example.invalid/theme.css");
      fetchFailed = false;
    } catch {
      fetchFailed = true;
    }
  }
  const cacheDir = opts.cacheDir ?? path.resolve(".quartz-cache/quartz-themes");
  fs.mkdirSync(cacheDir, { recursive: true });
  fs.writeFileSync(path.join(cacheDir, "stand-in.theme.css"), "body{}");
  return {
    name: spec,
    css: "body{color:red}",
    modes: spec === "Void" ? ["dark"] : undefined,
    styleSettings: spec.includes(".") ? { "theme-settings@@variant": "frappe" } : undefined,
    source: JSON.stringify({ spec, cwd: process.cwd(), cacheDir: opts.cacheDir ?? null, cacheTtl: opts.cacheTtl, version: opts.version ?? null, fetchFailed }),
    version: opts.version,
  };
}

// As core: a URL through the cache with `opts.fetch`, anything else a file relative to the cwd.
export async function resolveSnippet(spec, opts = {}) {
  if (/^https?:\/\//.test(spec)) {
    const response = await (opts.fetch ?? fetch)(spec);
    return await response.text();
  }
  return fs.readFileSync(path.resolve(spec), "utf8");
}

// Not core's parser: one section that shows the text it was given, so the test sees what went in.
export function parseStyleSettings(css) {
  if (css.includes("broken"))
    return { sections: [], errors: ["bad indentation of a mapping entry (3:5)"] };
  return { sections: [{ id: "seen", settings: [{ id: "text", type: "info-text", title: css }] }], errors: [] };
}
