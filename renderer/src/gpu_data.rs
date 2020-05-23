// pathfinder/renderer/src/gpu_data.rs
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

//! Packed data ready to be sent to the GPU.

use crate::builder::{ALPHA_TILES_PER_LEVEL, ALPHA_TILE_LEVEL_COUNT};
use crate::options::BoundingQuad;
use crate::paint::PaintCompositeOp;
use crate::tile_map::DenseTileMap;
use pathfinder_color::ColorU;
use pathfinder_content::effects::{BlendMode, Filter};
use pathfinder_content::render_target::RenderTargetId;
use pathfinder_geometry::line_segment::LineSegmentU16;
use pathfinder_geometry::rect::RectI;
use pathfinder_geometry::transform2d::Transform2F;
use pathfinder_geometry::vector::Vector2I;
use pathfinder_gpu::TextureSamplingFlags;
use std::fmt::{Debug, Formatter, Result as DebugResult};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;
use std::u32;

pub const TILE_CTRL_MASK_MASK:     i32 = 0x3;
pub const TILE_CTRL_MASK_WINDING:  i32 = 0x1;
pub const TILE_CTRL_MASK_EVEN_ODD: i32 = 0x2;

pub const TILE_CTRL_MASK_0_SHIFT:  i32 = 0;

pub enum RenderCommand {
    // Starts rendering a frame.
    Start {
        /// The number of paths that will be rendered.
        path_count: usize,

        /// A bounding quad for the scene.
        bounding_quad: BoundingQuad,

        /// Whether the framebuffer we're rendering to must be readable.
        ///
        /// This is needed if a path that renders directly to the output framebuffer (i.e. not to a
        /// render target) uses one of the more exotic blend modes.
        needs_readable_framebuffer: bool,
    },

    // Allocates a texture page.
    AllocateTexturePage { page_id: TexturePageId, descriptor: TexturePageDescriptor },

    // Uploads data to a texture page.
    UploadTexelData { texels: Arc<Vec<ColorU>>, location: TextureLocation },

    // Associates a render target with a texture page.
    //
    // TODO(pcwalton): Add a rect to this so we can render to subrects of a page.
    DeclareRenderTarget { id: RenderTargetId, location: TextureLocation },

    // Upload texture metadata.
    UploadTextureMetadata(Vec<TextureMetadataEntry>),

    // Adds fills to the queue.
    AddFills(Vec<Fill>),

    // Flushes the queue of fills.
    FlushFills,

    // Pushes a render target onto the stack. Draw commands go to the render target on top of the
    // stack.
    PushRenderTarget(RenderTargetId),

    // Pops a render target from the stack.
    PopRenderTarget,

    // Computes backdrops for tiles, prepares any Z-buffers, and performs clipping.
    PrepareTiles(PrepareTilesBatch),

    // Marks that tile compositing is about to begin.
    BeginTileDrawing,

    // Draws a batch of tiles to the render target on top of the stack.
    DrawTiles(DrawTileBatch),

    // Presents a rendered frame.
    Finish { cpu_build_time: Duration },
}

#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub struct TexturePageId(pub u32);

#[derive(Clone, Copy, Debug)]
pub struct TexturePageDescriptor {
    pub size: Vector2I,
}

#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub struct TextureLocation {
    pub page: TexturePageId,
    pub rect: RectI,
}

/// Information about a batch of tiles to be prepared (postprocessed).
#[derive(Clone, Debug)]
pub struct PrepareTilesBatch {
    /// The ID of this batch.
    /// 
    /// The renderer should not assume that these values are consecutive.
    pub batch_id: TileBatchId,

    /// The number of paths in this batch.
    pub path_count: u32,

    /// Information about all the allocated tiles.
    /// 
    /// If backdrops are being computed on CPU, then the backdrop values will already be summed.
    /// Otherwise, they will simply be raw delta values.
    pub tiles: Vec<TileObjectPrimitive>,

    /// Information about a batch of tiles specific to the rendering mode (CPU or GPU).
    pub modal: PrepareTilesModalInfo,

