" An example for a vimrc file.
"
" Maintainer:	Bram Moolenaar <Bram@vim.org>
" Last change:	2008 Dec 17
"
" To use it, copy it to
"     for Unix and OS/2:  ~/.vimrc
"	      for Amiga:  s:.vimrc
"  for MS-DOS and Win32:  $VIM\_vimrc
"	    for OpenVMS:  sys$login:.vimrc

" When started as "evim", evim.vim will already have done these settings.
if v:progname =~? "evim"
  finish
endif
	

" Use Vim settings, rather than Vi settings (much better!).
" This must be first, because it changes other options as a side effect.
set nocompatible

" allow backspacing over everything in insert mode
set backspace=indent,eol,start

set history=50		" keep 50 lines of command line history
set ruler		    " show the cursor position all the time
set showcmd		    " display incomplete commands
set incsearch		" do incremental searching


set backupdir=~/.vim/backup
set dir=~/.vim/temp

set number
set autoindent
set smartindent
set showmatch
set textwidth=78
set tabstop=4
set shiftwidth=4
set expandtab
set smarttab
" set iskeyword-=: " @,48-57,_,192-255
set path+=lib/,/www/lib/
set whichwrap+=<>
	
	
" set sb
" set spr

if has("autocmd")
  filetype plugin indent on

  autocmd BufReadPost *
    \ if line("'\"") > 1 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif

  augroup END

endif


if has('mouse')
  set mouse=a
endif

set t_Co=256

syntax on
set hlsearch

colors neverness

set cc=+1
hi ColorColumn ctermbg=235

" let g:kolor_bold=0
" let g:kolor_italic=0
" let g:kolor_alternative_matchparen=1
" colors kolor
"
"
":colorscheme seoul256
" :color jellybeans
" colors desertEx 

" let g:rehash256=1
" let g:molokai_original=1
" :color molokai
" set background=dark
" colors peaksea


" :colorscheme zarniwoop
"
" let g:lucius_style='dark'
" :colorscheme lucius

" :LuciusGrayHighContrast

" :colorscheme xoria256

let NERDTreeHijackNetrw=0

" execute pathogen#infect()
" nnoremap <silent> <F12> :TlistToggle<CR>

