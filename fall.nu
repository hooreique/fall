use codec.nu

const version = "0.3.0"
const fetch_start_gap = 100ms

def fail-with-help [message: string] {
  print --stderr $"(ansi red)($message)(ansi reset)\n\n  (ansi attr_bold)fall --help(ansi reset)  to get help\n"
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
      {valid: true, path: $repo, fetch_mode: $decoded.fetch_mode, events: []}
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
    "# Write one path per line. Use absolute paths.
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
# Escape ASCII spaces with \\ . The first unescaped space starts an ignored suffix.
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

def dirtycheck [repo: string, fetch: bool, fetch_mode: string] {
  let git_options = (git-options)

  let inside = (^git ...$git_options -C $repo rev-parse --is-inside-work-tree | complete)
  if $inside.exit_code != 0 {
    return [(event "err" $"($repo) (ansi red)not a git repo(ansi reset)")]
  }

  mut events = []
  if $fetch {
    let result = (^git ...$git_options -C $repo fetch | complete)
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
          dirtycheck $item.path $item.fetch $item.fetch_mode
        } else {
          $item.events
        }
        emit $events
        $events
      }
    | reduce --fold [] { |item, acc| $acc ++ $item }
}

def help-message [] {
  $"(ansi attr_bold)fall(ansi reset) – (ansi attr_bold)(ansi attr_underline)F(ansi reset)etch (ansi attr_bold)(ansi attr_underline)ALL(ansi reset) git repositories

Run without arguments to fetch enabled repositories in (ansi blue)repos.conf(ansi reset) and display
its status. (ansi dark_gray)Under the hood,  (ansi attr_bold)fall(ansi reset)  (ansi dark_gray)simply  iterates  over  each  repository  and
executes

  (ansi yellow)git fetch && git status(ansi dark_gray)

(ansi attr_bold)fall(ansi reset) (ansi dark_gray)just makes the process quicker and the output easier to read.(ansi reset)

(ansi attr_bold)(ansi attr_underline)Usage(ansi reset)
  (ansi attr_bold)fall(ansi reset)            Fetch enabled repositories and show all statuses
  (ansi attr_bold)fall(ansi reset) (ansi cyan)--help(ansi reset)     Show this help message
  (ansi attr_bold)fall(ansi reset) (ansi cyan)--version(ansi reset)  Show the program version
  (ansi attr_bold)fall(ansi reset) (ansi green)show(ansi reset)       Display the contents of (ansi blue)repos.conf(ansi reset)
  (ansi attr_bold)fall(ansi reset) (ansi green)add(ansi reset)        Add the current directory to (ansi blue)repos.conf(ansi reset) (ansi dark_gray)\(creates the  file  if
                  it does not exist)(ansi reset)
  (ansi attr_bold)fall(ansi reset) (ansi green)edit(ansi reset)       Open (ansi blue)repos.conf(ansi reset) in your $EDITOR (ansi dark_gray)\(creates the file if  it  does
                  not exist)(ansi reset)
  (ansi attr_bold)fall(ansi reset) (ansi green)prev(ansi reset)       Show the result of previous (ansi attr_bold)fall(ansi reset) with datetime
  (ansi attr_bold)fall(ansi reset) (ansi green).(ansi reset)          Use the nearest (ansi magenta).repos.conf(ansi reset) file from  the  current  directory
                  instead of the global (ansi blue)repos.conf(ansi reset) (ansi dark_gray)\(accepts relative paths, does
                  not write prev.txt)(ansi reset)

  fall test       Validate the global config without fetch/status or state changes
  fall test .     Validate the nearest .repos.conf; print its absolute path first
  fall status     Show all global statuses without fetching; update prev.txt
  fall status .   Show nearest .repos.conf statuses without fetching or writing prev.txt

Prefix a path with ! and one or more ASCII spaces to skip its fetch in normal runs.
Prefix with ? to fetch and, on fetch failure, warn and continue showing local status.
Prefixes must start the line and use one or more ASCII spaces, never a tab.
Empty paths, nested prefixes, and paths starting with ! or ? are unsupported.
Only fetch failures are tolerated; config, path, and repository validation still applies.
Ahead/behind counts use locally stored remote-tracking information, possibly stale
after a failed or skipped fetch. Global runs save warnings and statuses to prev.txt.
Paths escape ASCII spaces with \\ . The first unescaped space starts an ignored suffix.
Backslashes in paths and CR/LF are unsupported. Tabs and quotes are literal.
Blank lines and lines whose first non-whitespace character is # are ignored.
Global paths must be absolute or start with ~/. Local paths are relative to the config.
Root and trailing slashes are unsupported. Maximum: 100 lines including comments.
Test succeeds only when all entries are Git roots and the file has at most 100 lines.

(ansi attr_bold)(ansi attr_underline)File locations(ansi reset) (ansi dark_gray)– handled automatically, but feel free to edit them yourself(ansi reset)
  $HOME/.config/fall/(ansi blue)repos.conf(ansi reset)
  $HOME/.local/state/fall/prev.txt"
}

def --wrapped main [...raw_args] {
  let args = if (($raw_args | length) > 0) and (($raw_args | get 0) == "--") {
    $raw_args | skip 1
  } else {
    $raw_args
  }

  if (($args | length) > 1) and ($args != ["test" "."]) and ($args != ["status" "."]) {
    fail-with-help $"too many args: ($args | str join ' ')"
  }

  if (($args | length) == 1) and (($args | get 0) == "--help") {
    print (help-message)
    return
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
