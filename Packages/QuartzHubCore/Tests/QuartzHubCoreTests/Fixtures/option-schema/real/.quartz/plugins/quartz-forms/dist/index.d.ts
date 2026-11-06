import { QuartzTransformerPlugin, QuartzEmitterPlugin } from '@quartz-community/types';
import { QuartzFormsOptions, ResolvedOptions, Text, FormTemplate, FormDefinition } from './types.js';
export { EncryptionConfig, FormField, ResolvedForm, SpamConfig, SuccessConfig, TransportConfig } from './types.js';
export { FormBox } from './components/index.js';

declare const Forms: QuartzTransformerPlugin<Partial<QuartzFormsOptions>>;

/**
 * Copies the OpenPGP.js browser bundle into the site when a form needs it, and checks the keys
 * the forms encrypt to (the deep check level 1 could not do without the library).
 */
declare const FormsAssets: QuartzEmitterPlugin<Partial<QuartzFormsOptions>>;

declare const defaultOptions: QuartzFormsOptions;
/**
 * Quartz passes the raw YAML `options` of the entry; manifest defaults are not merged in.
 * Every factory of this plugin runs the raw options through here. Problems that the build must
 * not pass over are thrown as one error listing all of them; hints are returned for the caller
 * to log once.
 */
declare function resolveOptions(userOpts?: Partial<QuartzFormsOptions>): ResolvedOptions;
/**
 * The entry point of every factory: resolves, and stops the build on problems. A form with a
 * wrong definition would otherwise go out as a page that cannot send.
 */
declare function resolveOrThrow(userOpts?: Partial<QuartzFormsOptions>): ResolvedOptions;

/**
 * Picks the wording for a language: exact code, then primary subtag, then the first value.
 * `lang` may be a locale (`de-DE`) or a code (`de`); record keys may be either, too.
 */
declare function resolveText(text: Text | undefined, lang: string): string | undefined;

declare const templateNames: FormTemplate[];
declare function templateOf(name: FormTemplate): Partial<FormDefinition>;

export { FormDefinition, FormTemplate, Forms, FormsAssets, QuartzFormsOptions, ResolvedOptions, Text, defaultOptions, resolveOptions, resolveOrThrow, resolveText, templateNames, templateOf };
