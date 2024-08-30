//
// Created by Arjo Nagelhout on 22/08/2024.
//

#include <iostream>
#define VULKAN_HPP_RAII_NO_EXCEPTIONS
#define VULKAN_HPP_NO_EXCEPTIONS
#include <vulkan/vulkan_raii.hpp>

int main(int argc, char** argv)
{
    std::cout << "hello world" << std::endl;

    vk::raii::Context context;

    std::vector<vk::LayerProperties> layers = context.enumerateInstanceLayerProperties();
    for (vk::LayerProperties& layer: layers)
    {
        std::cout << layer.layerName << std::endl;
    }

    std::vector<vk::ExtensionProperties> extensions = context.enumerateInstanceExtensionProperties();
    for (vk::ExtensionProperties& extension: extensions)
    {
        std::cout << extension.extensionName << std::endl;
    }

    vk::ApplicationInfo appInfo(
        "App",
        {},
        {},
        {},
        vk::ApiVersion12
    );

    //char const* a = "VK_LAYER_KHRONOS_validation";

    vk::InstanceCreateInfo info(
        vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR,
        &appInfo,
        {},
        {vk::KHRPortabilityEnumerationExtensionName}
    );
    auto result = context.createInstance(info);
    if (!result.has_value())
    {
        auto error = result.error();
        std::cout << "error: " << to_string(error) << std::endl;
    }
}