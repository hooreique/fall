#!/usr/bin/env nu
use codec.nu
use std/assert

for path in ['/repo' '/한글/저장소' 'a  b' ' leading' 'trailing ' '  both  ' ' ' "tab\tpath" '"quoted"'] {
  for mode in [required skip] {
    let entry = {path: $path, fetch_mode: $mode}
    assert equal (codec decode (codec encode $entry)) $entry
  }
}
assert equal (codec encode {path: 'a  b', fetch_mode: required}) 'a\ \ b'
assert equal (codec encode {path: 'a b', fetch_mode: skip}) '! a\ b'
assert equal (codec decode 'repo suffix\ignored\') {path: 'repo', fetch_mode: required}
assert equal (codec decode 'a\ b ignored') {path: 'a b', fetch_mode: required}
assert equal (codec decode '!   a\ b suffix\ignored\') {path: 'a b', fetch_mode: skip}
assert equal (codec decode '!  \ leading') {path: ' leading', fetch_mode: skip}
for input in ['' ' suffix' 'a\q' 'a\' 'a\\b' "a\r" "a\n" "a suffix\r" "a suffix\n" '!' '!repo' "!\trepo" '! ' '!    ' '! !repo' ' ! repo'] {
  assert error { codec decode $input }
}
for path in ['' 'a\b' "a\r" "a\n" '!repo' '!'] {
  for mode in [required skip] {
    assert error { codec encode {path: $path, fetch_mode: $mode} }
  }
}
for mode in [optional unknown ''] {
  assert error { codec encode {path: repo, fetch_mode: $mode} }
}
print 'codec tests passed'
