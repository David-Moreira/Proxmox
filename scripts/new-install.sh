#!/usr/bin/env bash

source <(curl -s https://raw.githubusercontent.com/David-Moreira/Proxmox/main/scripts/misc/build.func)

color
catch_errors

echo -e "Testing... Loading..."

msg_info "Testing..."
msg_ok "Testing ok..."
msg_error "Testing Error..."