    /// Information about clips applied to paths, if any of the paths have clips.
    pub clipped_path_info: Option<ClippedPathInfo>,
}

/// Information about a batch of tiles to be prepared specific to the rendering mode (CPU or GPU).
#[derive(Clone, Debug)]
pub enum PrepareTilesModalInfo {
    CPU(PrepareTilesCPUInfo),
    GPU(PrepareTilesGPUInfo),
}

/// Information about a batch of tiles to be prepared on CPU.
#[derive(Clone, Debug)]
pub struct PrepareTilesCPUInfo {
    /// The Z-buffer used for occlusion culling.
    pub z_buffer: DenseTileMap<i32>,
}

/// Information about a batch of tiles to be prepared on GPU.
#[derive(Clone, Debug)]
pub struct PrepareTilesGPUInfo {
    /// Initial backdrop values for each tile column, packed together.
    pub backdrops: Vec<i32>,

    /// Mapping from path ID to metadata needed to compute propagation on GPU.
    /// 
    /// This contains indices into the `tiles` and `backdrops` vectors.
    pub propagate_metadata: Vec<PropagateMetadata>,
}

/// Information about clips applied to paths in a batch.
#[derive(Clone, Debug)]
pub struct ClippedPathInfo {
    /// The ID of the batch containing the clips.
    /// 
    /// In the current implementation, this is always 0.
    pub clip_batch_id: TileBatchId,

    /// The IDs of the paths that have clips.
    pub clipped_paths: Vec<PathIndex>,

    /// The maximum number of clipped tiles.
    /// 
    /// This is used to allocate vertex buffers.
    pub max_clipped_tile_count: u32,

    /// The actual clips, if calculated on CPU.
    pub clips: Option<Vec<Clip>>,
}

/// Together with the `TileBatchId`, uniquely identifies a path on the renderer side.
/// 
/// Generally, `PathIndex(!0)` represents no path.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct PathIndex(pub u32);

/// Unique ID that identifies a batch of tiles.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct TileBatchId(pub u32);

/// Information needed to draw a batch of tiles.
#[derive(Clone, Debug)]
pub struct DrawTileBatch {
    /// The ID of the tile batch. This must have been previously sent to the renderer in a
    /// `PrepareTiles` command.
    pub tile_batch_id: TileBatchId,

    /// The color texture to use.
    pub color_texture: Option<TileBatchTexture>,

    /// The filter to use.
    pub filter: Filter,

    /// The blend mode to composite these tiles with.
    pub blend_mode: BlendMode,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TileBatchTexture {
    pub page: TexturePageId,
    pub sampling_flags: TextureSamplingFlags,
    pub composite_op: PaintCompositeOp,
}

// TODO(pcwalton): Pack better.
#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct TileObjectPrimitive {
    pub tile_x: i16,
    pub tile_y: i16,
    pub alpha_tile_id: AlphaTileId,
    pub path_id: u32,
    // TODO(pcwalton): Maybe look the color up based on path ID?
    pub color: u16,
    pub backdrop: i8,
    pub ctrl: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(C)]
pub struct PropagateMetadata {
    pub tile_rect: RectI,
    pub tile_offset: u32,
    pub backdrops_offset: u32,
    pub z_write: u32,
    pub clip_path: PathIndex,
}

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct TextureMetadataEntry {
    pub color_0_transform: Transform2F,
    pub base_color: ColorU,
}

#[derive(Clone, Copy, Debug, Default)]
#[repr(C)]
pub struct Fill {
    pub line_segment: LineSegmentU16,
    // NB: This is overloaded to mean the next fill in the compute phase.
    pub alpha_tile_index: u32,
}

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct ClipMetadata {
    pub draw_tile_rect: RectI,
    pub clip_tile_rect: RectI,
    pub draw_tile_offset: u32,
    pub clip_tile_offset: u32,
    pub pad0: u32,
    pub pad1: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ClipBatchKey {
    pub dest_page: u16,
    pub src_page: u16,
    pub kind: ClipBatchKind,
}

// Order is significant here.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum ClipBatchKind {
    Draw,
    Clip,
}

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct Clip {
    pub dest_tile_id: AlphaTileId,
    pub dest_backdrop: i32,
    pub src_tile_id: AlphaTileId,
    pub src_backdrop: i32,
}

