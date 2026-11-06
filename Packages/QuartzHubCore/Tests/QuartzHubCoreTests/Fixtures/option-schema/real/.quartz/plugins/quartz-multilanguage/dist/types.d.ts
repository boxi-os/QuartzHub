export { BuildCtx, CSSResource, ChangeEvent, FilePath, FullSlug, JSResource, ProcessedContent, QuartzComponent, QuartzComponentConstructor, QuartzComponentProps, QuartzEmitterPlugin, QuartzFilterPlugin, QuartzPluginData, QuartzTransformerPlugin, StaticResources } from '@quartz-community/types';

/** How the language of a page is determined. Strategies are tried in the configured order. */
type DetectionStrategy = "folder" | "suffix" | "frontmatter";
/** How translations of the same page are matched. Strategies are tried in the configured order. */
type LinkingStrategy = "frontmatter" | "aliases" | "path";
interface LanguageConfig {
    /** Language code used in folder names, file suffixes and frontmatter, e.g. `de`. */
    code: string;
    /** Display name, e.g. `German`. Defaults to the upper-cased code. */
    label?: string;
    /** Name in the language itself, e.g. `Deutsch`. Defaults to `label`. */
    native?: string;
    /** BCP 47 locale used for `<html lang>`, `hreflang` and `og:locale`, e.g. `de-DE`. Defaults to `code`. */
    locale?: string;
    /** Slug of the language's home page, e.g. `de/index`. Defaults to `<code>/index` or `index`. */
    home?: string;
    /** Flag or icon shown for `switcher.style: flags`. Defaults to an emoji flag derived from `locale`. */
    flag?: string;
}
interface SeoOptions {
    /** Emit `<link rel="alternate" hreflang>` for every translation. Requires `baseUrl`. Defaults to `true`. */
    hreflang?: boolean;
    /** Emit `og:locale` and `og:locale:alternate`. Defaults to `true`. */
    ogLocale?: boolean;
    /** Which page the `x-default` alternate points to: `default` (the default language), a language code, or `none`. */
    xDefault?: string;
}
interface SwitcherOptions {
    /** `links` (inline text links), `dropdown` (`<details>` menu) or `flags`. Defaults to `links`. */
    style?: "links" | "dropdown" | "flags";
    /** What each entry shows: `code`, `label`, `native` or `translatedTitle`. Defaults to `label`. */
    label?: "code" | "label" | "native" | "translatedTitle";
    /** Show the current language as a non-link entry. Defaults to `true`. */
    showCurrent?: boolean;
    /** Languages without a translation: `hide`, link to their `home`, or show as `disabled`. Defaults to `home`. */
    missing?: "hide" | "home" | "disabled";
    /** Text between entries in `links` style. Defaults to `|`. */
    separator?: string;
    /** Accessible name of the switcher. Defaults to the plugin's translated "Language". */
    title?: string;
}
interface FrontmatterKeys {
    /** Frontmatter key holding the page language. Defaults to `lang`. */
    lang?: string;
    /** Frontmatter key shared by all translations of a page. Defaults to `translationKey`. */
    key?: string;
    /** Frontmatter key mapping language codes to slugs. Defaults to `translations`. */
    translations?: string;
}
interface MultilanguageOptions {
    /** Languages of the site. Strings are treated as codes. */
    languages?: (LanguageConfig | string)[];
    /** Language of pages that match no detection strategy. Defaults to the first language. */
    defaultLanguage?: string;
    /** Detection strategies in priority order. Defaults to `[folder, suffix, frontmatter]`. */
    detection?: DetectionStrategy[];
    /** Linking strategies in priority order. Defaults to `[frontmatter, aliases, path]`. */
    linking?: LinkingStrategy[];
    frontmatterKeys?: FrontmatterKeys;
    /** Redirect `/` to a language home: `none`, `default` or `browser` (browser language, remembered choice first). */
    rootRedirect?: "none" | "default" | "browser";
    /** Remember the visitor's explicit language choice in `localStorage`. Defaults to `true`. */
    rememberChoice?: boolean;
    seo?: SeoOptions;
    switcher?: SwitcherOptions;
    /** Show a notice on pages that have no translation in the visitor's language. Defaults to `false`. */
    missingTranslationNotice?: boolean;
    /** Show a notice with a link when a translation in the visitor's language exists. Defaults to `false`. */
    availableTranslationNotice?: boolean;
    /** Emit redirect pages for missing translations (`de/foo` → `en/foo`). Defaults to `none`. */
    fallbackPages?: "none" | "redirect";
    /** Rewrite links that point to another language's page when a same-language page exists. Defaults to `false`. */
    rewriteCrossLanguageLinks?: boolean;
    /** Re-format `<time datetime>` elements client-side in the page language. Defaults to `false`. */
    localizeDates?: boolean;
    /** Only publish these languages (empty = all). `QUARTZ_LANGS=de,en` overrides at build time. */
    publishLanguages?: string[];
}
interface ResolvedLanguage {
    code: string;
    label: string;
    native: string;
    locale: string;
    home?: string;
    flag: string;
}
interface ResolvedOptions {
    languages: ResolvedLanguage[];
    /** Languages that are published: `languages` restricted by `publishLanguages` (all when empty). */
    activeLanguages: ResolvedLanguage[];
    defaultLanguage: string;
    detection: DetectionStrategy[];
    linking: LinkingStrategy[];
    frontmatterKeys: Required<FrontmatterKeys>;
    rootRedirect: "none" | "default" | "browser";
    rememberChoice: boolean;
    seo: Required<SeoOptions>;
    switcher: Required<Omit<SwitcherOptions, "title">> & {
        title?: string;
    };
    missingTranslationNotice: boolean;
    availableTranslationNotice: boolean;
    fallbackPages: "none" | "redirect";
    rewriteCrossLanguageLinks: boolean;
    localizeDates: boolean;
    publishLanguages: string[];
}
/** Language code → full slug of the translation (includes the page itself). */
type TranslationMap = Record<string, string>;
/** What the transformer stores in `file.data.multilanguage`. */
interface MultilanguageFileData {
    lang: string;
    /** Slug with the language folder or suffix removed; equal for path-linked translations. */
    baseSlug: string;
    source: DetectionStrategy | "default";
    translationKey?: string;
    translations?: Record<string, string>;
}
declare module "vfile" {
    interface DataMap {
        multilanguage?: MultilanguageFileData;
    }
}

export type { DetectionStrategy, FrontmatterKeys, LanguageConfig, LinkingStrategy, MultilanguageFileData, MultilanguageOptions, ResolvedLanguage, ResolvedOptions, SeoOptions, SwitcherOptions, TranslationMap };
