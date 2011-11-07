"=============================================================================
" FILE: async_cache.vim
" AUTHOR: Shougo Matsushita <Shougo.Matsu@gmail.com>
" Last Modified: 07 Nov 2011.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following condition
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim

function! s:main(argv)"{{{
  " args: funcname, outputname filename pattern_file_name mark minlen maxfilename
  let [funcname, outputname, filename, pattern_file_name, mark, minlen, maxfilename, fileencoding]
        \ = a:argv

  if funcname ==# 'load_from_file'
    let keyword_list = s:load_from_file(filename, pattern_file_name, mark, minlen, maxfilename, fileencoding)
  else
    let keyword_list = s:load_from_tags(filename, pattern_file_name, mark, minlen, maxfilename, fileencoding)
  endif

  " Create dictionary key.
  for keyword in keyword_list
    if !has_key(keyword, 'abbr')
      let keyword.abbr = keyword.word
    endif
    if !has_key(keyword, 'kind')
      let keyword.kind = ''
    endif
    if !has_key(keyword, 'menu')
      let keyword.menu = ''
    endif
  endfor

  " Output cache.
  let word_list = []
  for keyword in keyword_list
    call add(word_list, printf('%s|||%s|||%s|||%s',
          \keyword.word, keyword.abbr, keyword.menu, keyword.kind))
  endfor

  call writefile(word_list, outputname)
endfunction"}}}

function! s:load_from_file(filename, pattern_file_name, mark, minlen, maxfilename, fileencoding)"{{{
  if filereadable(a:filename)
    let lines = map(readfile(a:filename), 'iconv(v:val, a:fileencoding, &encoding)')
  else
    " File not found.
    return []
  endif

  let pattern = get(readfile(a:pattern_file_name), 0, '\h\w*')

  let max_lines = len(lines)
  let menu = '[' . a:mark . '] ' . s:strwidthpart(
        \ fnamemodify(a:filename, ':t'), a:maxfilename)

  let keyword_list = []
  let dup_check = {}
  let keyword_pattern2 = '^\%('.pattern.'\m\)'

  for line in lines"{{{
    let match = match(line, pattern)
    while match >= 0"{{{
      let match_str = matchstr(line, keyword_pattern2, match)

      if !has_key(dup_check, match_str) && len(match_str) >= a:minlen
        " Append list.
        call add(keyword_list, { 'word' : match_str, 'menu' : menu })

        let dup_check[match_str] = 1
      endif

      let match = match(line, pattern, match + len(match_str))
    endwhile"}}}
  endfor"}}}

  return keyword_list
endfunction"}}}

function! s:load_from_tags(filename, pattern_file_name, mark, minlen, maxfilename, fileencoding)"{{{
  let menu = '[' . a:mark . ']'
  let menu_pattern = menu . printf(' %%.%ds', a:maxfilename)
  let keyword_lists = []
  let dup_check = {}
  let line_num = 1

  let [pattern, tags_file_name, filter_pattern, filetype] =
        \ readfile(a:pattern_file_name)[: 4]
  if tags_file_name !=# '$dummy$'
    " Check output.
    let tags_list = []

    let i = 0
    while i < 2
      if filereadable(tags_file_name)
        " Use filename.
        let tags_list = map(readfile(tags_file_name),
              \ 'iconv(v:val, a:fileencoding, &encoding)')
        break
      endif

      sleep 500m
      let i += 1
    endwhile
  else
    " Use filename.
    let tags_list = map(readfile(a:filename),
          \ 'iconv(v:val, a:fileencoding, &encoding)')
  endif

  if empty(tags_list)
    " File caching.
    return s:load_from_file(a:filename, a:pattern_file_name,
          \ a:mark, a:minlen, a:maxfilename, a:fileencoding)
  endif

  for line in tags_list"{{{
    let tag = split(substitute(line, "\<CR>", '', 'g'), '\t', 1)
    let opt = join(tag[2:], "\<TAB>")
    let cmd = matchstr(opt, '.*/;"')

    " Add keywords.
    if line !~ '^!' && len(tag) >= 3 && len(tag[0]) >= a:minlen
          \&& !has_key(dup_check, tag[0])
      let option = {
            \ 'cmd' : substitute(substitute(substitute(cmd,
            \'^\%([/?]\^\?\)\?\s*\|\%(\$\?[/?]\)\?;"$', '', 'g'),
            \ '\\\\', '\\', 'g'), '\\/', '/', 'g'),
            \ 'kind' : ''
            \}
      if option.cmd =~ '\d\+'
        let option.cmd = tag[0]
      endif

      for opt in split(opt[len(cmd):], '\t', 1)
        let key = matchstr(opt, '^\h\w*\ze:')
        if key == ''
          let option['kind'] = opt
        else
          let option[key] = matchstr(opt, '^\h\w*:\zs.*')
        endif
      endfor

      if has_key(option, 'file') || (has_key(option, 'access') && option.access != 'public')
        let line_num += 1
        continue
      endif

      let abbr = has_key(option, 'signature')? tag[0] . option.signature :
            \ (option['kind'] == 'd' || option['cmd'] == '') ?
            \ tag[0] : option['cmd']
      let abbr = substitute(abbr, '\s\+', ' ', 'g')
      " Substitute "namespace foobar" to "foobar <namespace>".
      let abbr = substitute(abbr,
            \'^\(namespace\|class\|struct\|enum\|union\)\s\+\(.*\)$', '\2 <\1>', '')
      " Substitute typedef.
      let abbr = substitute(abbr, '^typedef\s\+\(.*\)\s\+\(\h\w*\%(::\w*\)*\);\?$', '\2 <typedef \1>', 'g')

      let keyword = {
            \ 'word' : tag[0], 'abbr' : abbr, 'kind' : option['kind'], 'dup' : 1,
            \ }
      if has_key(option, 'struct')
        let keyword.menu = printf(menu_pattern, option.struct)
      elseif has_key(option, 'class')
        let keyword.menu = printf(menu_pattern, option.class)
      elseif has_key(option, 'enum')
        let keyword.menu = printf(menu_pattern, option.enum)
      elseif has_key(option, 'union')
        let keyword.menu = printf(menu_pattern, option.union)
      else
        let keyword.menu = menu
      endif

      call add(keyword_lists, keyword)
      let dup_check[tag[0]] = 1
    endif

    let line_num += 1
  endfor"}}}

  if filter_pattern != ''
    call filter(keyword_lists, filter_pattern)
  endif

  return keyword_lists
