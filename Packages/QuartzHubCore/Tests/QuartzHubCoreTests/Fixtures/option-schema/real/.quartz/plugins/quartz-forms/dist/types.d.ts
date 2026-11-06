type Params = Record<string, string | number | boolean | undefined>;
type Translate = (code: string, params?: Params) => string;

/**
 * The plugin's own messages about a definition - the problems that stop the build, the hints it
 * logs, what a key or the command line refuses - in English, word for word what the build log has
 * always said (the build log stays English; tests hold these strings). The German catalog must
 * have every key (de.ts is typed against this one).
 */
declare const en: {
    textEmpty: () => string;
    textShape: () => string;
    textRecordEmpty: () => string;
    fieldShape: () => string;
    fieldNamePattern: (p: Params) => string;
    fieldNameReserved: (p: Params) => string;
    minAboveMax: (p: Params) => string;
    maxLengthMin: () => string;
    patternJsU: () => string;
    patternJsNegClass: () => string;
    patternJsEmptyClass: () => string;
    patternJsLookbehind: () => string;
    patternInvalid: (p: Params) => string;
    optionsNeeded: (p: Params) => string;
    optionShape: () => string;
    optionTwice: (p: Params) => string;
    optionSpace: (p: Params) => string;
    scaleInteger: () => string;
    scaleOrder: (p: Params) => string;
    scaleSpan: () => string;
    consentText: () => string;
    hiddenValue: () => string;
    fieldTypeUnknown: (p: Params) => string;
    labelNeeded: (p: Params) => string;
    widthValue: () => string;
    layoutValue: () => string;
    layoutSelect: () => string;
    showIfNotAllowed: (p: Params) => string;
    showIfShape: () => string;
    showIfUnknown: (p: Params) => string;
    showIfLater: (p: Params) => string;
    showIfController: (p: Params) => string;
    showIfValue: (p: Params) => string;
    pageBreakEdge: () => string;
    pageBreakTwice: () => string;
    consentInConditionalStep: () => string;
    stepOnlyHidden: (p: Params) => string;
    keyShape: () => string;
    keyExactlyOne: () => string;
    keyOutside: (p: Params) => string;
    keyUnreadable: (p: Params) => string;
    keyFileBlock: (p: Params, t: Translate) => string;
    armorPrivate: () => string;
    armorNone: () => string;
    armorIncomplete: () => string;
    armorOther: (p: Params) => string;
    armorMany: (p: Params) => string;
    pgpUnreadable: (p: Params) => string;
    pgpPrivate: () => string;
    pgpRevoked: () => string;
    pgpExpired: (p: Params) => string;
    pgpNoEncrypt: () => string;
    pgpNewAlgorithm: (p: Params) => string;
    pgpVersion6: () => string;
    keyMissingSource: () => string;
    keyFileUnreadable: () => string;
    formIdPattern: (p: Params) => string;
    templateUnknown: (p: Params) => string;
    noFields: () => string;
    fieldNameTwice: (p: Params) => string;
    onePgpKey: () => string;
    urlNeeded: (p: Params) => string;
    urlNotHttp: (p: Params) => string;
    urlPlainHttp: (p: Params) => string;
    relayRecipient: () => string;
    presetUrl: (p: Params) => string;
    anonymousService: (p: Params) => string;
    mailtoRecipient: () => string;
    kindUnknown: (p: Params) => string;
    extraRelay: () => string;
    extraMailto: () => string;
    demoNoEffect: () => string;
    demoRedirect: () => string;
    demoCaptcha: (p: Params) => string;
    formatValue: () => string;
    modeValue: () => string;
    noKeys: () => string;
    keyUnknown: (p: Params) => string;
    mailtoEncrypted: () => string;
    minSecondsValue: () => string;
    powDifficultyValue: () => string;
    captchaValue: () => string;
    siteKeyNeeded: (p: Params) => string;
    anonymousCaptcha: (p: Params) => string;
    noRelayEffect: () => string;
    encryptionCaptcha: (p: Params) => string;
    powNoScript: () => string;
    minSecondsNoScript: () => string;
    rateLimitLever: (p: Params) => string;
    powSlow: (p: Params) => string;
    positiveInteger: () => string;
    maxBytesLow: (p: Params) => string;
    pageContextAnonymous: () => string;
    personalOptional: (p: Params) => string;
    successMode: () => string;
    successSlug: () => string;
    languageValue: (p: Params) => string;
    frontmatterKeyEmpty: () => string;
    layoutFormUnknown: (p: Params) => string;
    codeBlockLangValue: () => string;
    textsLocaleUnknown: () => string;
    textsShape: () => string;
    textsKeyUnknown: () => string;
    textsPlaceholderMissing: (p: Params) => string;
    textsPlaceholderUnknown: (p: Params) => string;
    cliNeedsValue: (p: Params) => string;
    cliUnknownArgument: (p: Params) => string;
    cliNoSite: () => string;
    cliConfigMissing: (p: Params) => string;
    cliNoEntry: (p: Params) => string;
    cliEntries: (p: Params) => string;
    cliNoOut: () => string;
    cliUnknownCommand: (p: Params) => string;
    cliNoKey: () => string;
    cliKeyUnreadable: (p: Params) => string;
    cliOperatorJson: () => string;
    cliOperatorProblems: (p: Params) => string;
    cliOptionProblems: (p: Params) => string;
    cliNoPhp: (p: Params) => string;
    cliPhpFailed: (p: Params) => string;
    cliPhpFailedShort: () => string;
    cliPatternUnreadable: (p: Params) => string;
    cliPatternRefusal: () => string;
    cliNothingWritten: () => string;
    cliWrittenAnyway: () => string;
    cliMissingRecipient: (p: Params) => string;
    operatorNotObject: () => string;
    operatorSecret: () => string;
    operatorOrigins: () => string;
    operatorFrom: () => string;
    operatorMailer: () => string;
    operatorRecord: (p: Params) => string;
    operatorText: (p: Params) => string;
    operatorCounterDir: () => string;
    operatorFlag: (p: Params) => string;
};

