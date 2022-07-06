#!/usr/bin/env bash
# Set power limits for NVIDIA GPUs and optionally
# install powerlimit script and systemd unit file
# to set power limits on boot.

# VERSION=0.2.1

# Puget Systems Labs
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

# Set variables
VERSION="0.2.1"

function show_usage() {
    cat <<EOF

nv-gpu-powerlimit-setup.sh version $VERSION 

Usage: 
    sudo ./nv-powerlimit-setup-0.2.1.sh [options]
    
    Without options:
        Interactively: set power limits for detected NVIDIA GPUs and optionally
        install powerlimit script and systemd unit file
        to set power limits on boot.

    see: 
    https://www.pugetsystems.com/labs/hpc/Quad-RTX3090-GPU-Power-Limiting-with-Systemd-and-Nvidia-smi-1983/

    
Options:
    -h, --help
        show this help message and exit
    
    -v, --version
        show version and exit
        
    -s, --status
        show current power limit settings for all NVIDIA GPUs

    -p, --powerlimits
        a list of power limits to set for each NVIDIA GPU in the form:
        <gpu_id>:<power_limit>  
        example -p 0:280 1:270  (any gpu_id not set will keep its current powerlimit)
        use -s or --status to see current gpu_ids and power limits

    -b, --boot
        create and enable nv-power-limit.service to run on boot

Examples:
    check powerlimits:
        ./nv-gpu-powerlimit-setup.sh --status

    set powerlimits and install systemd unit file:
        sudo ./nv-powerlimit-setup-0.2.1.sh -p 0:280 1:270 -b
EOF
}

function show_gpu_state() {
    OUT=$(nvidia-smi --query-gpu=index,gpu_name,persistence_mode,power.default_limit,power.limit --format=csv)
    echo "$OUT" | column -s , -t
}

while :; do
    case $1 in
    -h | --help)
        show_usage
        exit 0
        ;;
    -v | --version)
        printf "nv-power-limit-setup: %s\n" "${VERSION}"
        exit 0
        ;;
    -s | --status)
        show_gpu_state
        exit 0
        ;;
    -p | --powerlimits)
        if [[ -z "$2" || "$2" =~ ^[-] ]]; then
            echo "Error: missing power limits"
            show_usage
            exit 1
        fi
        declare -A POWERLIMITS
        while [[ "$*" ]]; do
            shift
            #echo $1
            # handle un-quoted input
            if [[ $1 =~ ^[0-9]+:[[:digit:]]+$ ]]; then
                POWERLIMITS[$(echo "$1" | cut -d: -f1)]=$(echo "$1" | cut -d: -f2)
            # handle quoted input
            elif ! [[ "$1" =~ ^[-] ]]; then
                IFS=" " read -ra quoted_array <<<"$1"
                for i in "${quoted_array[@]}"; do
                    POWERLIMITS[$(echo "$i" | cut -d: -f1)]=$(echo "$i" | cut -d: -f2)
                done
            else # we got another option
                break
            fi
        done
        declare -p POWERLIMITS
        ;;
    -b | --boot)
        do_systemd=1
        shift
        echo "Enabling nv-power-limit.service to run on boot"
        ;;
    --) # End of all options.
        shift
        break
        ;;
    -*) # Invalid options.
        printf >&2 "ERROR: Invalid flag '%s'\n\n" "$1"
        show_usage
        exit 1
        ;;
    *) # Default case: If no more options then break out of the loop.
        # If no options specified then run interactive
        break
        ;;
    esac
done

exit 0

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

success "Current Status of NVIDIA GPUs"
show_gpu_state

# loop over found GPUs and set power limits
declare -a gpu_indexes
IFS=" " read -ra gpu_indexes <<<"$(nvidia-smi --query-gpu=index --format=csv,noheader)"

declare -A gpu_power_limits

