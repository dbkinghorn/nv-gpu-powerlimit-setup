#!/usr/bin/env bash
# Set power limits for NVIDIA GPUs and optionally
# install powerlimit script and systemd unit file
# to set power limits on boot.

# VERSION=0.2.0

# Putet Systems Labs
# https://pugetsystems.com
#
# Copyright 2022 Puget Systems and D B Kinghorn
# CC0 v1 license
#
# Disclaimer of Liability:
# Puget Systems and D B Kinghorn do not warrant
# or assume any legal liability or responsibility for the use of this script

# Start install log. Will go to install.log
# (  # uncomment this line and # ) at end of file to enable logging

if [[ "$1" == "--help" ]]; then
    printf '
USAGE:  sudo ./nv-powerlimit-setup-0.2.1.sh \n
You will be prompted for powerlimits to set.

OPTIONALLY a config file will be stored in /usr/local/etc/nv-powerlimit.conf
and a systemd unit file will be created and installed to reset powerlimits on boot.

see:
https://www.pugetsystems.com/labs/hpc/Quad-RTX3090-GPU-Power-Limiting-with-Systemd-and-Nvidia-smi-1983/

This script will;
- make sanity checks for OS version and NVIDIA GPUs
- interactively set powerlimits for NVIDIA GPUs found on system
- OPTIONALLY: 
- create a config /usr/local/etc/nv-powerlimit.conf with the powerlimit values
- create and install /usr/local/sbin/nv-power-limit.sh
- create and install /etc/systemd/system/nv-power-limit.service
- enable nv-power-limit.service
'
    exit 0
fi

#set -e
set -o errexit  # exit on errors
set -o errtrace # trap on ERR in function and subshell
trap 'install-error $? $LINENO' ERR
install-error() {
    echo "Error $1 occurred on $2"
    echo "YIKS! something failed!"
    # echo "Check install.log"
}

#set -x
#trap read debug

# eye candy
NOTECOLOR=$(tput setaf 3)    # Yellow
SUCCESSCOLOR=$(tput setaf 2) # Green
ERRORCOLOR=$(tput setaf 1)   # Red
RESET=$(tput sgr0)

function note() { echo "${NOTECOLOR}${@}${RESET}"; }
function success() { echo "${SUCCESSCOLOR}${@}${RESET}"; }
function error() { echo "${ERRORCOLOR}${@}${RESET}" >&2; }

# Check for root/sudo
if [[ $(id -u) -ne 0 ]]; then
    echo "Please use sudo to run this script"
    exit 1
fi

#
# Sanity checks
#

note "Checking OS version ..."

source /etc/os-release
if [[ $NAME == "Ubuntu" ]] && [[ ${VERSION_ID/./}+0 -ge 1804 ]]; then
    success "[OK] ${PRETTY_NAME}"
else
    error "[STOP] Script only validated for Ubuntu 18.04 or greater"
    exit 1
fi

note "Checking for NVIDIA GPU and Driver version"

function get_driver_version() {
    nvidia-smi | grep Driver | cut -d " " -f 3
}

if lspci | grep -q NVIDIA; then
    success "[OK] Found NVIDIA GPU"
    if [[ $(which nvidia-smi) ]]; then
        driver_version=$(get_driver_version)
        note "Driver Version = ${driver_version}"
    else
        error "[Failed] NVIDIA Driver not installed ..."
        exit 1
    fi
else
    error "[Failed] NVIDIA GPU not detected"
    exit 1
fi

function show_gpu_state() {
    OUT=$(nvidia-smi --query-gpu=index,gpu_name,persistence_mode,power.default_limit,power.limit --format=csv)
    echo "$OUT" | column -s , -t
}
success "Current Status of NVIDIA GPUs"
show_gpu_state

# loop over found GPUs and set power limits
declare -a gpu_indexes
gpu_indexes=($(nvidia-smi --query-gpu=index --format=csv,noheader))

declare -A gpu_power_limits