type MessageCode = keyof typeof en;

/**
 * A message of the plugin about a definition: where (the option's path, as it stands in
 * quartz.config.yaml), what (a code) and with what (the values the sentence names). The sentence
 * is made from it per language; the build log takes English, the command line `--lang`.
 * QuartzControl reads the path to put a message at its form, field or section.
 */
interface Message {
    path: string;
    code: MessageCode;
    params?: Params;
}

/**
 * Options of quartz-forms. This file is the single source of truth for the data model:
 * `quartz.configSchema` in package.json is checked against it member by member
 * (test/config-schema.test.ts), `defaultOptions` in src/options.ts must satisfy it, and the
 * three validation levels (build, browser, relay) derive their rules from the same fields.
 */
/**
 * A user-facing text: one string for every language, or a record keyed by language code
 * (`{ de: "Name", en: "Name" }`). Resolution: exact code, then primary subtag, then the first
 * value. QuartzControl offers the site's languages as keys (`x-quartz-keys: "languages"`).
 */
type Text = string | Record<string, string>;
interface QuartzFormsOptions {
    /** The forms of this site, by id (`[a-z0-9-]`). A page embeds a form by this id. */
    forms: Record<string, FormDefinition>;
    /** Where a submission goes. Every form can override single fields of it. */
    transport: TransportConfig;
    /**
     * Public PGP keys, by name. A form names the keys it encrypts to; a key is read from a file
     * relative to the site root (`quartz/static/keys/owner.asc`) or written inline as armored text.
     */
    keys: Record<string, PgpKeySource>;
    /** Spam protection and size limits. Every form can override single fields of it. */
    spam: SpamConfig;
    /**
     * Frontmatter key that embeds a form on a page (`form: contact`) or hides the form placed
     * through the layout on this page (`form: false`).
     */
    frontmatterKey: string;
    /** Language tag of the fenced code block that embeds a form in the text. */
    codeBlockLang: string;
    /**
     * Id of the form placed through the layout block of this plugin entry (sidebar, footer, after
     * the body on every page). Empty: nothing is placed; forms are embedded per page only.
     */
    layoutForm: string;
    /**
     * Language of the form placed through the layout: `auto` takes the page language
     * (`frontmatter.lang`, else the site locale), or a language code.
     */
    language: string;
    /**
     * Own wording for the plugin's texts, by locale and text key (`de: { submit: "Abschicken" }`).
     * The keys are those of src/i18n/locales/en-US.ts.
     */
    texts: Record<string, Record<string, string>>;
}
/** The four field sets that ship with the plugin; `fields` replaces the template's fields. */
type FormTemplate = "contact" | "feedback" | "rsvp" | "survey";
interface FormDefinition {
    /** Start from a built-in field set. Own `fields` replace it entirely. */
    template?: FormTemplate;
    /** Heading above the form. */
    title?: Text;
    /** A sentence under the heading. */
    description?: Text;
    /** Text of the submit button; default from the plugin's texts. */
    submitLabel?: Text;
    /** The fields, in order. Required unless `template` is set. */
    fields?: FormField[];
    /**
     * Who receives the submission. For the relay this is a name the relay maps to an address in
     * its own `config.php`; the address never reaches the site. For `mailto` it is the address.
     */
    recipient?: string;
    /** Fixed subject line of the mail. With `anonymous` it must not contain field values. */
    subject?: Text;
    /** Overrides single fields of the global transport. */
    transport?: Partial<TransportConfig>;
    /** Encryption in the browser before sending. Default: off. */
    encryption?: EncryptionConfig;
    /**
     * Anonymous mode: no required personal fields, no Reply-To, no page context, no third-party
     * captcha, and the relay logs nothing. What this cannot promise is in the README.
     */
    anonymous?: boolean;
    /**
     * Send the page's title and slug along, as a line `Page: Title (slug)` of the message (for a
     * feedback form). Inside the ciphertext when the message is encrypted. Default: false.
     */
    pageContext?: boolean;
    /** Overrides single fields of the global spam settings. */
    spam?: Partial<SpamConfig>;
    /** What happens after a successful send. Default: a thank-you sentence in place. */
    /** What happens after sending. */
    success?: SuccessDefinition;
    /** Extra class(es) on the form element, next to the fixed `quartz-form`. */
    className?: string;
}
/**
 * How much of the form's width a field takes: all of it, half or a third. The form is a grid of
 * six tracks that falls to halves and then to one column in a narrow container (forms.scss).
 */
