local noise = require("noise")
data:extend{
    {
        type = "noise-expression",
        name = "rotation-random",
        intended_property = "spaghettorio-rotation",
        expression = noise.floor(((0 - (noise.random(1) - 1)) * 8)) -- int from 0 to 7. noise.random has (0, 1] normally
    }
}
