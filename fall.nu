use codec.nu

const version = "0.3.0"
const fetch_start_gap = 100ms

def fail-with-help [message: string, topic: string = ""] {
  let command = if $topic == "" { "fall" } else { $"fall ($topic)" }
  print --stderr $"(ansi red)($message)(ansi reset)\n\n  (ansi attr_bold)($command) --help(ansi reset)  to get help\n"
  exit 1
}

def fail [message: string] {
  print --stderr $"(ansi red)($message)(ansi reset)"
  exit 1
}

def event [stream: string, text: string] {
  { stream: $stream, text: $text }
}

def text-to-events [stream: string, text: string] {
  if $text == "" {
    []
  } else {
    $text | lines | each { |line| event $stream $line }
  }
}

def emit [events: list] {
  for e in $events {
    if $e.stream == "err" {
      print --stderr $e.text
    } else {
      print $e.text
    }
  }
}

def save-prev [prev: string, events: list] {
  let lines = ($events | get text)
  let content = if ($lines | is-empty) {
    ""
  } else {
    (($lines | str join "\n") + "\n")
  }

  $content | ansi strip | save --force $prev
}

def path-is-dir [path: string] {
  try {
    (($path | path expand --strict | path type) == "dir")
  } catch {
    false
  }
}

def path-is-file [path: string] {
  try {
    (($path | path expand --strict | path type) == "file")
  } catch {
    false
  }
}

# Split only on LF so the codec can reject CR without losing source text.
def read-config [file: string] {
  let raw = (open --raw $file)
  let rows = if $raw == "" { [] } else {
    let split = ($raw | split row "\n")
    if ($raw | str ends-with "\n") { $split | drop } else { $split }
  }
  {raw: $raw, count: ($rows | length), entries: ($rows | enumerate | where { |row|
    let trimmed = ($row.item | str trim)
    ($trimmed != "") and not ($trimmed | str starts-with "#")
  } | each { |row| {line: ($row.index + 1), raw: $row.item} })}
}

def diagnostic [file: string, entry: record, reason: string] {
  $"($file):($entry.line): [($entry.raw)]: ($reason)"
}

def resolve-repo [path: string, local: bool, root: string, home: string] {
  let expanded = (expand-home $path $home)
  if $expanded == "/" { error make {msg: "root\(/) not supported"} }
  if ($path | str ends-with "/") { error make {msg: "trailing slash\(/) not supported"} }
  if $local and (($path | str starts-with "/") or ($path | str starts-with "~/")) {
    error make {msg: "not a relative path"}
  }
  if (not $local) and not ($expanded | str starts-with "/") {
    error make {msg: "not an absolute path; use / or ~/"}
  }
  let repo = if $local { $root | path join $path } else { $expanded }
  if not (path-is-dir $repo) {
    error make {msg: ('directory not found: ' + $repo + '. 경로에 공백이 포함되어 있다면 escape되지 않은 공백이 원인일 수 있습니다. 해당하는 경우 공백을 `\ `로 작성하세요.')}
  }
  let canonical = ($repo | path expand --strict)
  if $canonical == "/" { error make {msg: "root\(/) not supported"} }
  $canonical
}

def require-git-root [repo: string] {
  let result = (^git -C $repo rev-parse --show-toplevel | complete)
  if $result.exit_code != 0 {
    error make {msg: "not a Git working repository root (bare repositories are unsupported)"}
  }
  if (($result.stdout | str replace --regex '\n$' '' | path expand --strict) != $repo) {
    error make {msg: "not a Git repository root (repository subdirectories are unsupported)"}
  }
}

def config-items [file: string, config: record, local: bool, root: string, home: string] {
  $config.entries | each { |entry|
    try {
      let decoded = (codec decode $entry.raw)
      let repo = (resolve-repo $decoded.path $local $root $home)
      require-git-root $repo
      if $decoded.remote != null {
        let remotes = (^git -C $repo remote | complete)
        if $remotes.exit_code != 0 { error make {msg: "could not list Git remotes"} }
        if not ($decoded.remote in ($remotes.stdout | lines)) {
          error make {msg: $"unregistered remote: ($decoded.remote)"}
        }
      }
      {valid: true, path: $repo, fetch_mode: $decoded.fetch_mode, remote: $decoded.remote, events: []}
    } catch { |err|
      {valid: false, path: "", events: [(event "err" (diagnostic $file $entry $err.msg))]}
    }
  }
}

