# Publishing Kindling to Homebrew

There are two destinations and they have very different bars.

| | `brew tap you/kindling && brew install kindling` | `brew install kindling` |
|---|---|---|
| Where | your own tap | `homebrew/core` |
| Approval | none, it's your repo | a PR reviewed by maintainers |
| When | today | once the project is notable |

Start with your own tap. It is the supported path for new software —
Homebrew's own policy says software that doesn't meet the core criteria
"can generally be maintained in a third-party tap".

## Why core will reject it today

From Homebrew's `Package-Acceptance-Policy.md`, a new package must show
public interest beyond its author:

- **30 forks, 30 watchers or 75 stars** — normal submission
- **90 forks, 90 watchers or 225 stars** — **self-submission by the repo owner**, which is what this would be
- the repository must be **at least 30 days old**

Plus, from `Acceptable-Formulae.md`: an immutable tagged release verified by
SHA-256 (not a moving branch), an open-source licence, and a working `test do`
block. Kindling already satisfies that second group — it's the notability gate
that takes time.

So: ship the tap now, open a core PR later if it gets traction.

## 1. Push the repository

The repo needs to exist publicly before a formula can point at it.

```sh
cd the kindling checkout
gh repo create kindling --public --source=. --remote=origin \
  --description "A zsh framework: async prompt, lazy loading, one-pass line editing"
git push -u origin main
git push origin v1.0.0
```

Add topics so people can find it — `zsh`, `zsh-framework`, `zsh-theme`,
`oh-my-zsh`, `shell`, `dotfiles`.

## 2. Get the real checksum

**Do not trust a locally built tarball's checksum.** GitHub generates the
archive for a tag itself, and its gzip output need not be byte-identical to
your `git archive`. Take the checksum from the URL Homebrew will actually
fetch:

```sh
curl -fsSL https://github.com/samuelbanapour/kindling/archive/refs/tags/v1.0.0.tar.gz \
  | shasum -a 256
```

## 3. Publish the tap

A tap is just a repo named `homebrew-<something>` with a `Formula/` directory.

```sh
gh repo create homebrew-kindling --public
cd homebrew-kindling
mkdir -p Formula
# copy Formula/kindling.rb in, with the url and sha256 from step 2
git add . && git commit -m "kindling 1.0.0" && git push
```

Then anyone can install it:

```sh
brew tap samuelbanapour/kindling
brew install kindling
```

## 4. Verify before you announce

```sh
brew style   --formula Formula/kindling.rb          # lint
brew install --build-from-source samuelbanapour/kindling/kindling
brew test    samuelbanapour/kindling/kindling                   # runs the formula's test block
brew audit --strict --formula samuelbanapour/kindling/kindling  # what core CI would run
```

All four pass on the formula in this repo.

## 5. Releasing a new version

```sh
# bump KINDLING_VERSION in kindling.zsh first
sh release.sh 1.1.0
```

It refuses to tag if `kindling.zsh` disagrees about the version or if the test
suite fails, pushes the tag, then fetches the tarball GitHub generated and
prints the `url` and `sha256` to paste into the tap.

## Later: the core PR

Once you clear the thresholds:

```sh
brew bump-formula-pr --new-formula ...
```

or open a PR against `homebrew/core` adding `Formula/e/kindling.rb`. Expect
review on: the `desc` (no leading article, no repeating the name, under 80
chars), the `test do` block doing something real rather than `--version`, and
whether the software is genuinely maintained.

## What Homebrew changed about Kindling

Packaging surfaced a design bug worth knowing about.

`$KINDLING_CUSTOM` used to default to `$KINDLING/custom`. Under Homebrew that is
`/opt/homebrew/Cellar/kindling/<version>/share/kindling/custom` — inside the
directory `brew upgrade` **replaces wholesale**. Every plugin and theme a user
wrote would vanish on the next upgrade, silently.

So the framework now detects how it was installed. The formula writes a marker
file, `.kindling-managed`, containing `homebrew`; `kindling.zsh` reads it and puts
`$KINDLING_CUSTOM` under `$XDG_DATA_HOME/kindling/custom` instead. A git or plain
install keeps `$KINDLING/custom` exactly as before. `kindling update` reads the same
marker and tells Homebrew users to run `brew upgrade kindling` rather than trying
to `git pull` inside the Cellar, which the next upgrade would undo anyway.

This is verified, not assumed: the test suite writes a plugin, reinstalls the
formula over the top, and checks the plugin is still there and still loadable.
