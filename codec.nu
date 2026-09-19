# Only path ASCII spaces are escaped; optional remote and branch fields are kept verbatim.
def validate-remote [remote: string] {
  if ($remote == "") or ($remote | str starts-with "#") or ($remote | str contains '\') or ($remote =~ '\s') {
    error make {msg: 'remote must be nonempty, cannot start with #, and cannot contain whitespace or backslash'}
  }
}

def validate-branch [branch: string] {
  if ($branch == "") or ($branch | str starts-with "#") or ($branch | str contains '\') or ($branch =~ '\s') {
    error make {msg: 'remote-branch must be nonempty, cannot start with #, and cannot contain whitespace or backslash'}
  }
}

export def encode [entry: record<path: string, fetch_mode: string>] {
  if ($entry.path == "") or ($entry.path | str contains "\r") or ($entry.path | str contains "\n") {
    error make {msg: "path must be nonempty and cannot contain CR/LF"}
  }
  if ($entry.path | str contains '\') {
    error make {msg: 'backslash is only allowed to escape an ASCII space; paths containing backslash are unsupported'}
  }
  if ($entry.path | str starts-with '!') or ($entry.path | str starts-with '?') { error make {msg: "path cannot start with ! or ?"} }
  let prefix = match $entry.fetch_mode {
    "required" => ""
    "skip" => "! "
    "optional" => "? "
    _ => { error make {msg: $"unsupported fetch mode: ($entry.fetch_mode)"} }
  }
  let remote = $entry.remote?
  if $remote != null { validate-remote $remote }
  let suffix = if $remote == null { "" } else { ' ' + $remote }
  let remote_branch = $entry.remote_branch?
  if $remote_branch != null {
    if $remote == null { error make {msg: "remote-branch requires a remote"} }
    validate-branch $remote_branch
  }
  let branch_suffix = if $remote_branch == null { "" } else { ' ' + $remote_branch }
  $prefix + ($entry.path | str replace --all ' ' '\ ') + $suffix + $branch_suffix
}

export def decode [text: string] {
  if ($text | str contains "\r") or ($text | str contains "\n") {
    error make {msg: "input cannot contain CR/LF"}
  }
  let fetch_mode = if ($text | str starts-with '!') { "skip" } else if ($text | str starts-with '?') { "optional" } else { "required" }
  let path_text = if $fetch_mode != "required" {
    if not ($text | str starts-with '! ') and not ($text | str starts-with '? ') {
      error make {msg: "! or ? must be followed by one or more ASCII spaces"}
    }
    $text | str replace --regex '^[!?] +' ''
  } else { $text }
  mut path = ""
  mut escaped = false
  mut in_suffix = false
  mut suffix = ""
  for char in ($path_text | split chars) {
    if $in_suffix {
      $suffix = $suffix + $char
    } else if $escaped {
      if $char != ' ' {
        error make {msg: 'backslash is only allowed to escape an ASCII space'}
      }
      $path = $path + ' '
      $escaped = false
    } else if $char == '\' {
      $escaped = true
    } else if $char == ' ' {
      $in_suffix = true
    } else {
      $path = $path + $char
    }
  }
  if $escaped {
    error make {msg: 'backslash is only allowed to escape an ASCII space; dangling backslash'}
  }
  if $path == "" { error make {msg: "empty path"} }
  if ($path | str starts-with '!') or ($path | str starts-with '?') { error make {msg: "path cannot start with ! or ?"} }
  let tokens = ($suffix | split row ' ' | where { |token| $token != "" } | take while { |token| not ($token | str starts-with "#") })
  if ($tokens | length) > 2 { error make {msg: "expected path [remote [remote-branch]]; extra tokens are unsupported"} }
  let remote = if ($tokens | is-empty) { null } else { $tokens | first }
  if $remote != null { validate-remote $remote }
  let remote_branch = if ($tokens | length) < 2 { null } else { $tokens | get 1 }
  if $remote_branch != null { validate-branch $remote_branch }
  {path: $path, fetch_mode: $fetch_mode, remote: $remote, remote_branch: $remote_branch}
}
