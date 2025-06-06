/*
    nijilive MeshGroup Node
    previously Inochi2D MeshGroup Node

    Copyright © 2020, Inochi2D Project
    Copyright © 2024, nijigenerate Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module nijilive.core.nodes.meshgroup;
import nijilive.core.nodes.drawable;
import nijilive.core.nodes.deformer.path;
import nijilive.integration;
import nijilive.fmt.serialize;
import nijilive.math;
import nijilive.math.triangle;
import std.exception;
import nijilive.core.dbg;
import nijilive.core;
import std.typecons: tuple, Tuple;
//import std.stdio;
import nijilive.core.nodes.utils;
import std.algorithm.searching;
import std.algorithm;
import std.string;

package(nijilive) {
    void inInitMeshGroup() {
        inRegisterNodeType!MeshGroup;
    }
}


private {
struct Triangle{
    mat3 offsetMatrices;
    mat3 transformMatrix;
}

}

/**
    Contains various deformation shapes that can be applied to
    children of this node
*/
@TypeId("MeshGroup")
class MeshGroup : Drawable, NodeFilter {
    mixin NodeFilterMixin;

protected:
    ushort[] bitMask;
    vec4 bounds;
    Triangle[] triangles;
    vec2[] transformedVertices = [];
    mat4 forwardMatrix;
    mat4 inverseMatrix;
    bool translateChildren = true;

    override
    string typeId() { return "MeshGroup"; }

    bool precalculated = false;

    override
    void preProcess() {
        super.preProcess();
    }

    override
    void postProcess(int id = 0) {
        super.postProcess(id);
    }

public:
    bool dynamic = false;

    /**
        Constructs a new MeshGroup node
    */
    this(Node parent = null) {
        super(parent);
    }

    Tuple!(vec2[], mat4*, bool) filterChildren(Node target, vec2[] origVertices, vec2[] origDeformation, mat4* origTransform) {
        if (!precalculated)
            return Tuple!(vec2[], mat4*, bool)(null, null, false);

        if (auto deformer = cast(PathDeformer)target) {
            if (!deformer.physicsEnabled) {
                return Tuple!(vec2[], mat4*, bool)(null, null, false);
            }
        }

        mat4 centerMatrix = inverseMatrix * (*origTransform);

        // Transform children vertices in MeshGroup coordinates.
        auto r = rect(bounds.x, bounds.y, (ceil(bounds.z) - floor(bounds.x) + 1), (ceil(bounds.w) - floor(bounds.y) + 1));
        foreach(i, vertex; origVertices) {
            vec2 cVertex;
            if (dynamic)
                cVertex = vec2(centerMatrix * vec4(vertex+origDeformation[i], 0, 1));
            else
                cVertex = vec2(centerMatrix * vec4(vertex, 0, 1));
            int index = -1;
            if (bounds.x <= cVertex.x && cVertex.x < bounds.z && bounds.y <= cVertex.y && cVertex.y < bounds.w) {
                ushort bit = bitMask[cast(int)(cVertex.y - bounds.y) * cast(int)r.width + cast(int)(cVertex.x - bounds.x)];
                index = bit - 1;
            }
            vec2 newPos = (index < 0)? cVertex: (triangles[index].transformMatrix * vec3(cVertex, 1)).xy;
            mat4 inv = centerMatrix.inverse;
            inv[0][3] = 0;
            inv[1][3] = 0;
            inv[2][3] = 0;
            origDeformation[i] += (inv * vec4(newPos - cVertex, 0, 1)).xy;
        }

        return tuple(origDeformation, cast(mat4*)null, changed);
    }

    /**
        A list of the shape offsets to apply per part
    */
    override
    void update() {
        preProcess();
        deformStack.update();
        
        if (data.indices.length > 0) {
            if (!precalculated) {
                precalculate();
            }
            transformedVertices.length = vertices.length;
            foreach(i, vertex; vertices) {
                transformedVertices[i] = vertex+this.deformation[i];
            }
            foreach (index; 0..triangles.length) {
                auto p1 = transformedVertices[data.indices[index * 3]];
                auto p2 = transformedVertices[data.indices[index * 3 + 1]];
                auto p3 = transformedVertices[data.indices[index * 3 + 2]];
                triangles[index].transformMatrix = mat3([p2.x - p1.x, p3.x - p1.x, p1.x,
                                                        p2.y - p1.y, p3.y - p1.y, p1.y,
                                                        0, 0, 1]) * triangles[index].offsetMatrices;
            }
            forwardMatrix = transform.matrix;
            inverseMatrix = globalTransform.matrix.inverse;
        }

        Node.update();
   }

    override
    void draw() {
        super.draw();
    }


