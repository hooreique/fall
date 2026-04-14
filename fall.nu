const version = "0.3.0"

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

def trimmed-lines [path: string] {
  open --raw $path | lines | each { |line| $line | str trim }
}

def config-entries [path: string] {
  trimmed-lines $path | where { |line|
    not (($line == "") or ($line | str starts-with "#"))
  }
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

# You cannot use $HOME. Use ~ instead.
#~/cool stuff
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

def dirtycheck [repo: string] {
  let git_dir = $"--git-dir=($repo)/.git"
  let work_tree = $"--work-tree=($repo)"
  let git_options = (git-options)

  let inside = (^git ...$git_options $git_dir $work_tree rev-parse --is-inside-work-tree | complete)
  if $inside.exit_code != 0 {
    return [(event "err" $"($repo) (ansi red)not a git repo(ansi reset)")]
  }

  let fetch = (^git ...$git_options $git_dir $work_tree fetch | complete)
  mut events = ((text-to-events "out" $fetch.stdout) ++ (text-to-events "err" $fetch.stderr))
  if $fetch.exit_code != 0 {
    $events = ($events ++ [(event "err" $"($repo) (ansi red)error occurred(ansi dark_gray); Try again later.(ansi reset)")])
    return $events
  }

  let lb = (^git ...$git_options $git_dir $work_tree branch --show-current | complete | get stdout | str trim)
  let rb_result = (^git ...$git_options $git_dir $work_tree rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" | complete)
  let rb = if $rb_result.exit_code == 0 { $rb_result.stdout | str trim } else { "" }

  mut stat = $"($repo) \((ansi blue)($lb)"
  if $rb != "" {
    $stat = $"($stat)(ansi reset),(ansi magenta)($rb)"
  }
  $stat = $"($stat)(ansi reset))"
  let before = $stat

  let status = (^git ...$git_options $git_dir $work_tree status --porcelain=v2 --branch | complete)
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

def run-checks [items: list] {
  $items
    | par-each --threads 4 { |item|
        if $item.valid {
          dirtycheck $item.path
        } else {
          $item.events
        }
      }
    | reduce --fold [] { |item, acc| $acc ++ $item }
}

def help-message [] {
  $"(ansi attr_bold)fall(ansi reset) – (ansi attr_bold)(ansi attr_underline)F(ansi reset)etch (ansi attr_bold)(ansi attr_underline)ALL(ansi reset) git repositories

Run without arguments to fetch every repository listed in (ansi blue)repos.conf(ansi reset) and display
its status. (ansi dark_gray)Under the hood,  (ansi attr_bold)fall(ansi reset)  (ansi dark_gray)simply  iterates  over  each  repository  and
executes

  (ansi yellow)git fetch && git status(ansi dark_gray)

(ansi attr_bold)fall(ansi reset) (ansi dark_gray)just makes the process quicker and the output easier to read.(ansi reset)

(ansi attr_bold)(ansi attr_underline)Usage(ansi reset)
  (ansi attr_bold)fall(ansi reset)            Fetch all repositories
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

  if ($args | length) > 1 {
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

    let duplicate = (
      config-entries $file
        | any { |line| (expand-home $line $home) == $cwd }
    )

    if $duplicate {
      print $"($cwd) (ansi yellow)duplicate(ansi dark_gray); skipping(ansi reset)"
    } else {
      $"($cwd)\n" | save --append $file
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

  if (($args | length) == 1) and (($args | get 0) == ".") {
    mut dotdir = (pwd)
    mut dotfile = ""

    loop {
      let candidate = $"($dotdir)/.repos.conf"
      if (path-is-file $candidate) {
        $dotfile = $candidate
        break
      }

      if $dotdir == "/" {
        print --stderr $"(ansi red).repos.conf not found up to filesystem root(ansi dark_gray); To use it, you need to create a .repos.conf file yourself.(ansi reset)"
        exit 1
      }

      $dotdir = ($dotdir | path dirname)
    }

    let dotroot = $dotdir
    let dotlines = (open --raw $dotfile | lines | length)
    if $dotlines >= 100 {
      print --stderr $"(ansi red)too big(ansi dark_gray); The ($dotfile) file has ($dotlines) lines. Please make it less than 100.(ansi reset)"
      exit 1
    }

    print $"(ansi dark_gray)falling from ($dotroot)... Please wait(ansi reset)"

    let items = (
      config-entries $dotfile
        | each { |rel|
            if (($rel | str starts-with "/") or ($rel | str starts-with "~/")) {
              { valid: false, path: "", events: [(event "err" $"($rel) (ansi red)not a relative path(ansi reset)")] }
            } else if ($rel | str ends-with "/") {
              { valid: false, path: "", events: [(event "err" $"($rel) (ansi red)trailing slash\(/) not supported(ansi reset)")] }
            } else {
              let abs = $"($dotroot)/($rel)"
              if not (path-is-dir $abs) {
                { valid: false, path: "", events: [(event "err" $"($abs) (ansi red)not found(ansi reset)")] }
              } else {
                { valid: true, path: $abs, events: [] }
              }
            }
          }
    )

    let events = (run-checks $items)
    emit $events

    if (($items | where valid | length) == 0) {
      print $"(ansi yellow)There is no repo to fall into.(ansi reset)\n\n  (ansi attr_bold)cat '($dotfile)'(ansi reset)  to check the input\n"
    }
    return
  }

  if (($args | length) == 1) and (($args | get 0) != "prev") {
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

  if ($args | length) == 1 {
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

  let lines = (open --raw $file | lines | length)
  if $lines >= 100 {
    print --stderr $"(ansi red)too big(ansi dark_gray); The repos.conf file has ($lines) lines. Please make it less than 100.(ansi reset)"
    exit 1
  }

  print $"(ansi dark_gray)falling... Please wait(ansi reset)"

  let items = (
    config-entries $file
      | each { |entry|
          let repo_path = (expand-home $entry $home)

          if $repo_path == "/" {
            { valid: false, path: "", events: [(event "err" $"(ansi red)root\((ansi reset)/(ansi red)) not supported(ansi reset)")] }
          } else if ($repo_path | str ends-with "/") {
            { valid: false, path: "", events: [(event "err" $"($entry) (ansi red)trailing slash\(/) not supported(ansi reset)")] }
          } else if not ($repo_path | str starts-with "/") {
            { valid: false, path: "", events: [(event "err" $"($entry) (ansi red)not an absolute path(ansi dark_gray); Path must start with slash\(/) or tilde\(~).(ansi reset)")] }
          } else if not (path-is-dir $repo_path) {
            { valid: false, path: "", events: [(event "err" $"($repo_path) (ansi red)not found(ansi reset)")] }
          } else {
            { valid: true, path: $repo_path, events: [] }
          }
        }
  )

  mut events = (run-checks $items)
  if (($items | where valid | length) == 0) {
    $events = ($events ++ [(event "out" $"(ansi yellow)There is no repo to fall into.(ansi reset)\n\n  (ansi attr_bold)fall --help(ansi reset)  to get help\n")])
  }

  emit $events
  save-prev $prev $events
}
