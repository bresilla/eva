/* SPDX-License-Identifier: MIT
 * A mouse that never moves: a uinput device held open until SIGTERM.
 */
#include <fcntl.h>
#include <linux/uinput.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;

static void stop(int signal_number)
{
    (void)signal_number;
    stopping = 1;
}

int main(void)
{
    struct uinput_setup setup;
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);

    if (fd < 0) {
        perror("/dev/uinput");
        return 1;
    }

    memset(&setup, 0, sizeof setup);
    setup.id.bustype = BUS_VIRTUAL;
    strncpy(setup.name, "eva virtual pointer", UINPUT_MAX_NAME_SIZE - 1);

    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 || ioctl(fd, UI_SET_KEYBIT, BTN_LEFT) < 0 ||
        ioctl(fd, UI_SET_EVBIT, EV_REL) < 0 || ioctl(fd, UI_SET_RELBIT, REL_X) < 0 ||
        ioctl(fd, UI_SET_RELBIT, REL_Y) < 0 || ioctl(fd, UI_DEV_SETUP, &setup) < 0 ||
        ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("uinput");
        return 1;
    }

    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    while (!stopping)
        pause();

    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
