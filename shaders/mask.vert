/*
    Copyright © 2020, nijigenerate Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
#version 330
uniform mat4 mvp;
uniform vec2 offset;
layout(location = 0) in vec2 verts;
layout(location = 1) in vec2 deform;

out vec2 texUVs;

void main() {
    gl_Position = mvp * vec4(verts.x-offset.x+deform.x, verts.y-offset.y+deform.y, 0, 1);
}