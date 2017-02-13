set nocompatible

set backspace=indent,eol,start

set history=50		
set ruler		    
set showcmd		    
set incsearch		


set backupdir=~/.vim/backup
set dir=~/.vim/temp
"set undofile
"set undodir=~/.vim/backup

set updatecount=10
set wildmenu

set number
set autoindent
set smartindent
set showmatch
set textwidth=78
set tabstop=4
set shiftwidth=4
set expandtab
set smarttab
set path+=lib/
set whichwrap+=<>
set cc=+1
hi ColorColumn ctermbg=235

set laststatus=2


set t_Co=256



syntax on
set hlsearch

"    color iceberg
set background=dark
let g:solarized_visibility = "normal"
" let g:solarized_termtrans  = 1
" let g:solarized_termcolors=256
let g:solarized_italic = 1
color solarized

" colors lucius
" LuciusLightHighContrast
" colors neverness
" colors github
" let g:rehash256 = 1
" colors molokai

" set lcs=tab:>-,eol:$,trail:~

if has("autocmd")
  filetype plugin indent on

  autocmd BufReadPost *
    \ if line("'\"") > 1 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif

  augroup END

endif

execute pathogen#infect()

let NERDTreeHijackNetrw=0

nmap <silent> <BS> :noh<CR>


" nnoremap <silent> <F12> :TlistToggle<CR>

