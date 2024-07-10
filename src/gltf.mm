//
// Created by Arjo Nagelhout on 09/07/2024.
//

#include "gltf.h"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"
#include "turbojpeg.h"
#include "lodepng.h"

#include <cassert>
#include <iostream>

bool importGltf(id <MTLDevice> device, std::filesystem::path const& path, GltfModel* outModel)
{
    assert(exists(path));

    // parse file
    cgltf_options options = {
        .type = cgltf_file_type_invalid, // = auto detect
        .file = cgltf_file_options{}
    };
    cgltf_data* cgltfData = nullptr;
    cgltf_result parseFileResult = cgltf_parse_file(&options, path.c_str(), &cgltfData);
    if (parseFileResult != cgltf_result_success)
    {
        cgltf_free(cgltfData);
        std::cout << "Failed to parse gltf file" << std::endl;
        exit(1);
    }

    // load buffers
    cgltf_result loadBuffersResult = cgltf_load_buffers(&options, cgltfData, path.c_str());
    if (loadBuffersResult != cgltf_result_success)
    {
        cgltf_free(cgltfData);
        std::cout << "Failed to load buffers, this can be due to .bin files not being located next to the file" << std::endl;
        exit(1);
    }

    // images
    {
        for (int i = 0; i < cgltfData->images_count; i++)
        {
            cgltf_image* image = &cgltfData->images[i];

            if (image->uri != nullptr)
            {
                if (strncmp(image->uri, "data:", 5) == 0)
                {
                    // data URI (string starts with data:content/type;base64,)
                    // todo
                }
                else
                {
                    // load from disk
                    std::filesystem::path imagePath = image->uri;
                    // todo
                }
            }
            else
            {
                // load from buffer view

                // buffer view type is invalid, but it is simply not set, which is the case for image buffers
                cgltf_buffer_view* bufferView = image->buffer_view;
                unsigned char const* imageBuffer = cgltf_buffer_view_data(bufferView);
                assert(imageBuffer != nullptr);
                size_t bufferSize = bufferView->size;

                int width, height;
                std::vector<unsigned char> decompressedImage;

                // mime_type is guaranteed to be set
                if (strcmp(image->mime_type, "image/jpeg") == 0)
                {
                    // decompress jpeg
                    {
                        tjhandle tjInstance = tjInitDecompress();
                        assert(tjInstance != nullptr);
                        int jpegSubsampling, jpegColorspace;
                        if (tjDecompressHeader3(tjInstance, imageBuffer, bufferSize, &width, &height, &jpegSubsampling, &jpegColorspace) < 0)
                        {
                            // error
                            tj3Destroy(tjInstance);
                            std::cerr << "Error decompressing JPEG: " << tjGetErrorStr() << std::endl;
                            exit(1);
                        }
                        assert(jpegColorspace == 1);

                        //int pixelSize = tjPixelSize[jpegColorspace]; // pixel size in samples
                        decompressedImage.resize(width * height * 4); // rgba

                        if (tjDecompress2(
                            tjInstance,
                            imageBuffer,
                            bufferSize,
                            decompressedImage.data(),
                            width,
                            0 /* pitch */,
                            height,
                            TJPF_RGBA,
                            TJFLAG_FASTDCT) < 0)
                        {
                            std::cerr << "Error decompressing JPEG: " << tjGetErrorStr() << std::endl;
                            exit(1);
                        }
                        tj3Destroy(tjInstance);
                    }
                }
                else if (strcmp(image->mime_type, "image/png") == 0)
                {
                    // decode png
                    {
                        lodepng::State state;
                        state.info_raw.bitdepth = 8;
                        state.info_raw.colortype = LodePNGColorType::LCT_RGBA;
                        unsigned w, h;
                        unsigned error = lodepng::decode(decompressedImage, w, h, state, imageBuffer, bufferSize);
                        width = (int)w;
                        height = (int)h;

                        if (error != 0)
                        {
                            std::cout << lodepng_error_text(error) << std::endl;
                            exit(1);
                        }
                    }

                }
                else
                {
                    assert(false && "only jpeg and png are supported");
                }

                // upload to gpu
                {
                    MTLTextureDescriptor* descriptor = [[MTLTextureDescriptor alloc] init];
                    descriptor.width = width;
                    descriptor.height = height;
                    descriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
                    descriptor.arrayLength = 1;
                    descriptor.textureType = MTLTextureType2D;
                    descriptor.usage = MTLTextureUsageShaderRead;
                    id <MTLTexture> texture = [device newTextureWithDescriptor:descriptor];

                    size_t strideInBytes = 4; // for each component 1 byte = 8 bits

                    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
                    [texture
                        replaceRegion:region
                        mipmapLevel:0
                        slice:0
                        withBytes:decompressedImage.data()
                        bytesPerRow:width * strideInBytes
                        bytesPerImage:0]; // only single image

                    outModel->textures.emplace_back(texture);
                }

                std::cout << "imported image: name: " << (bufferView->name ? bufferView->name : "") << ", width: " << width << ", height: " << height << std::endl;
            }

            //std::cout << imagePath << std::endl;
        }
    }


    cgltf_free(cgltfData);
    return true;
}