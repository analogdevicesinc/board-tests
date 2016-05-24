#!/bin/bash
#
# Test suite for the PicoZed breakout board using the SDR2 SOM module.
#
# To add more tests, create new functions with names ending in "_test" and they
# will get automatically run in alphabetical order.

LEDS=( /sys/class/leds/led* )

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
	sleep 3
	local link=$(ethtool eth0 | grep Link)
	[[ ${link//*: /} == yes ]]
}

evtest_done() {
	exec 3<&-
	kill -s SIGINT ${PID}
}

# Check push buttons and switches for event triggering, requires evtest to be
# installed.
button_test() {
	[[ -e /dev/input/event0 ]] || return 1
	local ret

	echo -e "\nToggle the buttons and switches on the board and watch for corresponding LED blinks."
	echo "Hit Ctrl-C when done if necessary."

	for led in "${LEDS[@]}"; do
		echo oneshot > "${led}"/trigger
		echo 1 > "${led}"/invert
	done

	trap evtest_done SIGINT
	exec 3< <(evtest /dev/input/event0)
	local PID=$!

	local -a pb_test=(0 0 0 0)
	local -a sw_test=(0 0 0 0)

	# Hacky method of blinking corresponding LEDs per button press and while
	# keeping track of which buttons have triggered.
	local line
	while read -r line; do
		if [[ ${line} == "Event: "*" type 1 (EV_KEY), code 105 "* ]]; then
			pb_test[0]=1
			echo 1 > "${LEDS[0]}"/shot
		elif [[ ${line} == "Event: "*" type 1 (EV_KEY), code 106 "* ]]; then
			pb_test[1]=1
			echo 1 > "${LEDS[1]}"/shot
		elif [[ ${line} == "Event: "*" type 1 (EV_KEY), code 103 "* ]]; then
			pb_test[2]=1
			echo 1 > "${LEDS[2]}"/shot
		elif [[ ${line} == "Event: "*" type 1 (EV_KEY), code 108 "* ]]; then
			pb_test[3]=1
			echo 1 > "${LEDS[3]}"/shot
		elif [[ ${line} == "Event: "*" type 5 (EV_SW), code 0 "* ]]; then
			sw_test[0]=1
			echo 1 > "${LEDS[0]}"/shot
		elif [[ ${line} == "Event: "*" type 5 (EV_SW), code 1 "* ]]; then
			sw_test[1]=1
			echo 1 > "${LEDS[1]}"/shot
		elif [[ ${line} == "Event: "*" type 5 (EV_SW), code 2 "* ]]; then
			sw_test[2]=1
			echo 1 > "${LEDS[2]}"/shot
		elif [[ ${line} == "Event: "*" type 5 (EV_SW), code 3 "* ]]; then
			sw_test[3]=1
			echo 1 > "${LEDS[3]}"/shot
		fi
		if [[ -z ${pb_test[@]//1/} && -z ${sw_test[@]//1/} ]]; then
			# all keys/switches are working, stopping the loop
			sleep 1
			evtest_done
			break
		fi
	done <&3

	for led in "${LEDS[@]}"; do
		echo 0 > "${led}"/invert
		echo none > "${led}"/trigger
	done

	trap - SIGINT
	[[ -n ${pb_test[@]//1/} || -n ${sw_test[@]//1/} ]] && return 1
	return 0
}

ret=0
tests=$(compgen -A function | grep '_test$' | sort -r)

pushd "$(dirname $(readlink -f "${0}"))" >/dev/null
# run all test functions
echo "PicoZed breakout test suite"
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
	for led in "${LEDS[@]}"; do
		echo none > "${led}"/trigger
		echo 100 > "${led}"/brightness
	done
else
	echo "TEST(S) FAILED"
	# flashing LEDs for failing test suite
	for led in "${LEDS[@]}"; do
		echo heartbeat > "${led}"/trigger
	done
fi

read -p "Press [Enter] to shutdown..."
/sbin/shutdown -h now