def nearest-config [] {
  mut dir = (pwd)
  loop {
    let candidate = ($dir | path join ".repos.conf")
    if ($candidate | path exists) { return $candidate }
    if $dir == "/" { error make {msg: ".repos.conf not found up to filesystem root"} }
    $dir = ($dir | path dirname)
  }
}

def test-config [file: string, local: bool, home: string] {
  let config = try { read-config $file } catch { |err| fail $"($file): ($err.msg)" }
  let items = (config-items $file $config $local ($file | path dirname) $home)
  let failed = ($items | where { |item| not $item.valid } | length)
  for item in $items { emit $item.events }
  if $config.count > 100 {
    print --stderr (diagnostic $file {line: 101, raw: ($config.raw | split row "\n" | get 100)} $"line limit exceeded: ($config.count) lines; maximum is 100")
  }
  print $"Checked: ($items | length), succeeded: (($items | length) - $failed), failed: ($failed); file lines: ($config.count)"
  if ($failed > 0) or ($config.count > 100) { exit 1 }
}

def expand-home [path: string, home: string] {
  if ($path | str starts-with "~/") {
    $path | str replace "~/" $"($home)/"
  } else {
    $path
  }
}

def ensure-config-file [dir: string, file: string] {
  if (($dir | path exists) and not (path-is-dir $dir)) {
    fail "~/.config/fall already exists but it is not a directory"
  }

  if (($file | path exists) and not (path-is-file $file)) {
    fail "repos.conf already exists but it is not a file"
  }

  mkdir $dir

  if not (path-is-file $file) {
    "# Write [prefix]path [remote] per line. Use absolute paths.
# Starting with # means comments.
#/path/to/repo
# Prefix a path with ! and ASCII spaces to skip fetch for that repository.
#! /path/to/offline-repo
# Prefix with ? and ASCII spaces to fetch but show local status on fetch failure.
#? /path/to/occasionally-unreachable-repo
# After fetch failure, ahead/behind counts use locally stored information.
# fall status skips all fetches; fall status . uses the nearest .repos.conf.

# You cannot use $HOME. Use ~ instead.
#~/cool\\ stuff
# Escape path ASCII spaces with \\ . Optionally append one registered remote name.
#? ~/my\\ repo upstream
# Remote names are literal: no whitespace or backslash. Extra tokens are errors.
# Suffixes are no longer ignored. Omit remote to keep Git default fetch selection.
# Remotes are validated even for !, ?, status and test; status uses the upstream.
# Backslashes in paths and CR/LF are unsupported. Run fall test to validate.
" | save --force $file
  }
}

def ago [prev: string] {
  let mtime = (ls $prev | get 0.modified)
  let diff = (((date now | into int) - ($mtime | into int)) / 1000000000 | math floor)

  if $diff < 60 {
    return "just now"
  }

  if $diff < 3600 {
    return $"($diff / 60 | math floor) minutes ago"
  }

  if $diff < 21600 {
    return $"($diff / 3600 | math floor) hours ago"
  }

  $mtime | format date "%Y-%m-%dT%H:%M:%S%:z"
}

def git-options [] {
  let ssh = ($env.FALL_GIT_SSH_COMMAND? | default "")

  if $ssh == "" {
    []
  } else {
    ["-c" $"core.sshCommand=($ssh)"]
  }
}

