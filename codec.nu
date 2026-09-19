# Only ASCII spaces are escaped; suffixes start at the first unescaped space.
export def encode [entry: record<path: string>] {
  if ($entry.path == "") or ($entry.path | str contains "\r") or ($entry.path | str contains "\n") {
    error make {msg: "path must be nonempty and cannot contain CR/LF"}
  }
  if ($entry.path | str contains '\') {
    error make {msg: 'backslash is only allowed to escape an ASCII space; paths containing backslash are unsupported'}
  }
  $entry.path | str replace --all ' ' '\ '
}

export def decode [text: string] {
  if ($text | str contains "\r") or ($text | str contains "\n") {
    error make {msg: "input cannot contain CR/LF"}
  }
  mut path = ""
  mut escaped = false
  for char in ($text | split chars) {
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
  {path: $path}
}
