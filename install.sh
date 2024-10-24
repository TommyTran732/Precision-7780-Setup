#!/bin/bash

# Copyright (C) 2021-2024 Thien Tran, Tommaso Chiti
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -u

output(){
    printf '\e[1;34m%-6s\e[m\n' "${@}"
}

unpriv(){
    sudo -u nobody "$@"
}

luks_password_prompt () {
    output 'Enter your encryption password (the password will not be shown on the screen):'
    read -r -s luks_password

    if [ -z "${luks_password}" ]; then
        output 'You need to enter a password.'
        luks_password_prompt
    fi

    output 'Confirm your encryption password (the password will not be shown on the screen):'
    read -r -s luks_password2
    if [ "${luks_password}" != "${luks_password2}" ]; then
        output 'Passwords do not match, please try again.'
        luks_password_prompt
    fi
}

disk_prompt (){
    lsblk
    output 'Please select the number of the primary disk (e.g. 1):'
    select entry in $(lsblk -dpnoNAME|grep -P "/dev/nvme|sd|mmcblk|vd");
    do
        disk="${entry}"
        output "Arch Linux will be installed on the following disk: ${disk}"
        break
    done
}

username_prompt (){
    output 'Please enter the name for a user account:'
    read -r username

    if [ -z "${username}" ]; then
        output 'Sorry, You need to enter a username.'
        username_prompt
    fi
}

fullname_prompt (){
    output 'Please enter the full name for the user account:'
    read -r fullname

    if [ -z "${fullname}" ]; then
        output 'Please enter the full name of the users account.'
        fullname_prompt
    fi
}

user_password_prompt () {
    output 'Enter your user password (the password will not be shown on the screen):'
    read -r -s user_password

    if [ -z "${user_password}" ]; then
        output 'You need to enter a password.'
        user_password_prompt
    fi

    output 'Confirm your user password (the password will not be shown on the screen):'
    read -r -s user_password2
    if [ "${user_password}" != "${user_password2}" ]; then
        output 'Passwords do not match, please try again.'
        user_password_prompt
    fi
}