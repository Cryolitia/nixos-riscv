obj-m += cv181x_saradc.o
cv181x_saradc-y := cvi_saradc.o

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build

all default: modules
install: modules_install

modules modules_install help clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(shell pwd) $@
