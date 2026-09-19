#!/usr/bin/env nu
use codec.nu
use std/assert

for path in ['/repo' '/한글/저장소' 'a  b' ' leading' 'trailing ' '  both  ' ' ' "tab\tpath" '"quoted"'] {
  assert equal (codec decode (codec encode {path: $path})) {path: $path}
}
assert equal (codec encode {path: 'a  b'}) 'a\ \ b'
assert equal (codec decode 'repo suffix\ignored\') {path: 'repo'}
assert equal (codec decode 'a\ b ignored') {path: 'a b'}
for input in ['' ' suffix' 'a\q' 'a\' 'a\\b' "a\r" "a\n" "a suffix\r" "a suffix\n"] {
  assert error { codec decode $input }
}
for path in ['' 'a\b' "a\r" "a\n"] {
  assert error { codec encode {path: $path} }
}
print 'codec tests passed'
