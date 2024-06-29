# metal-experiment 

![Screenshot](https://github.com/ArjoNagelhout/metal-experiment/assets/16051555/cb16a3a9-cec5-4bb2-997a-a233439b8112)

This experiment answers the question: "Why build a game engine when you can build directly on top of the graphics API?"
It follows these simple rules:
1. don't introduce abstractions until absolutely necessary. code duplication is good. you're too stupid to identify the right abstraction the first, second or third time.
2. hardcoding values is good
3. no object oriented programming shenanigans. It's a computer. Computers work with data, not an arbitrary model of the world.
4. Don't try to encapsulate. Everything can touch everything.
5. No arbitrary splits of responsibilities. There's only one app running. So there's one data structure: App.

# asset resources
https://polyhaven.com