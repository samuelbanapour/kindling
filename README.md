# Ember

A zsh framework. Same job as oh-my-zsh — plugins, themes, sane defaults, one
command to manage it — built around the things that go wrong with the usual
setup: slow startup, a prompt that stalls in big repositories, and highlighting
and autosuggestion plugins that fight each other over the same line.

```
~/code/ember  main +2 ~1 ⇡1                                          1.4s
❯
```

## Install

```sh
git clone https://github.com/ember-zsh/ember.git ~/.ember
sh ~/.ember/install.sh
```

Or with Homebrew, once the tap is published:

```sh
brew tap ember-zsh/ember && brew install ember
```

A Homebrew install keeps your own plugins and themes under
`$XDG_DATA_HOME/ember/custom` rather than inside the Cellar, so `brew upgrade`
can't delete them. See [PUBLISHING.md](PUBLISHING.md).

The installer never overwrites anything. An existing `~/.zshrc` is backed up
and Ember's block is *appended* below what you already had, so nothing of yours
is lost — though it does mean Ember loads last and wins where you both define
the same alias. Move those lines below Ember's block to take them back. Run
`sh install.sh --dry-run` first to see exactly what it will do; a dry run
changes nothing and says so on every line.

**Already running oh-my-zsh?** The installer stops and tells you, because the
two don't coexist: both set `PROMPT` from a `precmd` hook, both run `compinit`,
and both bind ZLE widgets, so whichever loads last silently wins while you keep
paying for the other. `sh install.sh --replace-omz` comments out the single
`source $ZSH/oh-my-zsh.sh` line and installs Ember. Your `ZSH_THEME` and
`plugins=()` settings are left alone — they're inert without that line — so
going back is a matter of deleting one comment prefix. Or use
`sh install.sh --no-zshrc` to drop the files in place and wire it up yourself.

Then start a new shell.

## Configure

Everything lives in four lines of `~/.zshrc`:

```zsh
export EMBER="$HOME/.ember"
ember_plugins=(git jump zline extract node python macos)
EMBER_THEME=spark
source "$EMBER/ember.zsh"
```

Anything you write *below* that `source` line wins, so your own aliases and
exports always override Ember's.

## The `ember` command

```
ember list                 what's available, and what's on
ember enable docker        add a plugin to .zshrc and load it right now
ember disable docker       take one out
ember theme quill          switch prompt, live
ember doctor               check the install
ember profile              time every unit loaded at startup
ember new plugin mine      scaffold your own
ember update               pull the latest and rebuild caches
```

`enable` and `theme` edit your `.zshrc` in place (keeping a dated backup) *and*
apply to the shell you're sitting in, so there's no reload step.

## Plugins

| | |
|---|---|
| `git` | `gst`, `gco`, `gcm`, `glg` and friends; `gclean` deletes branches whose upstream is gone; `gwip`/`gunwip` park work in progress; `gmain` returns to the default branch whatever it's called |
| `zline` | inline history suggestions and as-you-type syntax highlighting |
| `jump` | `j proj` goes to the directory you mean, ranked by frequency *and* recency |
| `extract` | `extract anything.{tar.gz,zip,7z,rar,...}`, and `pack` back the other way |
| `node` | `n` dispatches to npm/yarn/pnpm/bun based on the project's lockfile; `node_modules/.bin` follows you; nvm loads lazily |
| `python` | virtualenvs activate on `cd` and deactivate on the way out, without stepping on one you activated yourself |
| `docker` | `dps`, `dsh`, `dc` and the rest; compose v1/v2 resolved on first use |
| `macos` | `cdf` follows Finder, `ql` quick-looks, `caffeine 2h`, `dsclean`, plus Homebrew aliases |

## Themes

`spark` (default) is two lines with async git and command timing. `minimal` is
one line and forks nothing at all. `quill` puts a blank line before each prompt
and git on the right. `bar` draws powerline segments.

## What's different

**Startup stays under ~70ms with eight plugins loaded.** Not by doing less, but
by not paying for things before you need them:

- The completion dump is cached and `zcompile`d, and its security audit runs
  once a day rather than on every shell.
