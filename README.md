# compute-texture-painter


A texture painting utility that offloads GDScript-intensive operations such as pixel processing and barycentric coordinate calculations to a compute shader.
Currently, the tool is in an early stage but can already function as a dynamic masking solution.
It uses collision shapes to retrieve relevant face data.

TODO:

- Dynamic brush switching

- Texture resizing

- Saving painted textures to files

- Accessing face data without relying on PhysicsServer, if possible


![Preview](readme_assets/preview.webp)