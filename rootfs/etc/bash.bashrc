# If not running interactively, don't do anything
[[ $- != *i* ]] && return

[[ "$WAYLAND_DISPLAY" ]] && shopt -s checkwinsize

export HISTFILE="/home/$USER/.cache/bash_history"
export PS1='\[\e[1;92m\][\u@\h \w]\[\e[0m\] \$ '

[ -r /usr/share/bash-completion/bash_completion   ] && . /usr/share/bash-completion/bash_completion
