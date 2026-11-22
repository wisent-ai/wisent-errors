//! `cli_output::output`, the print every Wisent CLI's result goes through:
//! the result printed as pretty JSON and as `path: value` text, and each of
//! its refusals, a declared cause of `wisent_errors.cli_output.print`.
//!
//!   kompilator test --manifest-path rust/Cargo.toml --features cli-output --test cli-output-print
//!
//! - Rule 7: one test, the print's whole story step by step: a result
//!   printed both ways, a result JSON cannot hold, a standard output whose
//!   reader closed it, and (on macOS, the one host where a volume can be
//!   filled without privileges) a standard output on a full disk. Every
//!   cause of `wisent_errors.cli_output.print` names this test.
//!
//! What is printed, and a closed or full standard output, can only be met
//! by a process whose standard output is that, so those steps start this
//! test program again as that process: the child runs the one step named,
//! says on standard error when its harness has written its own lines, and
//! calls `output` once the parent closes its standard input; the parent
//! arranges the standard output in between and reads what the child
//! printed and said.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, Command, Stdio};

use wisent_errors::cli_output::output;

/// The one test, which its children run again.
const TEST: &str = "output_prints_the_result_or_says_the_declared_refusal";

/// Set in a child: the step it runs as the process whose standard output
/// the parent arranged.
const CHILD: &str = "WISENT_ERRORS_PRINT_CHILD";

/// What a child prints once its harness has written its own lines.
const READY: &str = "ready to print";

/// What a child prints before the refusal `output` answered.
const REFUSED: &str = "refused: ";

/// What a child prints on standard output before the result, so the
/// parent reads the result apart from the harness's own lines.
const PRINTED: &str = "printed below:\n";

/// EPIPE, a write to a pipe whose reader is gone: 32 in both macOS's
/// `sys/errno.h` and Linux's `asm-generic/errno-base.h`.
const EPIPE: i32 = 32;

/// ENOSPC, no space left on the device: 28 in macOS's `sys/errno.h`.
#[cfg(target_os = "macos")]
const ENOSPC: i32 = 28;

/// The kind and the words the operating system gives for `errno`, asked of
/// the standard library the way `output` hears them.
fn os_words(errno: i32) -> (String, String) {
    let error = std::io::Error::from_raw_os_error(errno);
    (format!("{:?}", error.kind()), error.to_string())
}

/// This test program started again as the child running `step`, its
/// standard output `stdout`.
fn child(step: &str, stdin: Stdio, stdout: Stdio) -> Command {
    let mut command = Command::new(std::env::current_exe().expect("the test program names itself"));
    command
        .args([TEST, "--exact", "--nocapture", "--test-threads=1"])
        .env(CHILD, step)
        .stdin(stdin)
        .stdout(stdout);
    command
}

/// In a child: print the result both ways, then end.
fn print_both_ways() -> ! {
    let result = serde_json::json!({
        "hosts": ["example-host", "example-host-2"],
        "name": "ada",
        "note": null,
        "owner": {"email": "ada@example.com", "teams": {}},
        "port": 8080,
        "ready": true,
        "tags": [],
    });
    print!("{PRINTED}");
    output::<_, serde_json::Error>(&result, false).expect("the result is printed as JSON");
    output::<_, serde_json::Error>(&result, true).expect("the result is printed as text");
    std::process::exit(0);
}

/// In a child: say it is ready, wait for the parent to close standard
/// input, then print a result of more than one disk block and say what
/// `output` answered. Ends the child; never returns.
fn print_when_told() -> ! {
    eprintln!("{READY}");
    let mut rest = Vec::new();
    std::io::stdin().read_to_end(&mut rest).expect("standard input is read to its end");
    let result = "x".repeat(8 * 1024);
    match output::<_, serde_json::Error>(&result, false) {
        Ok(()) => eprintln!("printed"),
        Err(error) => eprintln!("{REFUSED}{error}"),
    }
    std::process::exit(0);
}

/// Wait until `child` says it is ready, do `between`, close its standard
/// input, and return the refusal it said.
fn refusal(mut child: Child, between: impl FnOnce(&mut Child)) -> String {
    let mut said = BufReader::new(child.stderr.take().expect("the child's standard error is piped"));
    let mut line = String::new();
    while !line.contains(READY) {
        line.clear();
        assert_ne!(said.read_line(&mut line).expect("the child's standard error is read"), 0, "the child ended before it was ready");
    }
    between(&mut child);
    drop(child.stdin.take().expect("the child's standard input is piped"));
    let mut rest = String::new();
    said.read_to_string(&mut rest).expect("the child's standard error is read to its end");
    let status = child.wait().expect("the child ends");
    assert!(status.success(), "the child ran its step: {status:?}: {rest}");
    let Some(refused) = rest.lines().find_map(|line| line.strip_prefix(REFUSED)) else {
        panic!("the child said no refusal: {rest}");
    };
    refused.to_owned()
}

