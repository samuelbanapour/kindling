# plugins/extract — one command for every archive format.
#
#   extract foo.tar.gz            # into ./foo
#   extract foo.zip --into build  # into ./build
#   extract *.tar.xz              # each into its own directory

extract() {
  emulate -L zsh
  setopt local_options no_case_glob

  local -a files
  local into=""
  while (( $# )); do
    case $1 in
      (--into) into=$2; shift 2 ;;
      (-h|--help)
        print -- "usage: extract <archive>... [--into <dir>]"; return 0 ;;
      (*) files+=("$1"); shift ;;
    esac
  done

  (( ${#files} )) || { print -ru2 -- "extract: no archive given"; return 1 }

  local file target rc=0
  for file in "${files[@]}"; do
    if [[ ! -r $file ]]; then
      print -ru2 -- "extract: cannot read '$file'"; rc=1; continue
    fi

    # Strip every extension the name carries: foo.tar.gz -> foo
    target=${into:-${${file:t}%%.(tar.*|t[gbx]z|*)}}
    command mkdir -p -- "$target" || { rc=1; continue }

    case ${file:l} in
      (*.tar.gz|*.tgz)    tar xzf   "$file" -C "$target" ;;
      (*.tar.bz2|*.tbz2)  tar xjf   "$file" -C "$target" ;;
      (*.tar.xz|*.txz)    tar xJf   "$file" -C "$target" ;;
      (*.tar.zst|*.tzst)  tar --zstd -xf "$file" -C "$target" ;;
      (*.tar)             tar xf    "$file" -C "$target" ;;
      (*.zip|*.jar|*.war|*.ipa|*.apk|*.xpi|*.whl)
                          unzip -q  "$file" -d "$target" ;;
      (*.rar)             unrar x -idq "$file" "$target/" ;;
      (*.7z)              7z x -bso0 "-o$target" "$file" ;;
      (*.gz)              gunzip -c "$file" > "$target/${${file:t}%.gz}" ;;
      (*.bz2)             bunzip2 -c "$file" > "$target/${${file:t}%.bz2}" ;;
      (*.xz)              unxz -c   "$file" > "$target/${${file:t}%.xz}" ;;
      (*.zst)             zstd -dc  "$file" > "$target/${${file:t}%.zst}" ;;
      (*.dmg)             hdiutil attach "$file" ;;
      (*)
        print -ru2 -- "extract: don't know how to handle '$file'"
        rmdir "$target" 2>/dev/null
        rc=1; continue ;;
    esac || { rc=1; continue }

    # An archive with a single top-level directory ends up doubly nested.
    # Flatten that, since it's almost never what you wanted.
    local -a entries=("$target"/*(ND))
    if (( ${#entries} == 1 )) && [[ -d ${entries[1]} && -z $into ]]; then
      local inner=${entries[1]}
      command mv -- "$inner"/*(DN) "$target"/ 2>/dev/null && rmdir "$inner" 2>/dev/null
    fi

    print -r -- "${file} -> ${target}/"
  done
  return $rc
}

# pack <name> <path>... — the inverse, picking the format from <name>.
pack() {
  local out=$1; shift
  (( $# )) || { print -ru2 -- "usage: pack <archive> <path>..."; return 1 }
  case ${out:l} in
    (*.tar.gz|*.tgz)   tar czf "$out" "$@" ;;
    (*.tar.bz2)        tar cjf "$out" "$@" ;;
    (*.tar.xz)         tar cJf "$out" "$@" ;;
    (*.tar)            tar cf  "$out" "$@" ;;
    (*.zip)            zip -qr "$out" "$@" ;;
    (*.7z)             7z a -bso0 "$out" "$@" ;;
    (*) print -ru2 -- "pack: unknown format for '$out'"; return 1 ;;
  esac && print -r -- "-> $out"
}

alias x='extract'
