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

#include "glm/gtc/type_ptr.hpp"

[[nodiscard]] VertexAttributeType convertGltfAttributeType(cgltf_attribute_type type)
{
    switch (type)
    {
        case cgltf_attribute_type_invalid: assert(false);
        case cgltf_attribute_type_position: return VertexAttributeType::Position;
        case cgltf_attribute_type_normal: return VertexAttributeType::Normal;
        case cgltf_attribute_type_tangent: return VertexAttributeType::Tangent;
        case cgltf_attribute_type_texcoord: return VertexAttributeType::TextureCoordinate;
        case cgltf_attribute_type_color: return VertexAttributeType::Color;
        case cgltf_attribute_type_joints: return VertexAttributeType::Joints;
        case cgltf_attribute_type_weights: return VertexAttributeType::Weights;
        case cgltf_attribute_type_custom: assert(false);
        case cgltf_attribute_type_max_enum: assert(false);
        default: assert(false);
    }
    return VertexAttributeType::Position;
}

bool importGltf(id <MTLDevice> device, std::filesystem::path const& path, model::Model* outModel)
{
    assert(exists(path));
    assert(outModel != nullptr);

    // parse file
    cgltf_options cgltfOptions = {
        .type = cgltf_file_type_invalid, // = auto detect
        .file = cgltf_file_options{}
    };
    cgltf_data* cgltfData = nullptr;
    cgltf_result parseFileResult = cgltf_parse_file(&cgltfOptions, path.c_str(), &cgltfData);
    if (parseFileResult != cgltf_result_success)
    {
        cgltf_free(cgltfData);
        std::cout << "Failed to parse gltf file" << std::endl;
        exit(1);
    }

    // load buffers
    cgltf_result loadBuffersResult = cgltf_load_buffers(&cgltfOptions, cgltfData, path.c_str());
    if (loadBuffersResult != cgltf_result_success)
    {
        cgltf_free(cgltfData);
        std::cout << "Failed to load buffers, this can be due to .bin files not being located next to the file" << std::endl;
        exit(1);
    }

    // images
    if (1)
    {
        for (int i = 0; i < cgltfData->images_count; i++)
        {
            cgltf_image* image = &cgltfData->images[i];

            if (image->uri != nullptr)
            {
                if (strlen(image->uri) >= 5 && strncmp(image->uri, "data:", 5) == 0)
                {
                    // data URI (string starts with data:content/type;base64,)
                    // todo
                    assert(false && "unimplemented");
                }
                else
                {
                    // load from disk
                    std::filesystem::path imagePath = image->uri;
                    // todo
                    assert(false && "unimplemented");
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

                std::cout << "imported image: name: " << (bufferView->name ? bufferView->name : "") << ", width: " << width << ", height: " << height
                          << std::endl;
            }

            //std::cout << imagePath << std::endl;
        }
    }

    // meshes / primitives
    {
        static_assert(std::is_same_v<cgltf_float, float>);
        static_assert(std::is_same_v<cgltf_size, size_t>);

        for (int i = 0; i < cgltfData->meshes_count; i++)
        {
            model::Mesh* outMesh = &outModel->meshes.emplace_back();

            cgltf_mesh* mesh = &cgltfData->meshes[i];
            std::cout << "mesh name: " << (mesh->name ? mesh->name : "") << std::endl;

            for (int j = 0; j < mesh->primitives_count; j++)
            {
                model::Primitive* outPrimitive = &outMesh->primitives.emplace_back();
                cgltf_primitive* primitive = &mesh->primitives[j];

                // set primitive type
                {
                    MTLPrimitiveType t;
                    //@formatter:off
                    switch (primitive->type)
                    {
                        case cgltf_primitive_type_invalid:assert(false); break;
                        case cgltf_primitive_type_points:t = MTLPrimitiveTypePoint; break;
                        case cgltf_primitive_type_lines:t = MTLPrimitiveTypeLine; break;
                        case cgltf_primitive_type_line_loop:assert(false); break;
                        case cgltf_primitive_type_line_strip:t = MTLPrimitiveTypeLineStrip; break;
                        case cgltf_primitive_type_triangles:t = MTLPrimitiveTypeTriangle; break;
                        case cgltf_primitive_type_triangle_strip:t = MTLPrimitiveTypeTriangleStrip; break;
                        case cgltf_primitive_type_triangle_fan:assert(false); break;
                        case cgltf_primitive_type_max_enum:assert(false); break;
                    }
                    //@formatter:on
                    outPrimitive->primitive.primitiveType = t;
                }

                // get data for each attribute
                outPrimitive->primitive.vertexCount = std::numeric_limits<size_t>::max();
                size_t totalVertexBufferSize = 0;
                for (int k = 0; k < primitive->attributes_count; k++)
                {
                    VertexAttribute* outAttribute = &outPrimitive->primitive.attributes.emplace_back();
                    cgltf_attribute* attribute = &primitive->attributes[k];
                    outAttribute->type = convertGltfAttributeType(attribute->type);
                    std::cout << "attribute: " << (attribute->name ? attribute->name : "") << std::endl;

                    assert(outPrimitive->primitive.vertexCount == std::numeric_limits<size_t>::max() || outPrimitive->primitive.vertexCount == attribute->data->count);
                    outPrimitive->primitive.vertexCount = attribute->data->count;
                    assert(attribute->data->component_type == cgltf_component_type_r_32f && "only float component type is implemented");

                    outAttribute->componentCount = cgltf_num_components(attribute->data->type);
                    outAttribute->size = outAttribute->componentCount * sizeof(float) * outPrimitive->primitive.vertexCount;
                    totalVertexBufferSize += outAttribute->size;
                }

                // populate vertex buffer
                std::vector<unsigned char> values(totalVertexBufferSize);
                size_t offset = 0;
                for (int k = 0; k < primitive->attributes_count; k++)
                {
                    VertexAttribute* outAttribute = &outPrimitive->primitive.attributes[k];
                    cgltf_attribute* attribute = &primitive->attributes[k];

                    auto* begin = (float*)&values[offset];
                    size_t floatCount = outAttribute->componentCount * outPrimitive->primitive.vertexCount;
                    size_t floatsUnpacked = cgltf_accessor_unpack_floats(attribute->data, begin, floatCount);
                    assert(floatsUnpacked == floatCount);

                    offset += outAttribute->size;
                }

                // upload vertex buffer to GPU
                {
                    MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
                    outPrimitive->primitive.vertexBuffer = [device newBufferWithBytes:values.data() length:values.size() * sizeof(unsigned char) options:options];
                }

                // populate index buffer and upload to GPU
                {
                    outPrimitive->primitive.indexCount = primitive->indices->count;
                    outPrimitive->primitive.indexed = true;
                    size_t componentSize = cgltf_component_size(primitive->indices->component_type);
                    if (componentSize == 4) // 32 bits
                    {
                        outPrimitive->primitive.indexType = MTLIndexTypeUInt32;
                    }
                    else if (componentSize == 2) // 16 bits
                    {
                        outPrimitive->primitive.indexType = MTLIndexTypeUInt16;
                    }
                    else
                    {
                        assert(false && "invalid index component type");
                    }

                    std::vector<unsigned char> indexBuffer(componentSize * outPrimitive->primitive.indexCount);
                    size_t unpackedIndices = cgltf_accessor_unpack_indices(primitive->indices, indexBuffer.data(), componentSize, outPrimitive->primitive.indexCount);
                    assert(unpackedIndices == outPrimitive->primitive.indexCount);

                    MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
                    outPrimitive->primitive.indexBuffer = [device
                        newBufferWithBytes:indexBuffer.data()
                        length:indexBuffer.size() * sizeof(unsigned char) options:options];
                }

                // material
                {
                    if (primitive->material != nullptr)
                    {
                        outPrimitive->materialIndex = cgltf_material_index(cgltfData, primitive->material);
                    }
                }
            }
        }
    }

    // materials
    {
        for (int i = 0; i < cgltfData->materials_count; i++)
        {
            model::Material* outMaterial = &outModel->materials.emplace_back();
            cgltf_material* material = &cgltfData->materials[i];
            assert(material->has_pbr_metallic_roughness);
            cgltf_pbr_metallic_roughness mat = material->pbr_metallic_roughness;

            cgltf_texture* normal = material->normal_texture.texture;
            if (normal != nullptr)
            {
                outMaterial->normalMap = cgltf_image_index(cgltfData, normal->image);
            }

            cgltf_texture* baseColor = mat.base_color_texture.texture;
            if (baseColor != nullptr)
            {
                outMaterial->baseColorMap = cgltf_image_index(cgltfData, baseColor->image);
            }

            cgltf_texture* metallicRoughness = mat.metallic_roughness_texture.texture;
            if (metallicRoughness != nullptr)
            {
                outMaterial->metallicRoughnessMap = cgltf_image_index(cgltfData, metallicRoughness->image);
            }

            cgltf_texture* emissive = material->emissive_texture.texture;
            if (emissive != nullptr)
            {
                outMaterial->emissionMap = cgltf_image_index(cgltfData, emissive->image);
            }
        }
    }

    // nodes
    {
        for (int i = 0; i < cgltfData->nodes_count; i++)
        {
            cgltf_node* node = &cgltfData->nodes[i];
            model::Node* outNode = &outModel->nodes.emplace_back();

            float* a = glm::value_ptr(outNode->localTransform);
            cgltf_node_transform_local(node, a);

            if (node->mesh != nullptr)
            {
                outNode->meshIndex = cgltf_mesh_index(cgltfData, node->mesh);
            }

            for (int j = 0; j < node->children_count; j++)
            {
                outNode->childNodes.emplace_back(cgltf_node_index(cgltfData, node->children[j]));
            }
        }
    }

    // scenes
    {
        for (int i = 0; i < cgltfData->scenes_count; i++)
        {
            cgltf_scene* scene = &cgltfData->scenes[i];
            model::Scene* outScene = &outModel->scenes.emplace_back();

            // create root node that contains scene root nodes as children
            // makes traversal easier
            model::Node* rootNode = &outModel->nodes.emplace_back();
            size_t rootNodeIndex = outModel->nodes.size() - 1;
            outScene->rootNode = rootNodeIndex;

            for (int j = 0; j < scene->nodes_count; j++)
            {
                cgltf_node* node = scene->nodes[j];
                rootNode->childNodes.emplace_back(cgltf_node_index(cgltfData, node));
            }
        }
    }

    cgltf_free(cgltfData);
    return true;
}