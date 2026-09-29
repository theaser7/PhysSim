"""
Headless Blender 5.2 Exporter for PhysSim
Exports 3D models, sub-meshes, materials, and hierarchy to standard GLTF/GLB.
Usage:
  blender --background input.blend --python scripts/blender_export.py -- output.glb
"""

import sys
import bpy

def export_blend_to_gltf(output_path: str):
    print(f"[Blender Exporter] Exporting scene to: {output_path}")
    
    # Deselect all, then select all mesh objects
    bpy.ops.object.select_all(action='DESELECT')
    mesh_count = 0
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.select_set(True)
            mesh_count += 1
            
    print(f"[Blender Exporter] Found {mesh_count} mesh objects")
    
    try:
        bpy.ops.export_scene.gltf(
            filepath=output_path,
            export_format='GLB',
            use_selection=False,
            export_apply=True,
            export_normals=True,
            export_materials='EXPORT',
            export_cameras=False,
            export_lights=False
        )
        print(f"[Blender Exporter] Successfully exported to {output_path}")
        return True
    except Exception as e:
        print(f"[Blender Exporter] Error exporting GLTF: {e}")
        return False

def main():
    argv = sys.argv
    if "--" not in argv:
        print("[Blender Exporter] Error: No output path specified. Use -- <output_path>")
        sys.exit(1)
        
    out_idx = argv.index("--") + 1
    if out_idx >= len(argv):
        print("[Blender Exporter] Error: Missing output path after '--'")
        sys.exit(1)
        
    output_path = argv[out_idx]
    success = export_blend_to_gltf(output_path)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
