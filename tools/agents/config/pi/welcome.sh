#!/usr/bin/env bash
if [ -z "${NO_COLOR:-}" ]; then
  cyan=$(printf '\033[1;36m')
  yellow=$(printf '\033[1;93m')
  reset=$(printf '\033[0m')
else
  cyan=
  yellow=
  reset=
fi

printf '\n%s' "$cyan"
cat <<'BANNER'
################################################################################
#                                                                              #
#     ########     ####                                                        #
#     ##     ##     ##                                                         #
#     ##     ##     ##                                                         #
#     ########      ##                                                         #
#     ##            ##                                                         #
#     ##            ##                                                         #
#     ##           ####                                                        #
#                                                                              #
#     WELCOME TO PI AGENT                                                      #
#     Running in sbx Docker sandbox VM.                                        #
#                                                                              #
################################################################################
BANNER
printf '%s' "$yellow"
cat <<'BANNER'
#                                                                              #
#          +------------------------------------------+                        #
#          |                                          |                        #
#          |     START PI BY TYPING:                  |                        #
#          |                                          |                        #
#          |                  pi                      |                        #
#          |                                          |                        #
#          +------------------------------------------+                        #
#                                                                              #
BANNER
printf '%s' "$cyan"
cat <<'BANNER'
################################################################################
#                                                                              #
#       After Pi starts:                                                       #
#       /login      pick your model provider                                   #
#       Ctrl+L      switch model                                               #
#       /model      switch model                                               #
#                                                                              #
################################################################################
BANNER
printf '%s\n\n' "$reset"