def dirtycheck [repo: string, fetch: bool, fetch_mode: string, remote: any] {
  let git_options = (git-options)

  let inside = (^git ...$git_options -C $repo rev-parse --is-inside-work-tree | complete)
  if $inside.exit_code != 0 {
    return [(event "err" $"($repo) (ansi red)not a git repo(ansi reset)")]
  }

  mut events = []
  if $fetch {
    let fetch_args = if $remote == null { [] } else { ["--" $remote] }
    let result = (^git ...$git_options -C $repo fetch ...$fetch_args | complete)
    if ($result.exit_code != 0) and ($fetch_mode == "optional") {
      $events = [(event "err" $"($repo) (ansi yellow)fetch failed; showing local status(ansi reset)")]
    } else {
      $events = ((text-to-events "out" $result.stdout) ++ (text-to-events "err" $result.stderr))
      if $result.exit_code != 0 {
        $events = ($events ++ [(event "err" $"($repo) (ansi red)error occurred(ansi dark_gray); Try again later.(ansi reset)")])
        return $events
      }
    }
  }

  let lb = (^git ...$git_options -C $repo branch --show-current | complete | get stdout | str trim)
  let rb_result = (^git ...$git_options -C $repo rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" | complete)
  let rb = if $rb_result.exit_code == 0 { $rb_result.stdout | str trim } else { "" }

  mut stat = $"($repo) \((ansi blue)($lb)"
  if $rb != "" {
    $stat = $"($stat)(ansi reset),(ansi magenta)($rb)"
  }
  $stat = $"($stat)(ansi reset))"
  let before = $stat

  let status = (^git ...$git_options -C $repo status --porcelain=v2 --branch | complete)
  $events = ($events ++ (text-to-events "err" $status.stderr))
  for line in ($status.stdout | lines) {
    if not ($line | str starts-with "#") {
      $stat = $"($stat) (ansi yellow)±(ansi reset)"
      break
    } else if $line == "# branch.ab +0 -0" {
      continue
    } else if ($line | str starts-with "# branch.ab ") {
      $stat = $"($stat) (ansi dark_gray)($line | str substring 12..)(ansi reset)"
    }
  }

  if $stat == $before {
    $stat = $"($stat) (ansi green)clean(ansi reset)"
  }

  $events ++ [(event "out" $stat)]
}

def run-checks [items: list, offline: bool] {
  mut fetch_index = 0
  mut scheduled = []
  for item in $items {
    let fetch = if $item.valid {
      match $item.fetch_mode {
        "required" => (not $offline)
        "optional" => (not $offline)
        "skip" => false
        _ => { error make {msg: $"unsupported fetch mode: ($item.fetch_mode)"} }
      }
    } else { false }
    let delay = if $fetch and ($fetch_index < 4) { $fetch_index * $fetch_start_gap } else { 0ms }
    if $fetch { $fetch_index = $fetch_index + 1 }
    $scheduled = ($scheduled | append ($item | insert fetch $fetch | insert delay $delay))
  }
  $scheduled
    | par-each --keep-order --threads 4 { |item|
        let events = if $item.valid {
          if $item.fetch { sleep $item.delay }
          dirtycheck $item.path $item.fetch $item.fetch_mode $item.remote
        } else {
          $item.events
        }
        emit $events
        $events
      }
    | reduce --fold [] { |item, acc| $acc ++ $item }
}

def help-message [topic: string = ""] {
  let usage = $"(ansi attr_bold)(ansi attr_underline)Usage(ansi reset)"
  let fall = $"(ansi attr_bold)fall(ansi reset)"
  let global = $"$HOME/.config/fall/(ansi blue)repos.conf(ansi reset)"
  let local = $"(ansi magenta).repos.conf(ansi reset)"
  let prev = $"$HOME/.local/state/fall/(ansi blue)prev.txt(ansi reset)"
  match $topic {
    "" => $"($fall) – (ansi attr_bold)(ansi attr_underline)F(ansi reset)etch (ansi attr_bold)(ansi attr_underline)ALL(ansi reset) git repositories

Run without arguments to fetch enabled repositories and show all statuses.
Uses ($global); saves results to ($prev).

($usage)
  ($fall)            Fetch enabled repositories and show all statuses
  ($fall) (ansi green)show(ansi reset)       Display the contents of (ansi blue)repos.conf(ansi reset)
  ($fall) (ansi green)add(ansi reset)        Add the current directory to (ansi blue)repos.conf(ansi reset)
  ($fall) (ansi green)edit(ansi reset)       Open (ansi blue)repos.conf(ansi reset) in your $EDITOR
  ($fall) (ansi green)prev(ansi reset)       Show the result of previous ($fall) with datetime
  ($fall) (ansi green).(ansi reset)          Fetch and show statuses using the nearest ($local)
  ($fall) (ansi green)status(ansi reset)     Show all statuses without fetching
  ($fall) (ansi green)test(ansi reset)       Validate the config without state changes
  ($fall) (ansi cyan)--help(ansi reset)     Show this help message
  ($fall) (ansi cyan)--version(ansi reset)  Show the program version

(ansi dark_gray)Use(ansi reset) ($fall) (ansi green)<command>(ansi reset) (ansi cyan)--help(ansi reset) (ansi dark_gray)for details, e.g.(ansi reset) ($fall) (ansi green)status(ansi reset) (ansi cyan)--help(ansi reset).
(ansi dark_gray)Local modes also have help:(ansi reset) ($fall) (ansi green)status .(ansi reset) (ansi cyan)--help(ansi reset), ($fall) (ansi green)test .(ansi reset) (ansi cyan)--help(ansi reset)."
    "show" => $"($usage)
  ($fall) (ansi green)show(ansi reset)

Display the contents of the global config, with comments in gray.
File: ($global)
(ansi dark_gray)The file must already exist; use(ansi reset) ($fall) (ansi green)add(ansi reset) (ansi dark_gray)or(ansi reset) ($fall) (ansi green)edit(ansi reset) (ansi dark_gray)to create it.(ansi reset)"
    "add" => $"($usage)
  ($fall) (ansi green)add(ansi reset)

Add the current directory to ($global).
Creates the config file if it does not exist; escapes spaces in the path.
Adds an ordinary entry with required fetch and no explicit remote.
Duplicates are skipped using decoded paths, expanding ~/ regardless of prefix or remote.
(ansi dark_gray)Existing decoding errors prevent adding an entry.(ansi reset)"
    "edit" => $"($usage)
  ($fall) (ansi green)edit(ansi reset)

Open ($global) in $EDITOR \(default: vi).
Creates the config file if it does not exist.

(ansi attr_bold)(ansi attr_underline)Config syntax(ansi reset)
  [prefix]path [remote]
  ? ~/my\\ repo upstream
  ! ~/offline-repo

Global paths must be absolute or start with ~/. Escape ASCII spaces with \\ .
Prefix with ! and ASCII spaces to skip fetch; ? to fetch and show local status on failure.
An optional registered remote selects what to fetch; status always uses the upstream.
Blank lines and lines whose first non-whitespace character is # are ignored.
Maximum: 100 lines including comments. Use ($fall) (ansi green)test(ansi reset) to validate.
(ansi dark_gray)See README's Config section for all path, prefix, remote, and validation rules.(ansi reset)"
    "prev" => $"($usage)
  ($fall) (ansi green)prev(ansi reset)

Show the saved result of the previous global run with its age or datetime.
File: ($prev)
(ansi dark_gray)Global fetch and status runs save results; local runs do not update this file.(ansi reset)"
    "." => $"($usage)
  ($fall) (ansi green).(ansi reset)

Fetch enabled repositories and show statuses using the nearest ($local).
Searches from the current directory upwards to the filesystem root.
Paths are relative to the directory containing the selected config.
Does not save results to (ansi blue)prev.txt(ansi reset).
(ansi dark_gray)Use(ansi reset) ($fall) (ansi green)status .(ansi reset) (ansi dark_gray)to skip fetch, or(ansi reset) ($fall) (ansi green)test .(ansi reset) (ansi dark_gray)to validate.(ansi reset)"
    "status" => $"($usage)
  ($fall) (ansi green)status(ansi reset)
  ($fall) (ansi green)status .(ansi reset)

Show all statuses without fetching, regardless of fetch prefixes.
Global mode uses ($global) and saves results to ($prev).
Local mode uses the nearest ($local) and does not save results.
(ansi dark_gray)Ahead/behind counts use locally stored remote-tracking information, possibly stale.
Status follows the branch's upstream, even when a different fetch remote is configured.(ansi reset)
Use ($fall) (ansi green)status .(ansi reset) (ansi cyan)--help(ansi reset) for local path and discovery rules."
    "status ." => $"($usage)
  ($fall) (ansi green)status .(ansi reset)

Show all statuses without fetching, regardless of fetch prefixes.
Searches from the current directory upwards for the nearest ($local).
Paths are relative to the directory containing the selected config.
Does not save results to (ansi blue)prev.txt(ansi reset).
(ansi dark_gray)Ahead/behind counts use locally stored remote-tracking information, possibly stale.
Status follows the branch's upstream, even when a different fetch remote is configured.(ansi reset)"
    "test" => $"($usage)
  ($fall) (ansi green)test(ansi reset)
  ($fall) (ansi green)test .(ansi reset)

Validate ($global); use ($fall) (ansi green)test .(ansi reset) for the nearest ($local).
Checks syntax, paths, Git repository roots, and registered remote names.
Exit 0: all entries valid and at most 100 lines, including blanks and comments.
Exit 1: invalid entries, missing/unreadable config, or more than 100 lines.
Does not fetch, run Git status, or create/change config or state files.
(ansi dark_gray)Prints diagnostics and checked/succeeded/failed counts; an empty config succeeds.(ansi reset)
Use ($fall) (ansi green)test .(ansi reset) (ansi cyan)--help(ansi reset) for local path and discovery rules."
    "test ." => $"($usage)
  ($fall) (ansi green)test .(ansi reset)

Searches from the current directory upwards for the nearest ($local).
Prints its absolute path first; entry paths are relative to its directory.
Checks syntax, paths, Git repository roots, and registered remote names.
Exit 0: all entries valid and at most 100 lines, including blanks and comments.
Exit 1: invalid entries, missing/unreadable config, or more than 100 lines.
Does not fetch, run Git status, or create/change config or state files.
(ansi dark_gray)Prints diagnostics and checked/succeeded/failed counts; an empty config succeeds.(ansi reset)"
  }
}

def --wrapped main [...raw_args] {
  let args = if (($raw_args | length) > 0) and (($raw_args | get 0) == "--") {
    $raw_args | skip 1
  } else {
    $raw_args
  }

  let commands = ["show" "add" "edit" "prev" "." "status" "test"]
  let first = ($args | first | default "")
  let help_topic = ($args | drop | str join " ")
  if (($args | last | default "") == "--help") and (
    ($args == ["--help"]) or
    ((($args | length) == 2) and ($first in $commands)) or
    ($args == ["status" "." "--help"]) or ($args == ["test" "." "--help"])
  ) {
    print (help-message $help_topic)
    return
  }

  if (($args | length) > 1) and ($args != ["test" "."]) and ($args != ["status" "."]) {
    let topic = if $first in $commands { $first } else { "" }
    fail-with-help $"too many args: ($args | str join ' ')" $topic
  }

  if (($args | length) == 1) and (($args | get 0) == "--version") {
    print $version
    return
  }

  let home = $env.HOME
  let file = $"($home)/.config/fall/repos.conf"
  let config_dir = $"($home)/.config/fall"

  if (($args | first | default "") == "test") {
    let local = ($args == ["test" "."])
    let selected = if $local {
      try { nearest-config } catch { |err| fail $err.msg }
    } else { $file }
    if $local { print $".repos.conf at: ($selected)" }
    test-config $selected $local $home
    return
  }

  if (($args | length) == 1) and (($args | get 0) == "show") {
    if not (path-is-file $file) {
      fail-with-help "repos.conf not found"
    }

    print (
      open --raw $file
        | lines
        | each { |line|
            if ($line | str trim --left | str starts-with "#") {
              $"(ansi dark_gray)($line)(ansi reset)"
            } else {
              $line
            }
          }
        | str join "\n"
    )
    return
  }

  if (($args | length) == 1) and (($args | get 0) == "add") {
    let cwd = (pwd)
    if $cwd == "/" {
      fail $"root\((ansi reset)/(ansi red)) not supported"
    }

    ensure-config-file $config_dir $file

    let encoded = try { codec encode {path: $cwd, fetch_mode: "required"} } catch { |err| fail $err.msg }
    let config = try { read-config $file } catch { |err| fail $"($file): ($err.msg)" }
    let decoded = ($config.entries | each { |entry|
      try {
        {valid: true, path: (codec decode $entry.raw).path}
      } catch { |err|
        print --stderr (diagnostic $file $entry $err.msg)
        {valid: false, path: ""}
      }
    })
    if ($decoded | any { |entry| not $entry.valid }) { exit 1 }
    let duplicate = ($decoded | any { |entry| (expand-home $entry.path $home) == $cwd })

    if $duplicate {
      print $"($cwd) (ansi yellow)duplicate(ansi dark_gray); skipping(ansi reset)"
    } else {
      let separator = if ($config.raw != "") and not ($config.raw | str ends-with "\n") { "\n" } else { "" }
      $"($separator)($encoded)\n" | save --append $file
      print $"($cwd) (ansi green)added(ansi reset)"
    }
    return
  }

  if (($args | length) == 1) and (($args | get 0) == "edit") {
    ensure-config-file $config_dir $file
    let editor = ($env.EDITOR? | default "vi")
    ^$editor $file
    return
  }

  let offline = (($args | first | default "") == "status")
  if ($args == ["."]) or ($args == ["status" "."]) {
    let dotfile = try { nearest-config } catch { |err| fail $err.msg }
    let dotroot = ($dotfile | path dirname)
    let config = try { read-config $dotfile } catch { |err| fail $"($dotfile): ($err.msg)" }
    if $config.count > 100 { fail $"($dotfile): too big; ($config.count) lines, maximum is 100" }
    print $"(ansi dark_gray)falling from ($dotroot)... Please wait(ansi reset)"
    let items = (config-items $dotfile $config true $dotroot $home)

    let events = (run-checks $items $offline)

    if (($items | where valid | length) == 0) {
      print $"(ansi yellow)There is no repo to fall into.(ansi reset)\n\n  (ansi attr_bold)cat '($dotfile)'(ansi reset)  to check the input\n"
    }
    return
  }

  if (($args | length) == 1) and (($args | get 0) != "prev") and not $offline {
    fail-with-help $"unknown option: ($args | get 0)"
  }

  let prevdir = $"($home)/.local/state/fall"
  let prev = $"($prevdir)/prev.txt"

  if (($prevdir | path exists) and not (path-is-dir $prevdir)) {
    fail "~/.local/state/fall already exists but it is not a directory"
  }

  if (($prev | path exists) and not (path-is-file $prev)) {
    fail "~/.local/state/fall/prev.txt already exists but it is not a file"
  }

  mkdir $prevdir

  if $args == ["prev"] {
    if (path-is-file $prev) {
      print $"(ansi dark_gray)(ago $prev)(ansi reset)"
      print --no-newline (open --raw $prev)
      return
    }

    fail-with-help $"~/.local/state/fall/prev.txt not found(ansi dark_gray); This may indicate that you have never executed (ansi green)fall(ansi dark_gray).(ansi reset)"
  }

  if not (path-is-file $file) {
    fail-with-help "repos.conf not found"
  }

  let config = try { read-config $file } catch { |err| fail $"($file): ($err.msg)" }
  if $config.count > 100 { fail $"($file): too big; ($config.count) lines, maximum is 100" }
  print $"(ansi dark_gray)falling... Please wait(ansi reset)"
  let items = (config-items $file $config false ($file | path dirname) $home)

  mut events = (run-checks $items $offline)
  if (($items | where valid | length) == 0) {
    let no_repo_event = (event "out" $"(ansi yellow)There is no repo to fall into.(ansi reset)\n\n  (ansi attr_bold)fall --help(ansi reset)  to get help\n")
    emit [$no_repo_event]
    $events = ($events ++ [$no_repo_event])
  }

  save-prev $prev $events
}
