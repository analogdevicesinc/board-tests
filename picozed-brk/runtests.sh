#!/bin/bash
#
# Test suite for the PicoZed breakout board using the SDR2 SOM module.
#
# To add more tests, create new functions with names ending in "_test" and they
# will get automatically run in alphabetical order.

LED_PATH="/sys/class/leds/led*"

# Create a file of random data and copy it to a connected USB drive. Then copy
# it back from the USB device and make sure the files match.
USB_test() {
	local ret tmpfile tmpfile2 filename chksum new_chksum

	[[ -e /dev/sda ]] || return 1

	# create random 1MB data file
	tmpfile=$(mktemp)
	filename=$(basename "${tmpfile}")
	dd if=/dev/urandom of="${tmpfile}" bs=1024 count=1024 &>/dev/null
	chksum=$(md5sum "${tmpfile}" | cut -d' ' -f1)

	# copy data to USB drive and then copy it back
	dd if="${tmpfile}" of=/dev/sda bs=1024 count=1024 &>/dev/null
	sync
	echo 3 > /proc/sys/vm/drop_caches
	tmpfile2=$(mktemp)
	dd if=/dev/sda of="${tmpfile2}" bs=1024 count=1024 &>/dev/null
	sync
	echo 3 > /proc/sys/vm/drop_caches
	new_chksum=$(md5sum "${tmpfile2}" | cut -d' ' -f1)
	rm -f "${tmpfile}" "${tmpfile2}"

	[[ ${chksum} == ${new_chksum} ]] && ret=0 || ret=1
	return ${ret}
}

# Set interface speed to 100Mb/s so loopback cables work and check for a link.
Ethernet_test() {
	ethtool -s eth0 speed 100 duplex full autoneg off
	link=$(ethtool eth0 | grep Link)
	[[ ${link//*: /} == yes ]]
}

#button_test() {
#	# TODO: interactive button testing
#	# export gpios
#	true
#	# unexport gpios
#}

ret=0
tests=$(compgen -A function | grep '_test$' | sort -r)

pushd "$(dirname $(readlink -f "${0}"))" >/dev/null
# run all test functions
echo "PicoZed brk test suite"
echo "=============================="
for test_func in ${tests[@]}; do
	test_name=${test_func//_/ }
	echo -n "RUNNING: ${test_name} "
	eval ${test_func}
	if [[ $? -eq 0 ]]; then
		echo "PASSED"
	else
		echo "FAILED"
		ret=1
	fi
done
popd >/dev/null

echo "=============================="
# determine if any test functions failed
if [[ ${ret} -eq 0 ]]; then
	echo "ALL TESTS PASSED"
	# solid LEDs for passing test suite
	for led in ${LED_PATH}; do
		echo none > "${led}"/trigger
		echo 100 > "${led}"/brightness
	done
else
	echo "TEST(S) FAILED"
	# flashing LEDs for failing test suite
	for led in ${LED_PATH}; do
		echo heartbeat > "${led}"/trigger
	done
fi

read -p "Press [Enter] to shutdown..."
/sbin/shutdown -h now
