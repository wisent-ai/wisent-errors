//! A functionality's failure catalogue: every way one functionality of a
//! product can fail, declared in code beside the code that raises it.
//!
//! "Operation did not succeed" is a failure nobody analysed. A declared cause
//! is the analysis written down once: which step failed, why, which state the
//! reader is shown, what fixes it, the code and the exit status it leaves, the
//! test that provokes it and the documentation line that lists it. The
//! catalogue holds every cause the functionality can meet, including the ones
//! nobody has met yet, because the reader who meets one first has nothing
//! else to go on.
//!
//! The unit is the functionality, not the command that starts it. One command
//! runs several functionalities (a registry read, a store write, a connection
//! to a host), and many run with no command at all: a worker's loop, an API
//! route, a desktop screen, a routine. So an [`Operation`] is one
//! functionality, named by its failure point; it lists the `entries` a user or
//! a program starts it through and the functionalities it `uses`, whose causes
//! it meets without declaring them again.
//!
//! The same declaration produces the refusal the operator reads, the envelope
//! a machine reads, the `errors show` listing and the documentation page, so
//! none of them can say something the others do not. The rules a declaration
//! is held to, and the sentence each refusal of one says, are
//! catalogue/declaration.json, the same in every runtime.

mod catalogue;
mod cause;
mod source;
pub mod template;

pub use catalogue::catalogue_problems;
pub use cause::Cause;
pub(crate) use cause::{is_cause_id, is_test_path, text_problems};
pub use source::generic_sentences_in;
pub use template::{fill, parts, placeholders, template_problems, unfilled, Part};

/// One functionality and every cause it can fail with.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Operation {
    /// The functionality's failure point: a dotted lowercase path,
    /// `stado.registry.read`.
    pub id: &'static str,
    /// Every way a user or a program starts it, as they meet it: a command
    /// (`stado fleet enroll`), a route (`POST /v1/jobs`), a screen
    /// (`Desktop: Hosts → Enroll`), a routine or a library call. A
    /// functionality only other functionalities run has none and is listed
    /// in their `uses`.
    pub entries: &'static [&'static str],
    /// The functionalities it runs, whose causes it meets as they declare
    /// them.
    pub uses: &'static [&'static Operation],
    pub summary: &'static str,
    /// The functionality's documentation page; each cause is a line on it.
    pub docs: &'static str,
    /// The causes of its own steps; a functionality made only of the ones it
    /// uses declares none.
    pub causes: &'static [&'static Cause],
    /// What it does that its caller must know before it runs: an effect
    /// nothing undoes, access it takes from someone, a secret it lets out, a
    /// change outside the product, money it spends ([`crate::Warning`]). A
    /// functionality with no such effect declares none; a warning nobody needs
    /// teaches its reader to confirm without reading.
    pub warnings: &'static [&'static crate::Warning],
}

impl Operation {
    /// The declared cause with this id.
    pub fn cause(&self, id: &str) -> Option<&'static Cause> {
        self.causes.iter().copied().find(|cause| cause.id == id)
    }
}
