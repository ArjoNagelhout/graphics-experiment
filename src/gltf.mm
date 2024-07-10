//
// Created by Arjo Nagelhout on 09/07/2024.
//

#include "gltf.h"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

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
    cgltf_data* data = nullptr;
    cgltf_result parseFileResult = cgltf_parse_file(&options, path.c_str(), &data);
    if (parseFileResult != cgltf_result_success)
    {
        cgltf_free(data);
        std::cout << "Failed to parse gltf file" << std::endl;
        exit(1);
    }

    // load buffers
    cgltf_result loadBuffersResult = cgltf_load_buffers(&options, data, path.c_str());
    if (loadBuffersResult != cgltf_result_success)
    {
        cgltf_free(data);
        std::cout << "Failed to load buffers, this can be due to .bin files not being located next to the file" << std::endl;
        exit(1);
    }

    // images
    {
        for (int i = 0; i < data->images_count; i++)
        {
            cgltf_image* image = &data->images[i];

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
                // mime_type is guaranteed to be set
                if (strcmp(image->mime_type, "image/jpeg") == 0)
                {
                    cgltf_buffer_view* bufferView = image->buffer_view;

                }
                else if (strcmp(image->mime_type, "image/png") == 0)
                {

                }
                else
                {
                    assert(false && "only jpeg and png are supported");
                }
            }

            //std::cout << imagePath << std::endl;
        }
    }


    cgltf_free(data);
    return true;
}