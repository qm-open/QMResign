#!/bin/bash

echo "Current directory:"
pwd
echo "User:"
whoami
echo "Starting resign process:"
echo ~/.fastlane/bin/sigh resign -i "${1}" -p "${2}" "${3}"
~/.fastlane/bin/sigh resign -i "${1}" -p "${2}" "${3}"