#[test]
fn output_prints_the_result_or_says_the_declared_refusal() {
    match std::env::var(CHILD).as_deref() {
        Ok("printed") => print_both_ways(),
        Ok("closed" | "full") => print_when_told(),
        _ => {}
    }

    // A result, printed as pretty JSON and then as one line per field.
    let printed = child("printed", Stdio::null(), Stdio::piped()).output().expect("the test program starts again");
    assert!(printed.status.success(), "{}", String::from_utf8_lossy(&printed.stderr));
    let stdout = String::from_utf8(printed.stdout).expect("the child prints UTF-8");
    let Some((_, result)) = stdout.split_once(PRINTED) else {
        panic!("the child printed no result: {stdout}");
    };
    assert_eq!(
        result,
        concat!(
            "{\n",
            "  \"hosts\": [\n",
            "    \"example-host\",\n",
            "    \"example-host-2\"\n",
            "  ],\n",
            "  \"name\": \"ada\",\n",
            "  \"note\": null,\n",
            "  \"owner\": {\n",
            "    \"email\": \"ada@example.com\",\n",
            "    \"teams\": {}\n",
            "  },\n",
            "  \"port\": 8080,\n",
            "  \"ready\": true,\n",
            "  \"tags\": []\n",
            "}\n",
            "hosts[0]: example-host\n",
            "hosts[1]: example-host-2\n",
            "name: ada\n",
            "note: -\n",
            "owner.email: ada@example.com\n",
            "owner.teams: -\n",
            "port: 8080\n",
            "ready: true\n",
            "tags: -\n",
        )
    );

    // A result JSON has no form for: refused before anything is written.
    let mut unrepresentable: HashMap<(u8, u8), u8> = HashMap::new();
    unrepresentable.insert((1, 2), 3);
    let error = output::<_, serde_json::Error>(&unrepresentable, false).expect_err("a map keyed by pairs has no JSON form");
    let shape = std::any::type_name::<HashMap<(u8, u8), u8>>();
    let encoder = serde_json::to_value(&unrepresentable).expect_err("serde_json refuses a map keyed by pairs").to_string();
    assert_eq!(
        error.to_string(),
        format!("turning the result of type {shape} into JSON: the result holds a value JSON has no form for, such as a map whose keys are not text; observed: the encoder answered {encoder}; fix: give {shape} keys that serialize as strings, or a Serialize form that writes them as text")
    );

    // The reader of standard output goes away before the result is written.
    let started = child("closed", Stdio::piped(), Stdio::piped()).stderr(Stdio::piped()).spawn().expect("the test program starts again");
    let said = refusal(started, |child| drop(child.stdout.take()));
    let (kind, words) = os_words(EPIPE);
    assert_eq!(
        said,
        format!("writing 8195 bytes of the result to standard output: whatever read standard output closed it before the result was written; observed: the write ended with {kind}: {words}; fix: keep the reading end open until the command ends, as in `command | jq .` rather than a reader that stops early")
    );

    // Standard output redirected to a file on a volume filled once the
    // child's harness has written its own lines there.
    #[cfg(target_os = "macos")]
    {
        let root = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("print-unwritable-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("make the case's directory");
        let volume = Volume::attached(&root);
        let redirect = std::fs::File::create(volume.mount.join("printed.txt")).expect("create the redirect");
        let started = child("full", Stdio::piped(), Stdio::from(redirect)).stderr(Stdio::piped()).spawn().expect("the test program starts again");
        let said = refusal(started, |_| volume.filled());
        let (kind, words) = os_words(ENOSPC);
        assert_eq!(
            said,
            format!("writing 8195 bytes of the result to standard output: the operating system refused the write for a reason other than a closed reader: a full disk behind a redirect, or a device gone; observed: the write ended with {kind}: {words}; fix: free space on the disk standard output is redirected to, or redirect it elsewhere, and run the command again")
        );
    }
}

/// A 16 MiB HFS+ disk image of the case's own attached without privileges
/// (only macOS's hdiutil does) and detached when dropped.
#[cfg(target_os = "macos")]
struct Volume {
    mount: std::path::PathBuf,
}

#[cfg(target_os = "macos")]
fn hdiutil(arguments: &[&std::ffi::OsStr]) {
    let output = Command::new("hdiutil").args(arguments).output().expect("hdiutil starts");
    assert!(output.status.success(), "hdiutil {arguments:?}: {}", String::from_utf8_lossy(&output.stderr));
}

#[cfg(target_os = "macos")]
impl Volume {
    fn attached(root: &std::path::Path) -> Volume {
        let (image, mount) = (root.join("volume.dmg"), root.join("volume"));
        std::fs::create_dir_all(&mount).expect("make the mount point");
        let os = std::ffi::OsStr::new;
        hdiutil(&[os("create"), os("-size"), os("16m"), os("-fs"), os("HFS+"), os("-volname"), os("print-case"), image.as_os_str()]);
        hdiutil(&[os("attach"), image.as_os_str(), os("-mountpoint"), mount.as_os_str(), os("-nobrowse")]);
        Volume { mount }
    }

    /// Every block the volume has left taken by one file, written in
    /// shrinking pieces until even 512 bytes are refused with ENOSPC.
    fn filled(&self) {
        let mut filler = std::fs::File::create(self.mount.join("filler")).expect("create the filler");
        for size in [64 * 1024, 4096, 512] {
            let piece = vec![0u8; size];
            loop {
                match filler.write_all(&piece).and_then(|()| filler.sync_all()) {
                    Ok(()) => {}
                    Err(error) if error.raw_os_error() == Some(ENOSPC) => break,
                    Err(error) => panic!("the filler stopped for another reason: {error}"),
                }
            }
        }
    }
}

// A failed detach is said, not discarded; Drop never panics mid-failure.
#[cfg(target_os = "macos")]
impl Drop for Volume {
    fn drop(&mut self) {
        match Command::new("hdiutil").arg("detach").arg(&self.mount).arg("-force").output() {
            Ok(output) if output.status.success() => {}
            Ok(output) => eprintln!("hdiutil detach {}: {}", self.mount.display(), String::from_utf8_lossy(&output.stderr)),
            Err(error) => eprintln!("hdiutil detach {}: {error}", self.mount.display()),
        }
    }
}
