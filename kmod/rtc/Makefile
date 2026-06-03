
obj-m += cv181x_rtc.o
cv181x_rtc-y := cvi_rtc.o

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build

all default: modules
install: modules_install

modules modules_install help clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(shell pwd) $@

