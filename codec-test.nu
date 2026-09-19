#!/usr/bin/env nu
use codec.nu
use std/assert

for path in ['/repo' '/한글/저장소' 'a  b' ' leading' 'trailing ' '  both  ' ' ' "tab\tpath" '"quoted"'] {
  for mode in [required skip optional] {
    let entry = {path: $path, fetch_mode: $mode, remote: null, remote_branch: null}
    assert equal (codec decode (codec encode $entry)) $entry
  }
}
assert equal (codec encode {path: 'a  b', fetch_mode: required}) 'a\ \ b'
assert equal (codec encode {path: 'a b', fetch_mode: skip}) '! a\ b'
assert equal (codec encode {path: 'a b', fetch_mode: optional}) '? a\ b'
for mode in [required skip optional] {
  for remote in [null origin upstream '한글' '"quoted"' '-option' 'a/b' '?name'] {
    let entry = {path: ' a  b ', fetch_mode: $mode, remote: $remote, remote_branch: null}
    assert equal (codec decode (codec encode $entry)) $entry
  }
}
assert equal (codec decode '?   a\ b   upstream   ') {path: 'a b', fetch_mode: optional, remote: upstream, remote_branch: null}
assert equal (codec decode '!  \ leading   ') {path: ' leading', fetch_mode: skip, remote: null, remote_branch: null}
assert equal (codec decode 'repo   ') {path: repo, fetch_mode: required, remote: null, remote_branch: null}
assert equal (codec decode 'repo "quoted"') {path: repo, fetch_mode: required, remote: '"quoted"', remote_branch: null}
for remote in ['' 'a b' 'a\b' "a\tb" "a\nb" "a\rb" 'a b'] {
  assert error { codec encode {path: repo, fetch_mode: required, remote: $remote, remote_branch: null} }
}
for input in ['repo origin main extra' 'repo suffix\ignored\' 'repo remote\ name' "repo a\tb" 'repo a b'] {
  assert error { codec decode $input }
}
for input in ['' ' suffix' 'a\q' 'a\' 'a\\b' "a\r" "a\n" "a suffix\r" "a suffix\n" '!' '!repo' "!\trepo" '! ' '!    ' '! !repo' ' ! repo'] {
  assert error { codec decode $input }
}
for input in ['?' '?repo' "?\trepo" '? ' '?    ' '? ?repo' '? !repo' '! ?repo' '? ? repo' '? ! repo' '! ? repo' '! ! repo' ' ? repo'] {
  assert error { codec decode $input }
}
for path in ['' 'a\b' "a\r" "a\n" '!repo' '!' '?repo' '?'] {
  for mode in [required skip optional] {
    assert error { codec encode {path: $path, fetch_mode: $mode} }
  }
}
for mode in [unknown ''] {
  assert error { codec encode {path: repo, fetch_mode: $mode} }
}

for mode in [required skip optional] {
  for branch in [main feature/topic 한글] {
    let entry = {path: 'a b', fetch_mode: $mode, remote: origin, remote_branch: $branch}
    assert equal (codec decode (codec encode $entry)) $entry
  }
}
assert error { codec encode {path: repo, fetch_mode: required, remote_branch: main} }
assert error { codec encode {path: repo, fetch_mode: required, remote: null, remote_branch: main} }
assert equal (codec encode {path: repo, fetch_mode: required, remote: origin}) 'repo origin'
assert equal (codec decode '? repo   origin   feature/topic  ') {path: repo, fetch_mode: optional, remote: origin, remote_branch: feature/topic}
for branch in ['' 'a b' 'a\b' "a\tb"] {
  assert error { codec encode {path: repo, fetch_mode: required, remote: origin, remote_branch: $branch} }
}
for input in ['repo origin a\b' "repo origin a\tb"] {
  assert error { codec decode $input }
}
print 'codec tests passed'
