/*
 * Perform a loopback test on the pzsdr1 breakout board using the test fixture.
 */

#define GPIO_WAIT_TIME 5000
#define GPIO_MAP_SIZE 0x10000

#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>

volatile unsigned *regmap;

void gpio_write(uint32_t value) {
	*((unsigned *) (regmap + 0x101)) = value;
}

int gpio_read(uint32_t pin, uint32_t expected, uint32_t mask) {
	int ret = 0;
	uint32_t rdata;

	rdata = (*((unsigned *) (regmap + 0x102)));
	if ((rdata & mask) != (expected & mask)) {
		printf("Loopback error on pin %d: "
			"wrote 0x%08x, read 0x%08x\r\n", pin, expected, rdata);
		ret = 1;
	}

	return ret;
}

void gpio_wait()
{
	usleep(GPIO_WAIT_TIME);
}

int main()
{
	int ret = 0;
	uint32_t n, wdata, mask;
	int fd = 0;

	/* Open the UIO device file */
	fd = open("/dev/uio0", O_RDWR);
	if (fd < 1) {
		perror("failed opening /dev/uio0");
		return -1;
	}

	/* mmap the UIO device */
	regmap = (volatile unsigned *)mmap(NULL, GPIO_MAP_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	if (!regmap) {
		perror("failed mmap-ing /dev/uio0");
		return -1;
	}

	/* Only 27 pins are looped. */
	mask = (1 << 27) - 1;

	/* walking 1 */
	for(n = 0; n < 27; n++) {
		wdata = 1 << n;
		gpio_write(wdata);
		gpio_wait();
		if (gpio_read(n, wdata, mask) != 0)
			ret = 1;
	}

	/* walking 0 */
	for(n = 0; n < 27; n++) {
		wdata = 1 << n;
		wdata = ~wdata;
		gpio_write(wdata);
		gpio_wait();
		if (gpio_read(n, wdata, mask) != 0)
			ret = 1;
	}

	munmap((void*)regmap, GPIO_MAP_SIZE);
	return ret;
}
