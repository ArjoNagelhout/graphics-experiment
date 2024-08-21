//
// Created by Arjo Nagelhout on 17/08/2024.
//

#include <iostream>
#include <cassert>

#include <MoltenVK/mvk_vulkan.h>

struct App
{
    // vulkan handles are simply pointers, do not contain any data
    // retrieving data needs to be done using functions
    VkInstance_T* instance;
    VkPhysicalDevice_T* physicalDevice;
    VkPhysicalDeviceProperties properties;
    VkDevice_T* device;
};

int main(int argc, char** argv)
{
    App app{};

    // create instance
    {
        VkApplicationInfo appInfo{
            .apiVersion = VK_API_VERSION_1_2
        };

        VkInstanceCreateInfo info{
            .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &appInfo
        };
        VkResult result = vkCreateInstance(&info, nullptr, &app.instance);
        assert(result == VK_SUCCESS);
    }

    // get physical device
    {
        uint32_t count = 0;
        vkEnumeratePhysicalDevices(app.instance, &count, nullptr);
        assert(count > 0);
        std::vector<VkPhysicalDevice_T*> devices(count);
        vkEnumeratePhysicalDevices(app.instance, &count, devices.data());
        app.physicalDevice = devices[0];

        vkGetPhysicalDeviceProperties(app.physicalDevice, &app.properties);
    }

    // create device
    {
        VkDeviceCreateInfo info{
            .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        };
        VkResult result = vkCreateDevice(app.physicalDevice, &info, nullptr, &app.device);
        assert(result == VK_SUCCESS);
    }

    std::cout << "hello world" << std::endl;
}