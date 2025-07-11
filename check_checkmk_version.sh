#!/bin/bash
#===============================================================================
#
#          FILE: check_checkmk_version.sh
#
#         USAGE: Executed as the Checkmk site user.
#   DESCRIPTION: Checks the local installed Checkmk version with the newest available
#                version via the stable_downloads.json API
#       OPTIONS: 
#  REQUIREMENTS: BASH, curl, cut, date, jq, omd and sed
#          BUGS: ---
#         NOTES: Copyright (c) 2025. Licensed under Custom License 
#                - See LICENSE file for details.
#                - This script is provided WITHOUT WARRANTY
#                - Test it before production use
#                - Use at your own risk
#                - No support or guarantee provided
#                - No Backup, no remorse
#        AUTHOR: Stephan H. Wenderlich stephan.wenderlich@gray-hat-it-security-consulting.de
#  ORGANIZATION: Copyright (c) 2025 Gray-Hat IT-Security Consulting Stephan H. Wenderlich
#       CREATED: 07/10/2025 18:30:00 PM
#      REVISION: 3
#===============================================================================
set -euo pipefail

#-------------------------------------------------------------------------------
# Checkmk specific variables
#-------------------------------------------------------------------------------
API_URL='https://download.checkmk.com/stable_downloads.json'
declare -a majorversionarray=('2.6.0' '2.5.0' '2.4.0' '2.3.0' '2.2.0' '2.1.0' '2.0.0' '1.6.0')

#-------------------------------------------------------------------------------
# Command paths
#-------------------------------------------------------------------------------
THIS_CURL="$(command -v curl)"
 THIS_CUT="$(command -v cut)"
  THIS_JQ="$(command -v jq)"
THIS_DATE="$(command -v date)"
 THIS_OMD="$(command -v omd)"
 THIS_SED="$(command -v sed)"

#---  FUNCTION  ----------------------------------------------------------------
#          NAME: checkArgValidity
#   DESCRIPTION: Checks if the local found major version is valid
#    PARAMETERS: $1 - Major version to check
#                $@ - Array of valid major versions
#       RETURNS: 0 on success, exits with 3 on invalid version
#-------------------------------------------------------------------------------
function checkArgValidity() 
{
    local checkme="$1"
    shift
    declare -a checkmeArray=("$@")
    
    for version in "${checkmeArray[@]}"; do
        if [[ "${checkme}" == "${version}" ]]; then
            return 0
        fi
    done
    
    echo "UNKNOWN - Invalid Major-Version: ${checkme}"
    echo "Valid versions: ${majorversionarray[*]}"
    exit 3
}   # ----------  end of function checkArgValidity ----------

#---  FUNCTION  ----------------------------------------------------------------
#          NAME: getLocalMajorVersion
#   DESCRIPTION: Get the local used major version from omd command
#    PARAMETERS:
#       RETURNS: Echoes major version string, exits with 3 on error
#-------------------------------------------------------------------------------
function getLocalMajorVersion() 
{
    local major_version
    major_version="$("${THIS_OMD}" version | "${THIS_CUT}" -d' ' -f7 | "${THIS_CUT}" -d'p' -f1 2>/dev/null)"
    
    if [[ $? -ne 0 ]] || [[ -z "${major_version}" ]]; then
        echo "UNKNOWN - Can't determine major version"
        exit 3
    fi
    
    echo "${major_version}"
}   # ----------  end of function getLocalMajorVersion ----------


#---  FUNCTION  ----------------------------------------------------------------
#          NAME: getCheckmkVersionInfo
#   DESCRIPTION: Gets version info from API and calculates age delta
#    PARAMETERS: $1 - Major version to check
#       RETURNS: Checkmk plugin output, exits with status code 0-3
#-------------------------------------------------------------------------------
function getCheckmkVersionInfo()
{
    local majorversion="$1"
    
    local current_version_output
    current_version_output="$("${THIS_OMD}" version | "${THIS_CUT}" -d' ' -f7 | "${THIS_SED}" 's/\.[a-z]*$//' 2>/dev/null)"
    
    if [[ $? -ne 0 ]] || [[ -z "${current_version_output}" ]]; then
        echo "UNKNOWN - Can't use omd ... something is wrong"
        exit 3
    fi
    
    # Call API
    local api_data
    api_data="$("${THIS_CURL}" -s "${API_URL}")"
    
    if [[ $? -ne 0 ]] || [[ -z "${api_data}" ]]; then
        echo "UNKNOWN - API has a problem: ${API_URL}"
        exit 3
    fi
    
    # Extract version and release_date from API
    local latest_version release_date_epoch class_info
    
        latest_version="$(echo "${api_data}" | "${THIS_JQ}" -r ".checkmk.\"${majorversion}\".version"      2>/dev/null)"
    release_date_epoch="$(echo "${api_data}" | "${THIS_JQ}" -r ".checkmk.\"${majorversion}\".release_date" 2>/dev/null)"
            class_info="$(echo "${api_data}" | "${THIS_JQ}" -r ".checkmk.\"${majorversion}\".class"        2>/dev/null)"

    if [[ "${latest_version}" == "null" ]] || [[ "${release_date_epoch}" == "null" ]]; then
        echo "UNKNOWN - API gave us no information for ${majorversion}"
        exit 3
    fi
    
    if [[ "${current_version_output}" == "${latest_version}" ]]; then
        printf "0 Checkmk_Version_Check - Installed %s is up-to-date (latest: %s)\n" "${current_version_output}" "${latest_version}"
        exit 0
    fi
    
    local current_timestamp
    current_timestamp="$("${THIS_DATE}" +%s)"
    
    local delta_seconds=$((current_timestamp - release_date_epoch))
    local delta_days=$((delta_seconds / 86400))
    
    local release_date_human
    release_date_human="$("${THIS_DATE}" -d "@${release_date_epoch}" "+%d.%m.%Y %H:%M:%S")"
    
    declare -i warning_age=27
    declare -i critical_age=45
    
    local CONFIG_FILE="/etc/check_mk/check_checkmk_version.conf"
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
    fi
    
    local status=0
    
    if [[ "${delta_days}" -gt "${warning_age}" ]]; then
        status=1
    fi
    
    if [[ "${delta_days}" -gt "${critical_age}" ]]; then
        status=2
    fi

    printf "%d Checkmk_Version_Check - Update available! Installed %s, Newest %s (%s), Release %s, %d days ago\n" "${status}" "${current_version_output}" "${latest_version}" "${class_info}" "${release_date_human}" "${delta_days}"
    exit "${status}"
}   # ----------  end of function getCheckmkVersionInfo ----------

#-------------------------------------------------------------------------------
# Main entry point
#-------------------------------------------------------------------------------
majorversion="$(getLocalMajorVersion)"
checkArgValidity "${majorversion}" "${majorversionarray[@]}"
getCheckmkVersionInfo "${majorversion}"
