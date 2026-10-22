; extends

; Neovim validates injection language names before resolving filetype aliases.
; Handle the '+' characters in this common fence label explicitly.
((fenced_code_block
  (info_string
    (language) @_language)
  (code_fence_content) @injection.content)
  (#any-of? @_language "c++" "C++")
  (#set! injection.language "cpp"))
