Contributing to Kalamine
================================================================================


Setup
--------------------------------------------------------------------------------

Install [Rust](https://www.rust-lang.org/learn/get-started).

After checking out the repository, you can build kalamine with cargo:

```bash
cargo build
```

To launch kalamine with cargo and pass arguments to kalamine (and not cargo) you must add `--`, for example:

```bash
cargo run -- --help
```


Code Formating
--------------------------------------------------------------------------------

Format with the default Rust formatter:

```bash
cargo fmt
```


Code Linting
--------------------------------------------------------------------------------

You can use clippy to help you with Rust good practices:

```bash
cargo clippy
```


Unit Tests
--------------------------------------------------------------------------------

To launch tests:

```bash
cargo test
```


Before Committing
--------------------------------------------------------------------------------

You may ensure manually that your commit will pass the Github CI (continuous integration) with:

```bash
cargo test
```

But setting up a git pre-commit hook is strongly recommended. Just create an executable `.git/hooks/pre-commit` file containing:

```bash
#!/bin/sh
cargo test
```

This is asking git to run the above command before any commit is created, and to abort the commit if it fails.