impl Default for Clip {
    #[inline]
    fn default() -> Clip {
        Clip {
            dest_tile_id: AlphaTileId(!0),
            dest_backdrop: 0,
            src_tile_id: AlphaTileId(!0),
            src_backdrop: 0,
        }
    }
}

/*
#[derive(Clone, Copy, Debug, Default)]
#[repr(C)]
pub struct Tile {
    pub tile_x: i16,
    pub tile_y: i16,
    pub mask_0_u: u8,
    pub mask_0_v: u8,
    pub mask_0_backdrop: i8,
    pub pad: u8,
    pub color: u16,
    pub ctrl: u16,
}
*/

#[derive(Clone, Copy, PartialEq, Debug)]
#[repr(C)]
pub struct AlphaTileId(pub u32);

impl AlphaTileId {
    #[inline]
    pub fn new(next_alpha_tile_index: &[AtomicUsize; ALPHA_TILE_LEVEL_COUNT], level: usize) 
               -> AlphaTileId {
        let alpha_tile_index = next_alpha_tile_index[level].fetch_add(1, Ordering::Relaxed);
        debug_assert!(alpha_tile_index < ALPHA_TILES_PER_LEVEL);
        AlphaTileId((level * ALPHA_TILES_PER_LEVEL + alpha_tile_index) as u32)
    }

    #[inline]
    pub fn invalid() -> AlphaTileId {
        AlphaTileId(!0)
    }

    #[inline]
    pub fn page(self) -> u16 {
        (self.0 >> 16) as u16
    }

    #[inline]
    pub fn tile(self) -> u16 {
        (self.0 & 0xffff) as u16
    }

    #[inline]
    pub fn is_valid(self) -> bool {
        self.0 < !0
    }
}

impl Debug for RenderCommand {
    fn fmt(&self, formatter: &mut Formatter) -> DebugResult {
        match *self {
            RenderCommand::Start { .. } => write!(formatter, "Start"),
            RenderCommand::AllocateTexturePage { page_id, descriptor: _ } => {
                write!(formatter, "AllocateTexturePage({})", page_id.0)
            }
            RenderCommand::UploadTexelData { ref texels, location } => {
                write!(formatter, "UploadTexelData(x{:?}, {:?})", texels.len(), location)
            }
            RenderCommand::DeclareRenderTarget { id, location } => {
                write!(formatter, "DeclareRenderTarget({:?}, {:?})", id, location)
            }
            RenderCommand::UploadTextureMetadata(ref metadata) => {
                write!(formatter, "UploadTextureMetadata(x{})", metadata.len())
            }
            RenderCommand::AddFills(ref fills) => {
                write!(formatter, "AddFills(x{})", fills.len())
            }
            RenderCommand::FlushFills => write!(formatter, "FlushFills"),
            RenderCommand::PrepareTiles(ref batch) => {
                let clipped_path_count = match batch.clipped_path_info {
                    None => 0,
                    Some(ref clipped_path_info) => clipped_path_info.clipped_paths.len(),
                };
                write!(formatter,
                       "PrepareTiles({:?}, T {}, C {})",
                       batch.batch_id,
                       batch.tiles.len(),
                       clipped_path_count)
            }
            RenderCommand::PushRenderTarget(render_target_id) => {
                write!(formatter, "PushRenderTarget({:?})", render_target_id)
            }
            RenderCommand::PopRenderTarget => write!(formatter, "PopRenderTarget"),
            RenderCommand::BeginTileDrawing => write!(formatter, "BeginTileDrawing"),
            RenderCommand::DrawTiles(ref batch) => {
                write!(formatter,
                       "DrawTiles({:?}, C0 {:?}, {:?})",
                       batch.tile_batch_id,
                       batch.color_texture,
                       batch.blend_mode)
            }
            RenderCommand::Finish { cpu_build_time } => {
                write!(formatter, "Finish({} ms)", cpu_build_time.as_secs_f64() * 1000.0)
            }
        }
    }
}