type FieldWidth = "full" | "half" | "third";
/**
 * Show a field only while an earlier field has one of the given values: a choice's option value,
 * `"yes"` for a ticked checkbox, a scale's number as a string. With `checkboxes` one of the
 * values ticked is enough. A field whose condition does not hold is not required, not checked,
 * not sent and not mailed; a value posted for it anyway (a browser without JavaScript shows every
 * field) is dropped, not refused.
 */
interface ShowIf {
    /** The `name` of an earlier select, radio, checkboxes, checkbox or scale field. */
    field: string;
    /** The value, or values, that show the field. */
    equals: string | string[];
}
/** How the options of a radio or checkboxes field stand: under each other or side by side. */
type ChoiceLayout = "stacked" | "inline";
type InputFieldType = "text" | "email" | "tel" | "url" | "number" | "date" | "textarea";
/** A single-value field rendered as `<input>` or `<textarea>`. */
interface InputField {
    type: InputFieldType;
    /** Name in the submission (`[a-z0-9_-]`, unique per form). */
    name: string;
    label: Text;
    required?: boolean;
    placeholder?: Text;
    /** A sentence under the field. */
    hint?: Text;
    /** HTML `autocomplete` token (`name`, `email`, `tel`, `off`). */
    autocomplete?: string;
    /** Regular expression the value must match (HTML `pattern`). */
    pattern?: string;
    /** Lower bound for `number`, checked by the build, the script and the relay. */
    min?: number;
    /** Upper bound for `number`, checked like `min`. */
    max?: number;
    /**
     * Step for `number` (HTML `step`). Only the browser's own check reads it, and that runs on the
     * no-script path alone; the script and the relay accept any number within the bounds.
     */
    step?: number;
    /** Rows of a `textarea`. */
    rows?: number;
    /**
     * Maximum length, counted as the browser's `maxlength` counts (UTF-16 units: an emoji is two),
     * after trimming; default from the spam settings.
     */
    maxLength?: number;
    /** How much of the form's width the field takes; default `full`. */
    width?: FieldWidth;
    /** Show the field only while an earlier field has one of the given values. */
    showIf?: ShowIf;
}
interface ChoiceOption {
    value: string;
    label: Text;
}
/** One of several (`select`, `radio`) or several of several (`checkboxes`). */
interface ChoiceField {
    type: "select" | "radio" | "checkboxes";
    name: string;
    label: Text;
    required?: boolean;
    hint?: Text;
    options: ChoiceOption[];
    /** How much of the form's width the field takes; default `full`. */
    width?: FieldWidth;
    /** `inline`: the options side by side, wrapping; `stacked` (default) under each other. A
     *  `select` has no options to arrange; the build says so. */
    layout?: ChoiceLayout;
    /** Show the field only while an earlier field has one of the given values. */
    showIf?: ShowIf;
}
/** A single checkbox with a label. */
interface CheckboxField {
    type: "checkbox";
    name: string;
    label: Text;
    required?: boolean;
    hint?: Text;
    /** How much of the form's width the field takes; default `full`. */
    width?: FieldWidth;
    /** Show the field only while an earlier field has one of the given values. */
    showIf?: ShowIf;
}
/** A rating from `min` to `max`, rendered as a row of radio buttons. */
interface ScaleField {
    type: "scale";
    name: string;
    label: Text;
    required?: boolean;
    hint?: Text;
    min: number;
    max: number;
    /** Caption at the low end. */
    minLabel?: Text;
    /** Caption at the high end. */
    maxLabel?: Text;
    /** How much of the form's width the field takes; default `full`. */
    width?: FieldWidth;
    /** Show the field only while an earlier field has one of the given values. */
    showIf?: ShowIf;
}
/** A checkbox the visitor must tick, with a sentence and an optional link (privacy policy). */
interface ConsentField {
    type: "consent";
    name: string;
    text: Text;
    /** Link target shown after the sentence. */
    link?: string;
    /** Link text; default from the plugin's texts. */
    linkLabel?: Text;
    /** How much of the form's width the field takes; default `full`. */
    width?: FieldWidth;
}
/**
 * The visitor's own public PGP key, pasted or chosen as an `.asc` file, so the owner can reply
 * encrypted. Checked in the browser; its fingerprint is shown; sent as part of the message.
 */
