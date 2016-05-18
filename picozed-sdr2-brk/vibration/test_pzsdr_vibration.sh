#!/bin/bash

sleep 5
echo > /root/log.txt
/usr/local/bin/enable_static_ip.sh 192.168.1.99
Xvfb -shmem -screen 0 1280x1024x24 &>/dev/null &
sleep 15
export DISPLAY=:0

assert() {
    local pipestatus=${PIPESTATUS[*]}
    [[ -z ${pipestatus//[ 0]/} ]] || return 1
}

while true; do
	date >> /root/log.txt
	stdbuf -oL -eL /root/loopback |& tee -a /root/log.txt
	assert || break
	stdbuf -oL -eL /usr/local/bin/osc -n -p /usr/local/lib/osc/profiles/PZSDR2_test.ini |& tee -a /root/log.txt
	assert || break
done

for led in /sys/class/leds/led*/trigger; do
	echo heartbeat > "${led}"
done
killall -9 Xvfb &> /dev/null