for gpu_index in "${gpu_indexes[@]}"; do
    MIN_PL=$(nvidia-smi --id=$gpu_index --query-gpu=power.min_limit --format=csv,noheader)
    MAX_PL=$(nvidia-smi --id=$gpu_index --query-gpu=power.max_limit --format=csv,noheader)
    echo "Please enter power limit for GPU ${gpu_index} (min: ${MIN_PL}, max: ${MAX_PL})"
    read gpu_power_limit
    gpu_power_limits[$gpu_index]=$gpu_power_limit
    nvidia-smi --id=$gpu_index -pm ENABLED && success "GPU ${gpu_index} persistence enabled"
    nvidia-smi --id=$gpu_index --power-limit=$gpu_power_limit && success "GPU ${gpu_index} power limit set to ${gpu_power_limit}"
    #echo "GPU $gpu_index power limit set to = ${gpu_power_limits[$gpu_index]}"
done

success "Power Limit Status of NVIDIA GPUs"
show_gpu_state

note "Save setting and restore on reboot? (y/n)"
read save_config
if [[ $save_config == "y" ]]; then
    declare -p gpu_power_limits >/etc/nv-powerlimit.conf && success "Saved config to /etc/nv-powerlimit.conf"
    note "setting permission chmod 644 on /usr/local/etc/nv-power-limit.conf"
    chmod 644 /etc/nv-power-limit.conf
else
    note "Not saving..."
    note "You will need to rerun this script to set power limits after reboot"
    exit 0
fi

#
# Install nv-power-limit.sh
#
CONFIG_FILE=/etc/nv-powerlimit.conf
[ -f "$CONFIG_FILE" ] || {
    echo "$CONFIG_FILE NOT FOUND"
    exit 1
}

note "Creating /usr/local/sbin/nv-power-limit.sh"

sudo tee /usr/local/sbin/nv-power-limit.sh <<'EOF'
#!/usr/bin/env bash

# Set power limits for NVIDIA GPUs
# powerlimits sourced from /etc/nv-powerlimit.conf

CONFIG_FILE=/etc/nv-power-limit.conf
source ${CONFIG_FILE} # defines the array "gpu_power_limits"

for gpu_index in "${!gpu_power_limits[@]}"; do
    nvidia-smi --id=$gpu_index -pm ENABLED && echo "GPU ${gpu_index} persistence enabled"
    nvidia-smi --id=$gpu_index --power-limit=$gpu_power_limits[$gpu_index] 
    echo "GPU $gpu_index power limit set to = ${gpu_power_limits[$gpu_index]}"
done

exit 0

EOF

if [[ -f /usr/local/sbin/nv-power-limit.sh ]]; then
    success "[OK] /usr/local/sbin/nv-power-limit.sh created"
else
    error "[Failed] /usr/local/sbin/nv-power-limit.sh not created"
    exit 1
fi

note "setting permissions: chmod 744 on /usr/local/sbin/nv-power-limit.sh"
chmod 744 /usr/local/sbin/nv-power-limit.sh

#
# Install nv-power-limit.service
#

note "Creating /usr/local/etc/systemd/system/nv-power-limit.service"
mkdir -p /usr/local/etc/systemd/system

sudo tee /usr/local/etc/systemd/system/nv-power-limit.service <<'EOF'
[Unit]
Description=NVIDIA GPU Set Power Limit
After=syslog.target systemd-modules-load.service
ConditionPathExists=/usr/bin/nvidia-smi

[Service]
User=root
Environment="PATH=/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/usr/local/sbin/nv-power-limit.sh

[Install]
WantedBy=multi-user.target

EOF

if [[ -f /usr/local/etc/systemd/system/nv-power-limit.service ]]; then
    success "[OK] /usr/local/etc/systemd/system/nv-power-limit.service created"
else
    error "[Failed] /usr/local/etc/systemd/system/nv-power-limit.service not created"
    exit 1
fi

note "setting permissions: chmod 644 on /usr/local/etc/systemd/system/nv-power-limit.service"
chmod 644 /usr/local/etc/systemd/system/nv-power-limit.service

#
# Enable nv-power-limit.service
#
note "linking /usr/local/etc/systemd/system/nv-power-limit.service to /etc/systemd/system/nv-power-limit.service"
ln -s --force /usr/local/etc/systemd/system/nv-power-limit.service /etc/systemd/system/nv-power-limit.service

systemctl enable nv-power-limit.service

success "Finished setting NVIDIA GPU power-limit service"

exit 0