interface PgpKeyField {
    type: "pgpKey";
    name: string;
    label: Text;
    required?: boolean;
    hint?: Text;
    /** How much of the form's width the field takes; default `full`. */
    width?: FieldWidth;
    /** Show the field only while an earlier field has one of the given values. */
    showIf?: ShowIf;
}
/** A fixed value sent along, invisible. */
interface HiddenField {
    type: "hidden";
    name: string;
    value: string;
}
/**
 * A page break: the fields after it are the next step of the form, with "Next" and "Back"
 * between the steps and one submission at the end. Without JavaScript every step shows, one after
 * the other. A step may have a condition of its own; while it does not hold, the step is skipped
 * and its fields count as if their own condition did not hold.
 */
interface PageBreakField {
    type: "pageBreak";
    /** Heading of the step that starts here. */
    title?: Text;
    /** Skip the step that starts here unless an earlier field has one of the given values. */
    showIf?: ShowIf;
}
type FormField = InputField | ChoiceField | CheckboxField | ScaleField | ConsentField | PgpKeyField | HiddenField | PageBreakField;
/**
 * `relay`: the plugin's own PHP relay. `endpoint`: any URL that takes a POST. `formspree`,
 * `web3forms`: presets for those services. `mailto`: opens the visitor's mail program. `demo`:
 * sends nothing; the form checks, encrypts and shows below itself what would have been sent - for
 * a site that shows a form without anyone to receive it (a handbook on a host without PHP).
 */