    void precalculate() {
        if (data.indices.length == 0) {
            triangles.length = 0;
            bitMask.length   = 0;
            return;
        }

        vec4 getBounds(T)(ref T vertices) {
            vec4 bounds = vec4(float.max, float.max, -float.max, -float.max);
            foreach (v; vertices) {
                bounds = vec4(min(bounds.x, v.x), min(bounds.y, v.y), max(bounds.z, v.x), max(bounds.w, v.y));
            }
            bounds.x = floor(bounds.x);
            bounds.y = floor(bounds.y);
            bounds.z = ceil(bounds.z);
            bounds.w = ceil(bounds.w);
            return bounds;
        }

        // Calculating conversion matrix for triangles
        bounds = getBounds(data.vertices);
        triangles.length = 0;
        foreach (i; 0..data.indices.length / 3) {
            Triangle t;
            vec2[3] tvertices = [
                data.vertices[data.indices[3*i]],
                data.vertices[data.indices[3*i+1]],
                data.vertices[data.indices[3*i+2]]
            ];
            
            vec2* p1 = &tvertices[0];
            vec2* p2 = &tvertices[1];
            vec2* p3 = &tvertices[2];

            vec2 axis0 = *p2 - *p1;
            float axis0len = axis0.length;
            axis0 /= axis0len;
            vec2 axis1 = *p3 - *p1;
            float axis1len = axis1.length;
            axis1 /= axis1len;

            vec3 raxis1 = mat3([axis0.x, axis0.y, 0, -axis0.y, axis0.x, 0, 0, 0, 1]) * vec3(axis1, 1);
            float cosA = raxis1.x;
            float sinA = raxis1.y;
            t.offsetMatrices = 
                mat3([axis0len > 0? 1/axis0len: 0, 0, 0,
                        0, axis1len > 0? 1/axis1len: 0, 0,
                        0, 0, 1]) * 
                mat3([1, -cosA/sinA, 0, 
                        0, 1/sinA, 0, 
                        0, 0, 1]) * 
                mat3([axis0.x, axis0.y, 0, 
                        -axis0.y, axis0.x, 0, 
                        0, 0, 1]) * 
                mat3([1, 0, -(p1).x, 
                        0, 1, -(p1).y, 
                        0, 0, 1]);
            triangles ~= t;
        }

        // Construct bitMap
        int width  = cast(int)(ceil(bounds.z) - floor(bounds.x) + 1);
        int height = cast(int)(ceil(bounds.w) - floor(bounds.y) + 1);
        bitMask.length = width * height;
        bitMask[] = 0;
        foreach (size_t i, t; triangles) {
            vec2[3] tvertices = [
                data.vertices[data.indices[3*i]],
                data.vertices[data.indices[3*i+1]],
                data.vertices[data.indices[3*i+2]]
            ];

            vec4 tbounds = getBounds(tvertices);
            int bwidth  = cast(int)(ceil(tbounds.z) - floor(tbounds.x) + 1);
            int bheight = cast(int)(ceil(tbounds.w) - floor(tbounds.y) + 1);
            int top  = cast(int)floor(tbounds.y);
            int left = cast(int)floor(tbounds.x);
            foreach (y; 0..bheight) {
                foreach (x; 0..bwidth) {
                    vec2 pt = vec2(left + x, top + y);
                    if (isPointInTriangle(pt, tvertices)) {
                        ushort id = cast(ushort)(i + 1);
                        pt-= bounds.xy;
                        bitMask[cast(int)(pt.y * width + pt.x)] = id;
                    }
                }
            }
        }

        precalculated = true;
        foreach (child; children) {
            setupChild(child);
        }
    }

    override
    void renderMask(bool dodge = false) {

    }

    override
    void rebuffer(ref MeshData data) {
        super.rebuffer(data);
        if (dynamic) {
            precalculated = false;
        }
    }

    override
    void serializeSelfImpl(ref InochiSerializer serializer, bool recursive = true) {
        super.serializeSelfImpl(serializer, recursive);

        serializer.putKey("dynamic_deformation");
        serializer.serializeValue(dynamic);

        serializer.putKey("translate_children");
        serializer.serializeValue(translateChildren);
    }

    override
    SerdeException deserializeFromFghj(Fghj data) {
        super.deserializeFromFghj(data);

        if (!data["dynamic_deformation"].isEmpty) 
            data["dynamic_deformation"].deserializeValue(dynamic);

        translateChildren = false;
        if (!data["translate_children"].isEmpty)
            data["translate_children"].deserializeValue(translateChildren);

        return null;
    }

    bool setupChildNoRecurse(bool prepend = false)(Node node) {
        auto drawable = cast(Deformable)node;
        bool isDeformable = drawable !is null;
        if (translateChildren || isDeformable) {
            if (isDeformable && dynamic) {
                node.preProcessFilters  = node.preProcessFilters.removeByValue(tuple(0, &filterChildren));
                node.postProcessFilters = node.postProcessFilters.upsert!(Node.Filter, prepend)(tuple(0, &filterChildren));
            } else {
                node.preProcessFilters  = node.preProcessFilters.upsert!(Node.Filter, prepend)(tuple(0, &filterChildren));
                node.postProcessFilters = node.postProcessFilters.removeByValue(tuple(0, &filterChildren));
            }
        } else {
            node.preProcessFilters  = node.preProcessFilters.removeByValue(tuple(0, &filterChildren));
            node.postProcessFilters = node.postProcessFilters.removeByValue(tuple(0, &filterChildren));
        }
        return false;
     }

