# Only ASCII spaces are escaped; suffixes start at the first unescaped space.
export def encode [entry: record<path: string, fetch_mode: string>] {
  if ($entry.path == "") or ($entry.path | str contains "\r") or ($entry.path | str contains "\n") {
    error make {msg: "path must be nonempty and cannot contain CR/LF"}
  }
  if ($entry.path | str contains '\') {
    error make {msg: 'backslash is only allowed to escape an ASCII space; paths containing backslash are unsupported'}
  }
  if ($entry.path | str starts-with '!') { error make {msg: "path cannot start with !"} }
  let prefix = match $entry.fetch_mode {
    "required" => ""
    "skip" => "! "
    _ => { error make {msg: $"unsupported fetch mode: ($entry.fetch_mode)"} }
  }
  $prefix + ($entry.path | str replace --all ' ' '\ ')
}

export def decode [text: string] {
  if ($text | str contains "\r") or ($text | str contains "\n") {
    error make {msg: "input cannot contain CR/LF"}
  }
  let fetch_mode = if ($text | str starts-with '!') { "skip" } else { "required" }
  let path_text = if $fetch_mode == "skip" {
    if not ($text | str starts-with '! ') {
      error make {msg: "! must be followed by one or more ASCII spaces"}
    }
    $text | str replace --regex '^! +' ''
  } else { $text }
  mut path = ""
  mut escaped = false
  for char in ($path_text | split chars) {
    if $escaped {
      if $char != ' ' {
        error make {msg: 'backslash is only allowed to escape an ASCII space'}
      }
      $path = $path + ' '
      $escaped = false
    } else if $char == '\' {
      $escaped = true
    } else if $char == ' ' {
      break
    } else {
      $path = $path + $char
    }
  }
  if $escaped {
    error make {msg: 'backslash is only allowed to escape an ASCII space; dangling backslash'}
  }
  if $path == "" { error make {msg: "empty path"} }
  if ($path | str starts-with '!') { error make {msg: "path cannot start with !"} }
  {path: $path, fetch_mode: $fetch_mode}
}