endfunction"}}}

function! s:truncate(str, width)"{{{
  " Original function is from mattn.
  " http://github.com/mattn/googlereader-vim/tree/master

  if a:str =~# '^[\x00-\x7f]*$'
    return len(a:str) < a:width ?
          \ printf('%-'.a:width.'s', a:str) : strpart(a:str, 0, a:width)
  endif

  let ret = a:str
  let width = s:wcswidth(a:str)
  if width > a:width
    let ret = s:strwidthpart(ret, a:width)
    let width = s:wcswidth(ret)
  endif

  if width < a:width
    let ret .= repeat(' ', a:width - width)
  endif

  return ret
endfunction"}}}

function! s:strchars(str)"{{{
  return len(substitute(a:str, '.', 'x', 'g'))
endfunction"}}}

function! s:strwidthpart(str, width)"{{{
  let ret = a:str
  let width = s:wcswidth(a:str)
  while width > a:width
    let char = matchstr(ret, '.$')
    let ret = ret[: -1 - len(char)]
    let width -= s:wcwidth(char)
  endwhile

  return ret
endfunction"}}}
function! s:strwidthpart_reverse(str, width)"{{{
  let ret = a:str
  let width = s:wcswidth(a:str)
  while width > a:width
    let char = matchstr(ret, '^.')
    let ret = ret[len(char) :]
    let width -= s:wcwidth(char)
  endwhile

  return ret
endfunction"}}}

if v:version >= 703
  " Use builtin function.
  function! s:wcswidth(str)"{{{
    return strdisplaywidth(a:str)
  endfunction"}}}
  function! s:wcwidth(str)"{{{
    return strwidth(a:str)
  endfunction"}}}
else
  function! s:wcswidth(str)"{{{
    if a:str =~# '^[\x00-\x7f]*$'
      return strlen(a:str)
    end

    let mx_first = '^\(.\)'
    let str = a:str
    let width = 0
    while 1
      let ucs = char2nr(substitute(str, mx_first, '\1', ''))
      if ucs == 0
        break
      endif
      let width += s:wcwidth(ucs)
      let str = substitute(str, mx_first, '', '')
    endwhile
    return width
  endfunction"}}}

  " UTF-8 only.
  function! s:wcwidth(ucs)"{{{
    let ucs = a:ucs
    if (ucs >= 0x1100
          \  && (ucs <= 0x115f
          \  || ucs == 0x2329
          \  || ucs == 0x232a
          \  || (ucs >= 0x2e80 && ucs <= 0xa4cf
          \      && ucs != 0x303f)
          \  || (ucs >= 0xac00 && ucs <= 0xd7a3)
          \  || (ucs >= 0xf900 && ucs <= 0xfaff)
          \  || (ucs >= 0xfe30 && ucs <= 0xfe6f)
          \  || (ucs >= 0xff00 && ucs <= 0xff60)
          \  || (ucs >= 0xffe0 && ucs <= 0xffe6)
          \  || (ucs >= 0x20000 && ucs <= 0x2fffd)
          \  || (ucs >= 0x30000 && ucs <= 0x3fffd)
          \  ))
      return 2
    endif
    return 1
  endfunction"}}}
endif

if argc() == 8 &&
      \ (argv(0) ==# 'load_from_file' || argv(0) ==# 'load_from_tags')
  try
    call s:main(argv())
  catch
    call writefile([v:throwpoint, v:exception],
          \     expand('~/async_error_log'))
  endtry

  qall!
else
  function! neocomplcache#async_cache#main(argv)"{{{
    call s:main(a:argv)
  endfunction"}}}
endif

" vim: foldmethod=marker
