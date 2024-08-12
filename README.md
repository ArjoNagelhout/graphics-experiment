# metal-experiment 

![Latest](https://github.com/user-attachments/assets/c26fc56a-c00a-4ecd-a050-3c2b78fa6ea0)

This open-ended experiment is intended to experiment with real-time graphics techniques and AEC data.
It is desktop first, but with the intention to support VR. Two broad scopes / directions are defined hereafter:

### Direction 1
A renderer that should be able to render an architectural scene in real-time. 
This architectural scene should be automatically created from BIM or CAD data. 
Assets should be able to be added to the scene using a simple editor. 

#### Applications
- Design review
- Presentation / architectural visualisation

#### User interaction
- [ ] Walk through the environment -> requires collision

### Direction 2
A conceptual design tool for creating architectural concepts and rendering them in real time in VR. 
Simple procedural geometry tools, simple parametric tools. This conceptual design should be exportable 
to an external program. 

### Graphics API and supported platforms
The application is written for Cocoa (macOS) and the Metal API, but for VR should be ported to Vulkan. Metal is 
a cleaner API, so we might want to write a Vulkan backend for the Metal API (or a subset of the Metal API we use) 
but porting is easier than implementing the features, focus is on implementing features first. 

### Experiments

List of features to implement or techniques to experiment with. This list is neither exhaustive nor prescriptive. 

#### Data
- [ ] CAD or BIM data (e.g. Revit, IFC using ifcOpenShell)
- [ ] OpenCascade or another CAD kernel for generating geometry from certain representations such as BReps or Nurbs. 
- [ ] 3D city data (Open Street Maps), Cesium (https://cesium.com/why-cesium/3d-tiles/)
- [X] Gltf import
- [ ] Gltf import with stride of 16 bytes instead of 12 for vector3, this is better for alignment. packed_float3 is not ideal.
- [ ] Scene file format -> utilize GLTF instead of inventing own scene model
- [ ] Collision (terrain collider, box collider)
- [ ] Asynchronous loading and decoding of png / jpeg
- [ ] Caching of imported textures / other assets

#### Rendering techniques
- [X] Directional light shadow mapping
- [X] Blinn phong shading
- [X] Fog
- [X] Skybox (panoramic / 360 spherical)
- [X] Compilation of shader variants
- [ ] PBR shading (OpenPBR Surface)
  - [X] conductors
  - [X] dielectrics
  - [ ] subsurface
  - [ ] transmission
  - [ ] coat
  - [ ] glass
- [ ] Batch rendering primitives by material (to avoid constantly switching fragment shader buffers etc.)
- [ ] Shadow volumes (https://en.wikipedia.org/wiki/Shadow_volume)
- [ ] Megatextures (https://en.wikipedia.org/wiki/Clipmap)
- [ ] Deferred rendering (gbuffer etc., support many non-image based lights)
- [ ] Point lights, area lights, spot lights, directional lights
- [ ] Animation / rigging of a mesh, skinning
- [ ] Automatic mip-mapping of textures for better interpolation at grazing angles
- [ ] Raytracing reflections, denoising
- [ ] Ambient occlusion baking using path tracing
- [ ] Specular reflection probes / environment probes
- [ ] Screen space reflections
- [ ] Screen-space ambient occlusion
- [ ] Lens flare / post-processing effects
- [ ] Support cubemaps instead of equirectangular projection
- [ ] HDR support for image based lighting
- [ ] Terrain system
  - [ ] Heightmaps
  - [ ] Erosion / simulation
  - [ ] Tri-planar mapping
  - [ ] Terrain chunks / LOD system
- [ ] Particle systems (fire)
- [ ] Volumetrics / volumetric fog
- [ ] Grass / foliage / tree vertex shader (animated with wind etc.)
- [ ] Water / ocean shader
- [ ] Hair shader
- [ ] Skin shader (optimized, subsurface scattering)
- [ ] Frustum culling -> meshes should have bounds
- [ ] Occlusion culling -> could be done by specific middleware? / on the GPU?
- [ ] LOD system and blending
- [ ] Proper text rendering (glyph caching, using truetype / opentype rendering library), use signed distance fields (SDF) for 3D text rendering. 
- [ ] Stereoscopic rendering for VR

Look at frame decompositions of games:
- e.g. https://www.adriancourreges.com/blog/2015/11/02/gta-v-graphics-study/
- and https://www.adriancourreges.com/blog/2016/09/09/doom-2016-graphics-study/

### Asset resources
- https://polyhaven.com
- https://sketchfab.com
