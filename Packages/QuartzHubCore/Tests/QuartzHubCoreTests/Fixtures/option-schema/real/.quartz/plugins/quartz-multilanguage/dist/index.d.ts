import { QuartzTransformerPlugin, QuartzFilterPlugin, QuartzEmitterPlugin } from '@quartz-community/types';
import { MultilanguageOptions } from './types.js';
export { DetectionStrategy, FrontmatterKeys, LanguageConfig, LinkingStrategy, MultilanguageFileData, SeoOptions, SwitcherOptions, TranslationMap } from './types.js';
export { LanguageSwitcher } from './components/index.js';

declare const MultilanguageTransformer: QuartzTransformerPlugin<MultilanguageOptions>;

/**
 * Two jobs: record every page for the render-time `hreflang` lookup (see `registry.ts`),
 * and drop pages whose language is not in `publishLanguages`.
 */
declare const MultilanguageFilter: QuartzFilterPlugin<MultilanguageOptions>;

declare const MultilanguageEmitter: QuartzEmitterPlugin<MultilanguageOptions>;

/** The subset of the explorer's `FileTrieNode` this helper needs. */
interface TrieNodeLike {
    slug?: string;
    slugSegments?: string[];
    isFolder?: boolean;
    children?: TrieNodeLike[];
}
/**
 * Builds a `filterFn` for the explorer plugin that keeps only pages of one language.
 * The explorer accepts functions only from `quartz.ts`, not from YAML:
 *
 * ```ts
 * import { languageExplorerFilter } from "./.quartz/plugins/quartz-multilanguage"
 * Explorer({ filterFn: languageExplorerFilter("de", { languages: ["de", "en"] }) })
 * ```
 *
 * Folder nodes are kept when they contain at least one page of the language, so the
 * language folder itself and folders without pages stay visible only if needed.
 */
declare function languageExplorerFilter(lang?: string, userOpts?: MultilanguageOptions): (node: TrieNodeLike) => boolean;

export { MultilanguageEmitter, MultilanguageFilter, MultilanguageOptions, MultilanguageTransformer, type TrieNodeLike, languageExplorerFilter };
