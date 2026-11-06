import { ComponentChild } from 'preact';
export { BuildCtx, FilePath, FullSlug, GlobalConfiguration, PageGenerator, PageMatcher, ProcessedContent, QuartzComponent, QuartzComponentConstructor, QuartzComponentProps, QuartzPageTypePlugin, QuartzPageTypePluginInstance, QuartzPluginData, VirtualPage } from '@quartz-community/types';

/** Props passed to every view renderer */
interface ViewRendererProps {
    entries: BasesEntry[];
    view: BasesView;
    basesData: BasesData;
    total: number;
    locale: string;
    /** Slug of the page rendering this view (for resolving relative paths) */
    slug: string;
    /** All known slugs in the site (for `transformLink` with `shortest` strategy) */
    allSlugs: string[];
    /** Link resolution strategy ("absolute" | "relative" | "shortest"). Passed from plugin options. */
    linkResolution: "absolute" | "relative" | "shortest";
    /** Plugin-level options from the view type registration, if any. */
    options?: Record<string, unknown>;
    /** Entries shown before "Show more" (per group); 0 or undefined shows all. */
    showMore?: number;
}
/** View renderer function signature */
type ViewRenderer = (props: ViewRendererProps) => ComponentChild;
/** Registration record for a view type */
interface ViewTypeRegistration {
    /** Unique view type identifier, e.g. "table", "board", "my-custom-view" */
    id: string;
    /** Human-readable display name shown in the view selector */
    name: string;
    /** Optional Lucide icon name */
    icon?: string;
    /** The render function producing Preact JSX */
    render: ViewRenderer;
    /**
     * Optional CSS string injected once per page when this view type is active.
     * Deduplicated by view type ID — only injected once even if multiple views
     * of the same type appear on the page.
     */
    css?: string;
    /**
     * Optional client-side script injected once per page when this view type is
     * active. Runs after the DOM is loaded, following the same lifecycle as
     * `QuartzComponent.afterDOMLoaded`. Deduplicated by view type ID.
     */
    afterDOMLoaded?: string;
    /**
     * Optional user-supplied configuration for this view type. Community plugins
     * can use this to accept plugin-level options (e.g. feature flags, CDN URLs)
     * that are set once at registration time and passed through to every render
     * invocation via `ViewRendererProps.options`.
     */
    options?: Record<string, unknown>;
}
/** Plugin options for BasesPage */
interface BasesPageOptions {
    /** Default view type when none specified. Default: "table" */
    defaultViewType?: string;
    /**
     * Custom view renderers passed via TS config override.
     * Keys are view type IDs. These are registered into the ViewRegistry
     * at plugin init time, alongside (or overriding) built-in views.
     */
    customViews?: Record<string, ViewRenderer>;
    /**
     * How to resolve internal links in view renderers. Should match the
     * `markdownLinkResolution` setting of the crawl-links plugin.
     * Default: "shortest"
     */
    linkResolution?: "absolute" | "relative" | "shortest";
    /**
     * Whether pages Quartz generates without a source file - folder pages, tag pages,
     * the pages of `.base` and `.canvas` files - can be entries of a base. Obsidian
     * does not know them, so a filter like `file.folder == "x"` would list a folder
     * page that does not exist in the vault. Default: false
     */
    includeVirtualPages?: boolean;
    /**
     * Whether the page Quartz generates for each `.base` file shows up where pages are listed:
     * search, graph, explorer, `contentIndex.json`, `sitemap.xml`, the RSS feed, backlinks, recent
     * notes, folder and tag pages. Off, the page is marked `unlisted` and stays reachable by its URL
     * and by links; embedding a base never needs it. Obsidian has no such page. Default: false
     */
    listBasePages?: boolean;
    /**
     * Cooperation with quartz-multilanguage. `auto` lists only entries in the language of the page
     * the base is on (entries without a translation in it are left out), `all` ignores languages,
     * a language code (`de`) always lists that language. Entries in no language are listed
     * everywhere. Without quartz-multilanguage it changes nothing. Default: "auto"
     */
    language?: string;
    /**
     * A search field above each view of a base, filtering its entries in the browser by the text
     * they show. `auto` shows it from 8 entries on, `always` and `never` do what they say. Only the
     * entries the page contains are searched: what a view's `limit` cuts off is not. Default: "auto"
     */
    search?: "auto" | "always" | "never";
    /**
     * How many entries a view shows before a "Show more" button (in a grouped view: each group).
     * The rest is on the page and found by the search and a sort; the button shows it, then "Show
     * less" folds it again. Summaries and counts take every entry. Obsidian has no such limit (its
     * views scroll); `0` shows everything, as there. Default: 50
     */
    showMore?: number;
    /**
     * How a list of tags is shown (`file.tags`, the `tags` property): `lower` (`#gross/klein`, what
     * Quartz hands over), `upper` (`#GROSS/KLEIN`) or `capitalize` (`#Gross/Klein`, every part after
     * `/`, `-`, `_` or a space). Display only: the values formulas see stay lowercase, so this never
     * changes what a filter finds. Quartz lowercases tags before the plugin sees them, so the
     * spelling in the vault is not available. Default: "lower"
     */
    tagCase?: "lower" | "upper" | "capitalize";
}
/** Sort direction */
type SortDirection = "ASC" | "DESC";
/** Sort entry — one column + direction pair */
interface SortEntry {
    property: string;
    direction?: SortDirection;
}
/** Filter tree node — recursive and/or/not structure matching Obsidian spec */
type FilterNode = string | {
    and: FilterNode[];
} | {
    or: FilterNode[];
} | {
    not: FilterNode[];
};
/** Group-by configuration */
interface GroupBy {
    property: string;
    direction?: SortDirection;
}
/** Summary type — built-in aggregation functions + extensible string for custom */
type SummaryType = "Count" | "Average" | "Min" | "Max" | "Sum" | "Range" | "Median" | "Stddev" | "Earliest" | "Latest" | "Checked" | "Unchecked" | "Empty" | "Filled" | "Unique" | string;
/** Property display configuration */
interface PropertyConfig {
    displayName?: string;
}
/** View definition from .base file YAML — matches full Obsidian spec */
interface BasesView {
    /** View type identifier */
    type: string;
    /** Display name for this view (shown in view selector tab) */
    name?: string;
    /** Maximum number of entries to display */
    limit?: number;
    /** Group entries by a property */
    groupBy?: GroupBy;
    /** View-specific filters (merged with global filters at resolve time) */
    filters?: FilterNode;
    /** Sort order — list of property paths in priority order */
    order?: string[];
    /** Multi-key sort with explicit direction per column */
    sort?: SortEntry[];
    /** Per-property summary aggregations */
    summaries?: Record<string, SummaryType>;
    /** Column widths in pixels, keyed by property path */
    columnSize?: Record<string, number>;
    /** Row height in pixels */
    rowHeight?: number;
    /** Property name containing the image URL/path */
    image?: string;
    /** Card width (unitless ratio or pixels depending on renderer) */
    cardSize?: number;
    /** Image aspect ratio as height per width, like Obsidian (1 = square, 1.25 = taller). */
    imageAspectRatio?: number;
    /** Image fit mode: "cover" (crop to fill) or "contain" (scale to fit). Default: "cover". */
    imageFit?: "cover" | "contain";
    /**
     * @deprecated Use imageAspectRatio instead. Kept for backwards compatibility.
     */
    cardAspect?: number;
    /** Property path for the date field */
    date?: string;
    /** Alias for date */
    dateField?: string;
    /** Alias for date */
    dateProperty?: string;
    /** Marker before each entry: "bullet" (default), "number" or "none". */
    markers?: "bullet" | "number" | "none";
    /** Text between the properties of an entry, unless they are indented. Default: ", " */
    separator?: string;
    /** Properties as an indented block below the entry, each with a bullet. */
    indentProperties?: boolean;
    /** Property to group board columns by (if not using groupBy) */
    boardProperty?: string;
    /** Escape hatch for future/unknown view-specific fields */
    [key: string]: unknown;
}
/** Parsed .base file data — top-level YAML structure */
interface BasesData {
    /** Global filters applied to all views */
    filters?: FilterNode;
    /** Formula definitions — keys are formula names, values are expressions */
    formulas?: Record<string, string>;
    /** Property display configuration */
    properties?: Record<string, PropertyConfig>;
    /** Global summary configuration */
    summaries?: Record<string, string>;
    /** View definitions — each entry defines one tab/view */
    views?: BasesView[];
}
/** Resolved entry — a single note that matched the base query */
interface BasesEntry {
    /** The note's slug (URL path) */
    slug: string;
    /** Display title */
    title: string;
    /** All frontmatter properties (raw) */
    properties: Record<string, unknown>;
    /** File metadata properties */
    fileProperties: {
        name: string;
        basename: string;
        path: string;
        folder: string;
        ext: string;
        tags: string[];
        links: string[];
        /** Notes that link here, as links (`[[path|name]]`), in path order. */
        backlinks?: string[];
        embeds?: string[];
        created?: string | Date;
        modified?: string | Date;
        ctime?: Date;
        mtime?: Date;
        size?: number;
        /** Language code from quartz-multilanguage (`de`); Obsidian has no such property. */
        lang?: string;
    };
    /** Computed formula values; a formula that failed has none here, but an entry in formulaErrors. */
    formulaValues: Record<string, unknown>;
    /** The message of each formula that failed, shown in its cell as Obsidian shows it. */
    formulaErrors?: Record<string, string>;
}

export type { BasesData, BasesEntry, BasesPageOptions, BasesView, FilterNode, GroupBy, PropertyConfig, SortDirection, SortEntry, SummaryType, ViewRenderer, ViewRendererProps, ViewTypeRegistration };
