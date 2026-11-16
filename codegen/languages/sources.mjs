// Where the numbers every generated vocabulary carries come from. Each runtime
// writes the source beside the status or exit code it emits, so the generated
// module says where a 429 or a 69 is defined without sending its reader here.

// Every HTTP status code, by value.
export const STATUS_REGISTRY = 'https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml';
// A status code's first digit is its class: 5xx, 500 to 599, is a server error.
export const STATUS_CLASSES = 'https://www.rfc-editor.org/rfc/rfc9110.html#section-15';
// The retry exit, EX_UNAVAILABLE.
export const SYSEXITS = 'https://man.freebsd.org/cgi/man.cgi?query=sysexits';
// The usage exit, the code clap exits with on a usage error.
export const CLAP_USAGE_EXIT = 'https://docs.rs/clap/latest/clap/error/struct.Error.html#method.exit';