- `ember_lazy` replaces slow version managers (nvm, pyenv) with a stub that
  loads the real thing the first time you call it.
- `ember_defer` runs a unit after the first prompt is on screen.
- No plugin shells out at load time to ask a question whose answer never
  changes. (`docker compose version` alone costs 20ms — that one is resolved
  on first use of `dc` instead.)

`ember profile` shows you exactly where your own startup time goes:

```
$ EMBER_PROFILE=1 zsh -i -c 'ember profile'
startup: 54.8 ms across 19 unit(s)

   10.5 ms  lib:completion               █████
    6.9 ms  lib:aliases                  ███
    5.2 ms  plugin:python                ██
    ...
```

**The prompt never blocks on git.** `ember_async` runs the work in the
background and redraws the prompt in place when the answer arrives. A result
that comes back for a directory you've already left is discarded rather than
shown. In a repository big enough for `git status` to take a second, you get
your prompt immediately and the branch a moment later, instead of waiting.

**Suggestions and highlighting are one plugin, not two.** Both need to own
`region_highlight`, and running the two usual plugins together means one
clobbers the other's colours depending on load order. `zline` computes both in
a single pass per keystroke, so they compose — and the line is redrawn once
instead of twice.

**Git state costs one `git` call.** `ember_git_status` parses
`git status --porcelain=v2 --branch` once and reports staged, dirty, untracked,
conflicted, ahead, behind and stash together, rather than running five separate
commands the way prompt code usually does.

## Writing a plugin

```sh
ember new plugin mine
```

That creates `$EMBER_CUSTOM/plugins/mine/mine.plugin.zsh`. It's just a zsh file
— define functions and aliases in it, and `ember enable mine`. A custom plugin
shadows a bundled one of the same name, so you can replace `git` wholesale
without forking anything.

Themes work the same way (`ember new theme mine`). A theme sets `PROMPT` from a
`precmd` hook and can use `ember_async` to keep slow work off the prompt path.
Read `EMBER_LAST_STATUS` rather than `$?` — by the time your hook runs, `$?`
belongs to the previous hook in the chain.

## Settings

| Variable | Default | |
|---|---|---|
| `EMBER_THEME` | `spark` | prompt theme, or `none` |
| `EMBER_ASYNC` | `1` | set `0` to compute prompt git info synchronously |
| `EMBER_PROFILE` | `0` | record startup timings for `ember profile` |
| `EMBER_QUIET` | `0` | suppress load warnings |
| `EMBER_CUSTOM` | `$EMBER/custom` | where your own plugins and themes live |
| `EMBER_CACHE` | `$XDG_CACHE_HOME/ember` | completion dump, async scratch |
| `EMBER_ZLINE_SUGGEST` | `1` | inline history suggestions |
| `EMBER_ZLINE_HIGHLIGHT` | `1` | syntax highlighting |
| `EMBER_PYTHON_AUTOVENV` | `1` | activate virtualenvs on `cd` |
| `EMBER_DISABLE_AUTO_TITLE` | `0` | leave the terminal title alone |
| `EMBER_HISTFILE` | existing `$HISTFILE`, else `$XDG_STATE_HOME/ember/history` | where history is kept |
| `EMBER_HISTSIZE` / `EMBER_SAVEHIST` | `100000` | history length |

macOS and several Linux distributions ship an `/etc/zshrc` that sets
`HISTFILE`, `HISTSIZE` and `SAVEHIST` before your `~/.zshrc` runs — which is
why a `: ${HISTSIZE:=100000}` in your own config does nothing and you stay
capped at 1000 saved commands. Ember assigns these rather than defaulting them,
so the size actually takes effect. It keeps whatever `HISTFILE` path is already
in use, so your existing history stays where it is.

## Requirements

zsh 5.1 or newer, plus `awk`, `sed` and `grep`. `git` for the git plugin and
`ember update`. `fzf` is optional — `gcob`, `dsh` and `ji` use it when it's
there and fall back to something workable when it isn't.

## Tests

```sh
zsh test/run.zsh
```

82 tests, each in a throwaway `HOME`. Nothing in the suite touches the machine
it runs on.

## License

MIT.
