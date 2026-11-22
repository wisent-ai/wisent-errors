### Fixed

- **The library compiles again:** `Operation`'s catalogue (`operation/catalogue.rs`) renders each cause
  with `Cause::to_json`, which was visible only inside `operation::causes`, so every product built
  against main stopped at E0624 (Weles's Rust build among them). `to_json` is now visible to the
  whole `operation` module.