    override
    bool setupChild(Node child) {
        super.setupChild(child);
        void setGroup(Node node) {
            bool mustPropagate = node.mustPropagate();
            setupChildNoRecurse(node);
            // traverse children if node is Deformable and is not MeshGroup instance.
            if (mustPropagate) {
                foreach (child; node.children) {
                    setGroup(child);
                }
            }
        }

        if (data.indices.length > 0) {
            setGroup(child);
        } 

        return false;
    }


    bool releaseChildNoRecurse(Node node) {
        node.preProcessFilters = node.preProcessFilters.removeByValue(tuple(0, &this.filterChildren));
        node.postProcessFilters = node.postProcessFilters.removeByValue(tuple(0, &this.filterChildren));
        return false;
    }

    override
    bool releaseChild(Node child) {
        void unsetGroup(Node node) {
            releaseChildNoRecurse(node);

            bool mustPropagate = node.mustPropagate();
            if (mustPropagate) {
                foreach (child; node.children) {
                    unsetGroup(child);
                }
            }
        }
        unsetGroup(child);
        super.releaseChild(child);
        return false;
    }

    override
    void captureTarget(Node target) {
        children_ref ~= target;
        setupChildNoRecurse!true(target);
    }

    override
    void releaseTarget(Node target) {
        releaseChildNoRecurse(target);
        children_ref = children_ref.removeByValue(target);
    }


    void applyDeformToChildren(Parameter[] params, bool recursive = true) {
        if (dynamic || data.indices.length == 0)
            return;

        if (!precalculated) {
            precalculate();
        }
        forwardMatrix = transform.matrix;
        inverseMatrix = globalTransform.matrix.inverse;

        void update(vec2[] deformation) {
            transformedVertices.length = vertices.length;
            foreach(i, vertex; vertices) {
                transformedVertices[i] = vertex + deformation[i];
            }
            foreach (index; 0..triangles.length) {
                auto p1 = transformedVertices[data.indices[index * 3]];
                auto p2 = transformedVertices[data.indices[index * 3 + 1]];
                auto p3 = transformedVertices[data.indices[index * 3 + 2]];
                triangles[index].transformMatrix = mat3([p2.x - p1.x, p3.x - p1.x, p1.x,
                                                        p2.y - p1.y, p3.y - p1.y, p1.y,
                                                        0, 0, 1]) * triangles[index].offsetMatrices;
            }
        }

        bool transfer() {
            return translateChildren;
        }

        _applyDeformToChildren(tuple(0, &filterChildren), &update, &transfer, params, recursive);

        data.indices.length = 0;
        data.vertices.length = 0;
        data.uvs.length = 0;
        rebuffer(data);
        translateChildren = false;
        precalculated = false;
    }

    void switchMode(bool dynamic) {
        if (this.dynamic != dynamic) {
            this.dynamic = dynamic;
            precalculated = false;
        }
    }

    bool getTranslateChildren() { return translateChildren; }

    void setTranslateChildren(bool value) {
        translateChildren = value;
        foreach (child; children)
            setupChild(child);
    }

    override
    void clearCache() {
        precalculated = false;
        bitMask.length = 0;
        triangles.length = 0;
    }

    override
    void centralize() {
        super.centralize();
        vec4 bounds;
        vec4[] childTranslations;
        if (children.length > 0) {
            bounds = children[0].getCombinedBounds();
            foreach (child; children) {
                auto cbounds = child.getCombinedBounds();
                bounds.x = min(bounds.x, cbounds.x);
                bounds.y = min(bounds.y, cbounds.y);
                bounds.z = max(bounds.z, cbounds.z);
                bounds.w = max(bounds.w, cbounds.w);
                childTranslations ~= child.transform.matrix() * vec4(0, 0, 0, 1);
            }
        } else {
            bounds = transform.translation.xyxy;
        }
        vec2 center = (bounds.xy + bounds.zw) / 2;
        if (parent !is null) {
            center = (parent.transform.matrix.inverse * vec4(center, 0, 1)).xy;
        }
        auto diff = center - localTransform.translation.xy;
        localTransform.translation.x = center.x;
        localTransform.translation.y = center.y;
        foreach (ref v; vertices) {
            v -= diff;
        }
        transformChanged();
        clearCache();
        updateBounds();
        foreach (i, child; children) {
            child.localTransform.translation = (transform.matrix.inverse * childTranslations[i]).xyz;
            child.transformChanged();
        }
    }

    override
    void copyFrom(Node src, bool clone = false, bool deepCopy = true) {
        super.copyFrom(src, clone, deepCopy);

        if (auto mgroup = cast(MeshGroup)src) {
            dynamic = mgroup.dynamic;
            translateChildren = mgroup.translateChildren;
            clearCache();
        } else if (auto dcomposite = cast(DynamicComposite)src) {
//            dynamic = true;  // disabled dynamic mode by default.
            translateChildren = true;
            clearCache();
        }
    }

    override
    void build(bool force = false) { 
        if (force || !precalculated) {
            precalculate();
        }
        foreach (child; children) {
            setupChild(child);
        }
        setupSelf();
        super.build(force);
    }

    override
    bool coverOthers() { return true; }

    override
    bool mustPropagate() { return false; }
}