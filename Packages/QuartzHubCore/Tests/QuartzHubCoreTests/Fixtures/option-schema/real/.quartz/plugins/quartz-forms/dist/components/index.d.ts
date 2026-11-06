import { QuartzComponent } from '@quartz-community/types';
import { QuartzFormsOptions } from '../types.js';

/**
 * The form placed through the layout block of the plugin entry (`options.layoutForm`). A page
 * hides it with `form: false`. Language: `options.language`, `auto` = the page's.
 */
declare const _default: (userOpts?: Partial<QuartzFormsOptions>) => QuartzComponent;

export { _default as FormBox, QuartzFormsOptions };
