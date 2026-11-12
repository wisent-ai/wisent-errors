// Render the declaration rules (catalogue/declaration.json) and this
// package's own failures (catalogue/failures/) for each runtime, so the four
// refuse the same declarations with the same sentences and raise their own
// failures from one declaration.

const json = (value) => JSON.stringify(value);
const constant = (key) => key.toUpperCase().replace(/[^A-Z0-9]+/g, '_');
const camel = (key) => key.replace(/[-_.]([a-z0-9])/g, (_, next) => next.toUpperCase());
const PROBED = ['placeholder', 'cause_id', 'test_path'];

export function declarationJs({ declaration, banner }) {
  const probes = PROBED.map((key) => `  ${key}: Object.freeze({ valid: ${json(declaration[key].valid)}, invalid: ${json(declaration[key].invalid)} }),`).join('\n');
  return `${banner('//', 'catalogue/declaration.json')}

export const PLACEHOLDER_PATTERN = ${json(declaration.placeholder.pattern)};
export const PLACEHOLDER_GRAMMAR = ${json(declaration.placeholder.grammar)};
export const RAW_MESSAGE_NAMES = Object.freeze(${json(declaration.raw_message.names)});
export const CAUSE_ID_PATTERN = ${json(declaration.cause_id.pattern)};
export const TEST_PATH_PATTERN = ${json(declaration.test_path.pattern)};
export const FIELD_MEANINGS = Object.freeze(${JSON.stringify(declaration.fields, null, 2)});
export const SENTENCES = Object.freeze(${JSON.stringify(declaration.sentences, null, 2)});
export const PROBES = Object.freeze({
${probes}
});
`;
}

export function declarationPython({ declaration, banner }) {
  const probes = PROBED.map((key) => `    ${json(key)}: {"valid": ${json(declaration[key].valid)}, "invalid": ${json(declaration[key].invalid)}},`).join('\n');
  return `${banner('#', 'catalogue/declaration.json')}

PLACEHOLDER_PATTERN = ${json(declaration.placeholder.pattern)}
PLACEHOLDER_GRAMMAR = ${json(declaration.placeholder.grammar)}
RAW_MESSAGE_NAMES = ${json(declaration.raw_message.names).replace('[', '(').replace(/]$/, ')')}
CAUSE_ID_PATTERN = ${json(declaration.cause_id.pattern)}
TEST_PATH_PATTERN = ${json(declaration.test_path.pattern)}
FIELD_MEANINGS = ${JSON.stringify(declaration.fields, null, 4)}
SENTENCES = ${JSON.stringify(declaration.sentences, null, 4)}
PROBES = {
${probes}
}
`;
}

export function declarationRust({ declaration, banner }) {
  const sentences = Object.entries(declaration.sentences)
    .map(([key, text]) => `pub const ${constant(key)}: &str = ${json(text)};`)
    .join('\n');
  const meanings = Object.entries(declaration.fields).map(([field, text]) => `        ${json(field)} => ${json(text)},`).join('\n');
  const probes = PROBED.map((key) => `pub const ${constant(key)}_VALID: &[&str] = &${json(declaration[key].valid)};\npub const ${constant(key)}_INVALID: &[&str] = &${json(declaration[key].invalid)};`).join('\n');
  return `${banner('//', 'catalogue/declaration.json')}

//! What a declared cause or warning must be, and the sentence each refusal
//! of a declaration says.

pub const PLACEHOLDER_PATTERN: &str = ${json(declaration.placeholder.pattern)};
pub const PLACEHOLDER_GRAMMAR: &str = ${json(declaration.placeholder.grammar)};
pub const RAW_MESSAGE_NAMES: &[&str] = &${json(declaration.raw_message.names)};
pub const CAUSE_ID_PATTERN: &str = ${json(declaration.cause_id.pattern)};
pub const TEST_PATH_PATTERN: &str = ${json(declaration.test_path.pattern)};

/// What a declaration field holds, as a refusal of an empty one says.
pub fn field_meaning(field: &str) -> &'static str {
    match field {
${meanings}
        _ => "the text the declaration states",
    }
}

${sentences}

${probes}
`;
}

export function declarationSwift({ declaration, banner }) {
  const sentences = Object.entries(declaration.sentences).map(([key, text]) => `        ${json(key)}: ${json(text)},`).join('\n');
  const meanings = Object.entries(declaration.fields).map(([field, text]) => `        ${json(field)}: ${json(text)},`).join('\n');
  const list = (values) => `[${values.map(json).join(', ')}]`;
  const probes = PROBED.map((key) => `        ${json(key)}: (valid: ${list(declaration[key].valid)}, invalid: ${list(declaration[key].invalid)}),`).join('\n');
  return `${banner('//', 'catalogue/declaration.json')}

/// What a declared cause or warning must be, and the sentence each refusal
/// of a declaration says.
public enum Declaration {
    public static let placeholderPattern = ${json(declaration.placeholder.pattern)}
    public static let placeholderGrammar = ${json(declaration.placeholder.grammar)}
    public static let rawMessageNames: [String] = ${list(declaration.raw_message.names)}
    public static let causeIdPattern = ${json(declaration.cause_id.pattern)}
    public static let testPathPattern = ${json(declaration.test_path.pattern)}
    public static let fieldMeanings: [String: String] = [
${meanings}
    ]
    public static let sentences: [String: String] = [
${sentences}
    ]
    public static let probes: [String: (valid: [String], invalid: [String])] = [
${probes}
    ]
}
`;
}

export { camel, constant };
