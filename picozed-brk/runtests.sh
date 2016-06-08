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
	local tmpfile tmpfile2 filename chksum new_chksum

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

	[[ ${chksum} == ${new_chksum} ]] && return 0
	return 1
}

# Set interface speed to 100Mb/s so loopback cables work and check for a link.
Ethernet_test() {
	ethtool -s eth0 speed 100 duplex full autoneg off
	sleep 3
	local carrier=$(</sys/class/net/eth0/carrier)
	[[ ${carrier} == 1 ]] && return 0
	return 1
}

# Check push buttons and switches for gpio triggering.
button_test() {
	echo -e "\nToggle the buttons and switches on the board and watch for corresponding LED state changes."
	echo "The test will time out after 30 seconds if everything hasn't been toggled."

	for led in "${LEDS[@]}"; do
		echo 0 > "${led}"/brightness
	done

	# relative gpios: 54 55 56 57 62 63 64 65
	local -a pb_gpios=(960 961 962 963)
	local -a sw_gpios=(968 969 970 971)
	local -a gpios=( ${pb_gpios[@]} ${sw_gpios[@]} )
	local -a orig_gpio_values=( "${gpios[@]}" )
	local -a gpio_off=( "${gpios[@]}" )
	local -a gpio_on=( "${gpios[@]}" )
	local gpio gpio_path=/sys/class/gpio

	# export gpios
	for gpio in "${gpios[@]}"; do
		echo ${gpio} > "${gpio_path}"/export
		[[ $? -ne 0 ]] && return 1
	done

	# capture original GPIO state
	local i
	for i in "${!gpios[@]}"; do
		orig_gpio_values[${i}]=$(<"${gpio_path}"/gpio${gpios[${i}]}/value)
	done

	local gpio_value
	trap "break" SIGINT

	# 30 seconds to finish the test before timing out.
	sleep 30 &
	local timer_pid=$!

	# Hacky method of blinking corresponding LEDs per button press and while
	# keeping track of which have been triggered on and off.
	while [[ -n ${gpio_off[@]//1} || -n ${gpio_on[@]//1} ]]; do
		for i in "${!gpios[@]}"; do
			gpio_value=$(<"${gpio_path}"/gpio${gpios[$i]}/value)
			echo ${gpio_value} > "${LEDS[$((i % 4))]}"/brightness
			if [[ ${gpio_value} != ${orig_gpio_values[$i]} ]]; then
				if [[ ${gpio_value} == 1 ]]; then
					gpio_on[$i]=1
				else
					gpio_off[$i]=1
				fi
				orig_gpio_values[$i]=${gpio_value}
			fi
		done

		# check the timer is still running
		kill -0 ${timer_pid} 2>/dev/null || break
		sleep 0.1
	done

	trap - SIGINT

	for gpio in "${gpios[@]}"; do
		echo ${gpio} > /sys/class/gpio/unexport
		[[ $? -ne 0 ]] && return 1
	done
	for led in "${LEDS[@]}"; do
		echo 0 > "${led}"/brightness
	done

	[[ -n ${gpio_off[@]//1} || -n ${gpio_on[@]//1} ]] && return 1
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
