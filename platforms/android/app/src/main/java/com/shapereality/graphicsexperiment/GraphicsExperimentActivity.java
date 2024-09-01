package com.shapereality.graphicsexperiment;

import org.libsdl.app.SDLActivity;

/**
 * A sample wrapper class that just calls SDLActivity
 */

public class GraphicsExperimentActivity extends SDLActivity
{
    @Override protected String[] getLibraries() {
        return new String[] {
            "SDL3",
            "graphics_experiment"
        };
    }
}