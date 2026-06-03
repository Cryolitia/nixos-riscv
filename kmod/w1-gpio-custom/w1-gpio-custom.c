/*
# 格式：bus0=<ID>,<引腳編號>,<是否開漏>
# ID建議填0，引腳填498，開漏填1
sudo insmod w1-gpio-custom.ko bus0=0,498,1
*/

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/gpio/machine.h>

static unsigned int bus0[3]; 
static int nump;
module_param_array(bus0, uint, &nump, 0444);

static struct platform_device *pdev;
static struct gpiod_lookup_table *lookup;

static int __init w1_custom_init(void)
{
	if (nump < 2) return -EINVAL;

	/* 1. 分配空间：必须包含 2 个 entry（1个数据，1个作为结尾符） */
	lookup = kzalloc(sizeof(*lookup) + 2 * sizeof(struct gpiod_lookup), GFP_KERNEL);
	if (!lookup) return -ENOMEM;

	lookup->dev_id = kasprintf(GFP_KERNEL, "w1-gpio.%u", bus0[0]);
	
	lookup->table[0].key = NULL;          /* NULL 代表全局引脚编号 */
	lookup->table[0].chip_hwnum = bus0[1];
	lookup->table[0].con_id = NULL;
	lookup->table[0].idx = 0;
	lookup->table[0].flags = (bus0[2]) ? (GPIO_ACTIVE_HIGH | GPIO_OPEN_DRAIN) : GPIO_ACTIVE_HIGH;

	gpiod_add_lookup_table(lookup);

	/* 2. 注册平台设备 */
	pdev = platform_device_register_simple("w1-gpio", bus0[0], NULL, 0);
	if (IS_ERR(pdev)) {
		gpiod_remove_lookup_table(lookup);
		kfree(lookup->dev_id);
		kfree(lookup);
		return PTR_ERR(pdev);
	}

	return 0;
}

static void __exit w1_custom_exit(void)
{
	platform_device_unregister(pdev);
	gpiod_remove_lookup_table(lookup);
	kfree(lookup->dev_id);
	kfree(lookup);
}

module_init(w1_custom_init);
module_exit(w1_custom_exit);
MODULE_LICENSE("GPL");
