// pathfinder/renderer/src/z_buffer.rs
//
// Copyright © 2019 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

//! Software occlusion culling.

use crate::builder::Occluder;
use crate::gpu_data::{AlphaTileId, TileObjectPrimitive};
use crate::paint::PaintId;
use crate::tile_map::DenseTileMap;
use crate::tiles;
use pathfinder_geometry::rect::RectF;
use pathfinder_geometry::vector::Vector2I;
use vec_map::VecMap;

pub(crate) struct ZBuffer {
    buffer: DenseTileMap<u32>,
    depth_metadata: VecMap<DepthMetadata>,
}

#[derive(Clone, Copy)]
pub(crate) struct DepthMetadata {
    pub(crate) paint_id: PaintId,
}

impl ZBuffer {
    pub(crate) fn new(view_box: RectF) -> ZBuffer {
        let tile_rect = tiles::round_rect_out_to_tile_bounds(view_box);
        ZBuffer {
            buffer: DenseTileMap::from_builder(|_| 0, tile_rect),
            depth_metadata: VecMap::new(),
        }
    }

    pub(crate) fn test(&self, coords: Vector2I, depth: u32) -> bool {
        let tile_index = self.buffer.coords_to_index_unchecked(coords);
        self.buffer.data[tile_index as usize] < depth
    }

    pub(crate) fn update(&mut self,
                         solid_tiles: &[Occluder],
                         depth: u32,
                         metadata: DepthMetadata) {
        self.depth_metadata.insert(depth as usize, metadata);
        for solid_tile in solid_tiles {
            let tile_index = self.buffer.coords_to_index_unchecked(solid_tile.coords);
            let z_dest = &mut self.buffer.data[tile_index as usize];
            *z_dest = u32::max(*z_dest, depth);
        }
    }
}