for gpu_index in "${gpu_indexes[@]}"; do
    MIN_PL=$(nvidia-smi --id="$gpu_index" --query-gpu=power.min_limit --format=csv,noheader)
    MAX_PL=$(nvidia-smi --id="$gpu_index" --query-gpu=power.max_limit --format=csv,noheader)
    echo "Please enter power limit for GPU ${gpu_index} (min: ${MIN_PL}, max: ${MAX_PL})"
    read -r gpu_power_limit
    gpu_power_limits[$gpu_index]=$gpu_power_limit
    nvidia-smi --id="$gpu_index" -pm ENABLED && success "GPU ${gpu_index} persistence enabled"
    nvidia-smi --id="$gpu_index" --power-limit="$gpu_power_limit" && success "GPU ${gpu_index} power limit set to ${gpu_power_limit}"
    #echo "GPU $gpu_index power limit set to = ${gpu_power_limits[$gpu_index]}"
done

success "Power Limit Status of NVIDIA GPUs"
show_gpu_state

note "Save setting and restore on reboot? (y/n)"
read -r save_config
if [[ $save_config == "y" ]]; then
    declare -p gpu_power_limits >/etc/nv-powerlimit.conf && success "Saved config to /etc/nv-powerlimit.conf"
    note "setting permission chmod 644 on /usr/local/etc/nv-powerlimit.conf"
    chmod 644 /etc/nv-powerlimit.conf
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

note "Creating /usr/local/sbin/nv-powerlimit.sh"

sudo tee /usr/local/sbin/nv-powerlimit.sh <<'EOF'
#!/usr/bin/env bash

# Set power limits for NVIDIA GPUs
# powerlimits sourced from /etc/nv-powerlimit.conf

CONFIG_FILE=/etc/nv-powerlimit.conf
source ${CONFIG_FILE} # defines the array "gpu_power_limits"

for gpu_index in "${!gpu_power_limits[@]}"; do
    gpu_power_limit="${gpu_power_limits[$gpu_index]}"
    nvidia-smi --id=$gpu_index -pm ENABLED && echo "GPU ${gpu_index} persistence enabled"
    nvidia-smi --id=$gpu_index --power-limit="$gpu_power_limit" 
    echo "GPU $gpu_index power limit set to = ${gpu_power_limits[$gpu_index]}"
done

exit 0

EOF

if [[ -f /usr/local/sbin/nv-powerlimit.sh ]]; then
    success "[OK] /usr/local/sbin/nv-powerlimit.sh created"
else
    error "[Failed] /usr/local/sbin/nv-powerlimit.sh not created"
    exit 1
fi

note "setting permissions: chmod 744 on /usr/local/sbin/nv-powerlimit.sh"
chmod 744 /usr/local/sbin/nv-powerlimit.sh

#
# Install nv-power-limit.service
#

note "Creating /usr/local/etc/systemd/system/nv-powerlimit.service"
mkdir -p /usr/local/etc/systemd/system

sudo tee /usr/local/etc/systemd/system/nv-powerlimit.service <<'EOF'
[Unit]
Description=NVIDIA GPU Set Power Limit
After=syslog.target systemd-modules-load.service
ConditionPathExists=/usr/bin/nvidia-smi

[Service]
User=root
Environment="PATH=/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/usr/local/sbin/nv-powerlimit.sh

[Install]
WantedBy=multi-user.target

EOF

if [[ -f /usr/local/etc/systemd/system/nv-powerlimit.service ]]; then
    success "[OK] /usr/local/etc/systemd/system/nv-powerlimit.service created"
else
    error "[Failed] /usr/local/etc/systemd/system/nv-powerlimit.service not created"
    exit 1
fi

note "setting permissions: chmod 644 on /usr/local/etc/systemd/system/nv-powerlimit.service"
chmod 644 /usr/local/etc/systemd/system/nv-powerlimit.service

#
# Enable nv-power-limit.service
#
note "linking /usr/local/etc/systemd/system/nv-powerlimit.service to /etc/systemd/system/nv-powerlimit.service"
ln -s --force /usr/local/etc/systemd/system/nv-powerlimit.service /etc/systemd/system/nv-powerlimit.service

systemctl enable nv-powerlimit.service

success "Finished setting NVIDIA GPU powerlimit service"

exit 0
