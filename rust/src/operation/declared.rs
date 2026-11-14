//! A declared cause met: the cause and the values its raising site knew,
//! as one error a product raises instead of a type of its own. It is the Rust
//! form of the JS package's `DeclaredError` (js/refusal.mjs): displayed, it
//! says the cause's refusal, its sentence and its fix.

use super::{Cause, Operation};

/// A declared cause met, with the values its sentences are filled with.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Declared {
    pub cause: &'static Cause,
    values: Vec<(&'static str, String)>,
}

impl Declared {
    /// `cause` met with `values`.
    pub fn new(cause: &'static Cause, values: &[(&'static str, &str)]) -> Self {
        Self {
            cause,
            values: values.iter().map(|(name, value)| (*name, (*value).to_owned())).collect(),
        }
    }

    /// The values the cause's sentences are filled with.
    pub fn values(&self) -> Vec<(&'static str, &str)> {
        self.values.iter().map(|(name, value)| (*name, value.as_str())).collect()
    }

    /// What failed, why, and the state observed ([`Cause::sentence`]).
    pub fn sentence(&self) -> String {
        self.cause.sentence(&self.values())
    }

    /// What would fix it ([`Cause::fix`]).
    pub fn fix(&self) -> String {
        self.cause.fix(&self.values())
    }

    /// The exit status this refusal leaves a command with, given the
    /// product's own failure status ([`Cause::exit_code`]).
    pub fn exit_code(&self, failure_exit: i32) -> i32 {
        self.cause.exit_code(failure_exit)
    }

    /// The cause's full id, `<functionality>.<cause>`, as `errors show`
    /// names it: the first of `operations` that declares it, else its bare id.
    pub fn code(&self, operations: &[&Operation]) -> String {
        let declaring = operations
            .iter()
            .find(|operation| operation.causes.iter().any(|listed| std::ptr::eq(*listed, self.cause)));
        match declaring {
            Some(operation) => format!("{}.{}", operation.id, self.cause.id),
            None => self.cause.id.to_owned(),
        }
    }

    /// The first declared cause in `error`'s chain of sources, `error` itself
    /// first: what a caller reporting a failure several layers above its
    /// raising site names it by.
    pub fn in_chain<'a>(error: &'a (dyn std::error::Error + 'static)) -> Option<&'a Self> {
        std::iter::successors(Some(error), |link| link.source()).find_map(|link| link.downcast_ref::<Self>())
    }
}

impl std::fmt::Display for Declared {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.cause.refusal(&self.values()))
    }
}

impl std::error::Error for Declared {}
