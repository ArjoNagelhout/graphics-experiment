# metal-experiment 

![Screenshot 1](https://github.com/user-attachments/assets/0b9083ae-c8ad-4c41-a08e-1b2e75acaece)

![Screenshot 2](https://github.com/user-attachments/assets/350fb0de-f1a7-4661-a0fe-50d69fde9a0e)

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
but porting is easier than implementing the features, so that is where the focus is initially.

### Experiments

List of features to implement or techniques to experiment with. This list is neither exhaustive nor prescriptive. 

#### Data
- [ ] CAD or BIM data (e.g. Revit, IFC using ifcOpenShell)
- [ ] 3D city data (Open Street Maps), Cesium (https://cesium.com/why-cesium/3d-tiles/)
- [X] Gltf import
- [ ] Gltf import with stride of 16 bytes instead of 12 for vector3, this is better for alignment. packed_float3 is not ideal.
- [ ] Scene file format -> utilize GLTF instead of inventing own scene model
- [ ] Collision (terrain collider, box collider)

#### Rendering techniques
- [X] Blinn phong shading
- [X] Fog
- [X] Skybox (panoramic / 360 spherical)
- [X] Compilation of shader variants
- [ ] PBR shading (OpenPBR Surface)
     - [X] conductor
     - [ ] dielectric
     - [ ] subsurface
- [ ] Deferred rendering (gbuffer etc., support many non-image based lights)
- [ ] Point lights, area lights, spot lights
- [ ] Animation / rigging of a mesh, skinning
- [ ] Multiple light sources (point light, directional light, colored lights) probably best with deferred rendering
- [ ] Automatic mip-mapping of textures for better interpolation at grazing angles
- [ ] Lens flare / post-processing effects
- [ ] Raytracing reflections, denoising
- [ ] Ambient occlusion baking using path tracing
- [ ] Screen-space ambient occlusion
- [ ] Screen space reflections
- [ ] Use cubemaps instead of equirectangular projection
- [ ] HDR support from image based lighting
- [ ] Specular reflection probes / environment probes
- [ ] Terrain system
     - [ ] Terrain normals (calculate derivatives for perlin noise terrain)
     - [ ] Grass / foliage / tree shader (animated with wind etc.)
     - [ ] Terrain chunks
- [ ] Particle system
- [ ] Water shader
- [ ] Hair shader
- [ ] Skin shader
- [ ] Frustum culling -> meshes should have bounds
- [ ] Occlusion culling
- [ ] LOD system
- [ ] 3d text rendering
- [ ] Stereoscopic rendering

Look at frame decompositions of games:
- e.g. https://www.adriancourreges.com/blog/2015/11/02/gta-v-graphics-study/
- and https://www.adriancourreges.com/blog/2016/09/09/doom-2016-graphics-study/

Asset resources:
- https://polyhaven.com
- https://sketchfab.com