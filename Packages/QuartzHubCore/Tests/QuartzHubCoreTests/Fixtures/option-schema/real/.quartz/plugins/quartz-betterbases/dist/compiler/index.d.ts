import { FilterNode } from '../types.js';
import 'preact';
import '@quartz-community/types';

type Span = {
    start: number;
    end: number;
};

type LiteralValue = string | number | boolean | null | RegExp;
type UnaryOperator = "!" | "-";
type BinaryOperator = "+" | "-" | "*" | "/" | "%" | "==" | "!=" | ">" | "<" | ">=" | "<=" | "&&" | "||";
type BaseNode = {
    type: string;
    span: Span;
};
type LiteralExpression = BaseNode & {
    type: "Literal";
    value: LiteralValue;
};
type IdentifierExpression = BaseNode & {
    type: "Identifier";
    name: string;
};
type UnaryExpression = BaseNode & {
    type: "Unary";
    operator: UnaryOperator;
    argument: Expression;
};
type BinaryExpression = BaseNode & {
    type: "Binary";
    operator: BinaryOperator;
    left: Expression;
    right: Expression;
};
type CallExpression = BaseNode & {
    type: "Call";
    callee: Expression;
    args: Expression[];
};
type MemberExpression = BaseNode & {
    type: "Member";
    object: Expression;
    property: string;
};
type IndexExpression = BaseNode & {
    type: "Index";
    object: Expression;
    index: Expression;
};
type ListExpression = BaseNode & {
    type: "List";
    elements: Expression[];
};
type Expression = LiteralExpression | IdentifierExpression | UnaryExpression | BinaryExpression | CallExpression | MemberExpression | IndexExpression | ListExpression;

type Instruction = {
    type: "Const";
    value: LiteralValue | undefined;
} | {
    type: "Ident";
    name: string;
} | {
    type: "LoadFormula";
    name: string;
} | {
    type: "Member";
    name: string;
} | {
    type: "Index";
} | {
    type: "List";
    count: number;
} | {
    type: "Unary";
    operator: UnaryOperator;
} | {
    type: "Binary";
    operator: BinaryOperator;
} | {
    type: "ToBool";
} | {
    type: "CallGlobal";
    name: string;
    argc: number;
} | {
    type: "CallMethod";
    name: string;
    argc: number;
} | {
    type: "CallMethodLazy";
    name: string;
    argPrograms: Instruction[][];
} | {
    type: "Jump";
    offset: number;
} | {
    type: "JumpIfFalse";
    offset: number;
} | {
    type: "JumpIfTrue";
    offset: number;
};

type EvalContext = {
    note: Record<string, unknown>;
    file: {
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
        properties?: Record<string, unknown>;
        created?: string | Date;
        modified?: string | Date;
        ctime?: Date;
        mtime?: Date;
        size?: number;
        /** Language code from quartz-multilanguage (`de`); Obsidian has no such property. */
        lang?: string;
    };
    /** The page's language, for a duration joined to text ("ein Tag"). */
    locale?: string;
    formula: Record<string, unknown>;
    /** In a summary formula: the column's value on every row, empty ones included. */
    values?: unknown[];
    /**
     * The page the base is rendered on, which `this` reads (as a ThisFile): for a base embedded
     * in a note the note, for the page of a .base file the base file itself, as Obsidian has it
     * when the base is opened on its own.
     */
    self?: {
        file: EvalContext["file"];
    };
    _lambdaValue?: unknown;
    /** In map(), filter() and reduce(): the element's position (`index`). */
    _lambdaIndex?: number;
    /** In reduce(): what the elements before gave (`acc`). */
    _lambda?: {
        acc: unknown;
    };
    _fileLookup?: Map<string, EvalContext["file"]>;
};
declare function resolvePropertyValue(path: string, context: EvalContext): unknown;

type CompiledExpression = {
    ast: Expression;
    instructions: Instruction[];
};

/**
 * An error while evaluating a formula, as Obsidian reports it in the cell (warning icon and
 * message). It travels through the expression like an exception: `(date + 1) + "x"`, a list
 * holding it and a formula that names it (`formula.a`) are the same error; only a branch that is
 * not taken (`true || err`, `if(true, 1, err)`) escapes it. Measured with the Obsidian CLI
 * (`base:query` on gui-test-content, _cmp-test/prop.base).
 */
declare class FormulaError extends Error {
    constructor(message: string);
}
declare function isFormulaError(value: unknown): value is FormulaError;

declare function compile(expression: string): CompiledExpression;
/**
 * The value of an expression, or the FormulaError it ended in (shown in the cell as Obsidian
 * shows it). An expression that does not parse stays empty.
 */
declare function evaluate(expression: string, context: EvalContext): unknown;
declare function evaluateFilter(node: FilterNode | undefined, context: EvalContext): boolean;

export { type CompiledExpression, type EvalContext, FormulaError, compile, evaluate, evaluateFilter, isFormulaError, resolvePropertyValue };
