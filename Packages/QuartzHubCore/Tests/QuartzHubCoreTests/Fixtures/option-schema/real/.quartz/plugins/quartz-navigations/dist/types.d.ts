export { BuildCtx, FullSlug, GlobalConfiguration, QuartzComponent, QuartzComponentConstructor, QuartzComponentProps, QuartzPluginData } from '@quartz-community/types';

type NavVariant = "tree" | "bar" | "accordion" | "dropdown" | "flyout" | "tabs" | "mega" | "columns" | "select" | "pager";
type NavMobile = "same" | "accordion" | "offcanvas" | "select" | "hidden";
type NavScope = "root" | "section" | "parent" | "current";
type NavSort = "manual" | "alphabetical" | "date";
type NavSortDirection = "asc" | "desc";
type NavFoldersFirst = "first" | "last" | "mixed";
type NavDateField = "created" | "modified" | "published";
type NavIndexEntry = "none" | "first";
type NavFolderLink = "index" | "none" | "first-child";
type NavFolderClick = "link" | "toggle";
type NavFolderState = "collapsed" | "open";
type NavTrigger = "click" | "hover";
type NavPagerOrder = "tree" | "siblings";
/** Which icons a row shows: none, folder/file glyphs, custom `navIcon` values, or both. */
type NavIcons = "none" | "type" | "custom" | "both";
/** Alignment of the horizontal variants' top row; `full` spreads the entries over the width. */
type NavAlign = "left" | "center" | "right" | "full";
/** Side the flyout panels open to; `auto` picks it from the navigation's position on the page. */
type NavFlyoutSide = "auto" | "right" | "left";
interface NavigationFrontmatterKeys {
    /** Numeric sort key of a page or folder index. Defaults to `navOrder`. */
    order?: string;
    /** Title shown in the navigation instead of the page title. Defaults to `navTitle`. */
    title?: string;
    /** `true` hides the page, or the folder when set on its index page. Defaults to `navHide`. */
    hide?: string;
    /**
     * Icon rendered before the title when `icons` is on: short text, an emoji or a Lucide icon
     * as `lucide:<name>` (e.g. `lucide:book-open`). Defaults to `navIcon`.
     */
    icon?: string;
}
/** Lucide icon names for the plugin's own symbols. */
interface NavigationIconNames {
    /** Closed folder. Defaults to `folder`. */
    folder?: string;
    /** Open folder. Defaults to `folder-open`. */
    folderOpen?: string;
    /** Page. Defaults to `file`. */
    file?: string;
    /** The `showHome` entry. Defaults to `house`. */
    home?: string;
    /** Folder toggle. Defaults to `chevron-down`. */
    chevron?: string;
    /** Off-canvas burger. Defaults to `menu`. */
    menu?: string;
    /** Off-canvas close button. Defaults to `x`. */
    close?: string;
    /** Pager "Previous". Defaults to `chevron-left`. */
    previous?: string;
    /** Pager "Next". Defaults to `chevron-right`. */
    next?: string;
}
interface NavigationBreakpoints {
    /** Mobile breakpoint, e.g. `800px`. Defaults to the value in `quartz/styles/variables.scss`. */
    mobile?: string;
    /** Desktop breakpoint, e.g. `1200px`. Defaults to the value in `quartz/styles/variables.scss`. */
    desktop?: string;
}
interface NavigationOptions {
    /**
     * Cooperation with quartz-multilanguage. `auto` shows the tree of the current page's language,
     * with paths (`rootPath`, `order`, `nodeIcons`, `include`, `exclude`) written without the
     * language folder or suffix; without quartz-multilanguage it changes nothing. `all` ignores
     * languages. A language code (`de`) always shows that language. Defaults to `auto`.
     */
    language?: string;
    /** Presentation; each variant implies its orientation. Defaults to `tree`. */
    variant?: NavVariant;
    /** Presentation below the mobile breakpoint. Defaults to `same`. */
    mobile?: NavMobile;
    /** Alignment of `bar`, `dropdown`, `mega` and `tabs`. Defaults to `left`. */
    align?: NavAlign;
    /** Extra class names on the root element. Defaults to none. */
    className?: string;
    /** Stable instance id used for `localStorage` and element ids. Defaults to a hash of the options. */
    id?: string;
    /** Heading rendered above the navigation. Defaults to none. */
    title?: string;
    /** Accessible name of the `<nav>`. Defaults to a translated "Main navigation". */
    ariaLabel?: string;
    /** Render chevrons on collapsible folders. Defaults to `true`. */
    chevrons?: boolean;
    /**
     * Row icons: `type` draws folder and file glyphs, `custom` the `navIcon` frontmatter value
     * (and `nodeIcons`), `both` draws the custom icon where one is set and the type glyph
     * elsewhere, `none` draws nothing. `true` / `false` mean `both` / `none`. Defaults to `both`.
     */
    icons?: NavIcons | boolean;
    /** Lucide icons for folders, files, the home entry, chevrons, burger, close and pager arrows. */
    iconNames?: NavigationIconNames;
    /**
     * Icons per path from the site config, e.g. `{ docs: "lucide:book-open", "docs/api": "🧩" }`.
     * Same syntax as `navIcon` (`lucide:<name>`, text, emoji, or `none`); frontmatter wins.
     */
    nodeIcons?: Record<string, string>;
    /** Folder the navigation starts at, e.g. `docs`. Defaults to the site root. */
    rootPath?: string;
    /** Which subtree to show relative to the current page. Defaults to `root`. */
    scope?: NavScope;
    /** Number of levels below the scope root; `0` means unlimited. Defaults to `0`. */
    depth?: number;
    /** Render nothing on pages outside `rootPath`. Defaults to `true`. */
    hideOutsideRoot?: boolean;
    /** Render the scope root as a linked heading above the list. Defaults to `false`. */
    showScopeRoot?: boolean;
    /** Prepend a link to the index page of `rootPath`. Defaults to `false`. */
    showHome?: boolean;
    /** Add the folder index page as the first child of an expanded folder. Defaults to `none`. */
    indexEntry?: NavIndexEntry;
    /** Sort mode. Defaults to `manual` (order map, `navOrder`, numeric prefix, title). */
    sort?: NavSort;
    /** Sort direction. Defaults to `asc`. */
    sortDirection?: NavSortDirection;
    /** Where folders go relative to pages. Defaults to `first`. */
    foldersFirst?: NavFoldersFirst;
    /** Date used by `sort: date`. Defaults to `created`. */
    dateField?: NavDateField;
    /** Explicit child order per folder path, e.g. `{ "": ["docs", "blog"], docs: ["intro"] }`. */
    order?: Record<string, string[]>;
    /** Remove a numeric prefix such as `01-` from titles taken from file names. Defaults to `false`. */
    stripNumericPrefix?: boolean;
    /** Frontmatter keys read by the plugin. */
    frontmatterKeys?: NavigationFrontmatterKeys;
    /** Hide the `tags` folder. Defaults to `true`. */
    hideTags?: boolean;
    /** Hide pages marked `unlisted`. Defaults to `true`. */
    hideUnlisted?: boolean;
    /** Hide pages with `draft: true`. Defaults to `true`. */
    hideDrafts?: boolean;
    /** Drop folders that end up without visible children. Defaults to `true`. */
    hideEmptyFolders?: boolean;
    /** Keep folders whose only content is their index page. Defaults to `true`. */
    keepIndexOnlyFolders?: boolean;
    /** Globs on slugs; when set, only matching pages and subtrees are shown. Defaults to all. */
    include?: string[];
    /** Globs on slugs to hide, e.g. `private/**`. Defaults to none. */
    exclude?: string[];
    /** Where a folder title links to. Defaults to `index`. */
    folderLink?: NavFolderLink;
    /**
     * Collapsible folders: `toggle` makes the whole row open and close the folder, `link` makes
     * the row a link with a separate toggle button at its end. Defaults to `toggle`.
     */
    folderClick?: NavFolderClick;
    /** Initial state of collapsible folders. Defaults to `collapsed`. */
    folderDefaultState?: NavFolderState;
    /** Open folders on the path to the current page. Defaults to `true`. */
    expandActive?: boolean;
    /** Only one open folder per level (`<details name>`). Defaults to `false`. */
    exclusive?: boolean;
    /** Remember open folders in `localStorage`. Defaults to `false`. */
    persistState?: boolean;
    /** How dropdown, mega and flyout panels open: on click or on hover and focus. Defaults to `click`. */
    trigger?: NavTrigger;
    /** Override the breakpoints read from `quartz/styles/variables.scss`. */
    breakpoints?: NavigationBreakpoints;
    /** Options of the `tabs` variant. */
    tabs?: {
        /** Show the children of the active tab in a second row. Defaults to `true`. */
        secondary?: boolean;
    };
    /** Options of the `flyout` variant. */
    flyout?: {
        /**
         * Side the panels open to. `auto` (default) opens to the left when the navigation sits in
         * the right half of the viewport, decided by the client script; `right` / `left` fix it.
         */
        side?: NavFlyoutSide;
    };
    /** Options of the `select` variant and of `mobile: select`. */
    select?: {
        /**
         * Show a "Go" button next to the select. Choosing an option navigates anyway (pointer
         * selection immediately, keyboard selection on Enter). Defaults to `false`.
         */
        button?: boolean;
    };
    /** Options of the `columns` variant. */
    columns?: {
        /** Maximum number of columns. Defaults to `4`. */
        max?: number;
    };
    /** Options of the `pager` variant. */
    pager?: {
        /** Show "Previous" / "Next" labels above the titles. Defaults to `true`. */
        labels?: boolean;
        /** Walk the whole tree in order or only the siblings of the current page. Defaults to `tree`. */
        order?: NavPagerOrder;
    };
}
interface ResolvedOptions {
    /** `auto`, `all` or a lower-case language code. */
    language: string;
    variant: NavVariant;
    mobile: NavMobile;
    align: NavAlign;
    className: string;
    id: string;
    title: string;
    ariaLabel: string;
    chevrons: boolean;
    icons: NavIcons;
    iconNames: Required<NavigationIconNames>;
    nodeIcons: Record<string, string>;
    rootPath: string;
    scope: NavScope;
    depth: number;
    hideOutsideRoot: boolean;
    showScopeRoot: boolean;
    showHome: boolean;
    indexEntry: NavIndexEntry;
    sort: NavSort;
    sortDirection: NavSortDirection;
    foldersFirst: NavFoldersFirst;
    dateField: NavDateField;
    order: Record<string, string[]>;
    stripNumericPrefix: boolean;
    frontmatterKeys: Required<NavigationFrontmatterKeys>;
    hideTags: boolean;
    hideUnlisted: boolean;
    hideDrafts: boolean;
    hideEmptyFolders: boolean;
    keepIndexOnlyFolders: boolean;
    include: string[];
    exclude: string[];
    folderLink: NavFolderLink;
    folderClick: NavFolderClick;
    folderDefaultState: NavFolderState;
    expandActive: boolean;
    exclusive: boolean;
    persistState: boolean;
    trigger: NavTrigger;
    breakpoints: NavigationBreakpoints;
    tabs: {
        secondary: boolean;
    };
    flyout: {
        side: NavFlyoutSide;
    };
    select: {
        button: boolean;
    };
    columns: {
        max: number;
    };
    pager: {
        labels: boolean;
        order: NavPagerOrder;
    };
}
/** One entry of the navigation tree. Folders carry the slug of their index page (`docs/index`). */
interface NavNode {
    kind: "folder" | "page";
    /** Slug the node links to (a folder's index page, or `docs/index` when it has none). */
    slug: string;
    /** Language-neutral path: `docs/setup`, `docs` for a folder, `` for the root. */
    path: string;
    /** Last slug segment; empty for the site root. */
    segment: string;
    title: string;
    parentSlug?: string;
    /** `0` for the site root. */
    depth: number;
    children: NavNode[];
    /** Folder: an index page exists (real or generated by the folder-page plugin). */
    hasIndex: boolean;
    /** Folder: the index page is generated, there is no `index.md`. */
    isVirtual: boolean;
    order?: number;
    listOrder?: number;
    prefixOrder?: number;
    date?: Date;
    /** Custom icon from `navIcon` or `nodeIcons`: `lucide:<name>`, text, emoji, or `none`. */
    icon?: string;
}
interface NavTree {
    root: NavNode;
    bySlug: Map<string, NavNode>;
    /** Folders by language-neutral path. */
    folders: Map<string, NavNode>;
    /** Language of the tree when it was built for one. */
    language?: string;
}

export type { NavAlign, NavDateField, NavFlyoutSide, NavFolderClick, NavFolderLink, NavFolderState, NavFoldersFirst, NavIcons, NavIndexEntry, NavMobile, NavNode, NavPagerOrder, NavScope, NavSort, NavSortDirection, NavTree, NavTrigger, NavVariant, NavigationBreakpoints, NavigationFrontmatterKeys, NavigationIconNames, NavigationOptions, ResolvedOptions };