type TransportKind = "relay" | "endpoint" | "formspree" | "web3forms" | "mailto" | "demo";
interface TransportConfig {
    kind: TransportKind;
    /** POST target for `relay` and `endpoint`; the form id or access key for the presets. */
    url?: string;
    /** Body encoding for `endpoint`; `relay` always sends JSON. */
    format?: "json" | "form";
    /**
     * Extra fields sent with every submission to an `endpoint` or a service (an access key, for
     * instance). The relay, `mailto` and `demo` take none; the build says so.
     */
    extra?: Record<string, string>;
}
interface PgpKeySource {
    /** Path of an armored public key, relative to the site root. */
    file?: string;
    /** The armored public key itself. */
    armored?: string;
}
type EncryptionMode = "required" | "optional" | "off";
interface EncryptionConfig {
    /**
     * `required`: nothing is sent unencrypted; without JavaScript the form cannot send.
     * `optional`: the visitor decides with a checkbox (on by default). `off`: plain text.
     */
    mode: EncryptionMode;
    /** Names from `keys` to encrypt to; default: all keys. */
    keys?: string[];
    /** Show the recipient key's fingerprint under the form. Default: true. */
    showFingerprint?: boolean;
}
interface SpamConfig {
    /** An invisible field that must stay empty. */
    honeypot: boolean;
    /** Seconds a visitor needs at least between opening the page and sending. 0 turns it off. */
    minSeconds: number;
    /**
     * Accept a submission from a browser without JavaScript (a plain form post). It skips the time
     * trap and the proof of work, which only the script can supply; honeypot, rate limit and field
     * checks still apply. `false` renders the form without a target until the script runs.
     */
    noScript: boolean;
    /** Proof of work checked by the relay (`transport.kind: relay` only). */
    pow: boolean;
    /**
     * Leading zero bits the proof must reach, 8 to 20. Hashed in a Worker: 16 takes up to a second
     * on a desktop, 18 and more take seconds on a phone (the build says so).
     */
    powDifficulty: number;
    /** A third-party captcha. Loads that provider's script; ignored for anonymous forms. */
    captcha: "none" | "turnstile" | "hcaptcha";
    /** The provider's site key. */
    captchaSiteKey: string;
    /** Submissions per form and hour the relay accepts; 0 turns it off. No addresses are stored. */
    rateLimitPerHour: number;
    /** Default maximum length of a single-line field, in characters. */
    maxFieldLength: number;
    /** Default maximum length of a textarea, in characters. */
    maxTextareaLength: number;
    /** Maximum length of a pasted public key, in characters. */
    maxKeyLength: number;
    /**
     * Maximum size of a whole submission, in bytes, checked by the script before sending and by the
     * relay. The build says when the fields may hold more than this (a textarea of 20 000 CJK
     * characters is about 60 kB, armored ciphertext a third more).
     */
    maxBytes: number;
}
/** `success` as written: the same as `SuccessConfig`, with `mode` left out for `inline`. */
interface SuccessDefinition {
    /** `inline` (the default): a sentence replaces the form. `redirect`: go to a page of the site. */
    mode?: "inline" | "redirect";
    /** The sentence for `inline`; default from the plugin's texts. */
    text?: Text;
    /** Slug of the page for `redirect` (`thanks`, `kontakt/danke`). */
    slug?: string;
}
interface SuccessConfig {
    /** `inline` (the default): a sentence replaces the form. `redirect`: go to a page of the site. */
    mode: "inline" | "redirect";
    /** The sentence for `inline`; default from the plugin's texts. */
    text?: Text;
    /** Slug of the page for `redirect` (`thanks`, `kontakt/danke`). */
    slug?: string;
}
interface ResolvedForm {
    id: string;
    title?: Text;
    description?: Text;
    submitLabel?: Text;
    fields: FormField[];
    recipient?: string;
    subject?: Text;
    transport: TransportConfig;
    encryption: Required<EncryptionConfig>;
    anonymous: boolean;
    pageContext: boolean;
    spam: SpamConfig;
    success: SuccessConfig;
    className?: string;
}
interface ResolvedOptions {
    forms: Record<string, ResolvedForm>;
    transport: TransportConfig;
    keys: Record<string, PgpKeySource>;
    spam: SpamConfig;
    frontmatterKey: string;
    codeBlockLang: string;
    layoutForm: string;
    language: string;
    texts: Record<string, Record<string, string>>;
    /** Problems the build must not pass over; `resolveOptions` throws them, this keeps them readable. */
    problems: string[];
    /** Things worth a line in the log, once. */
    hints: string[];
    /** The problems and hints as path, code and values, for another language (src/messages). */
    problemMessages: Message[];
    hintMessages: Message[];
}

export type { CheckboxField, ChoiceField, ChoiceLayout, ChoiceOption, ConsentField, EncryptionConfig, EncryptionMode, FieldWidth, FormDefinition, FormField, FormTemplate, HiddenField, InputField, InputFieldType, PageBreakField, PgpKeyField, PgpKeySource, QuartzFormsOptions, ResolvedForm, ResolvedOptions, ScaleField, ShowIf, SpamConfig, SuccessConfig, SuccessDefinition, Text, TransportConfig, TransportKind };
