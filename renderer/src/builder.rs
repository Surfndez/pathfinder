// pathfinder/renderer/src/builder.rs
//
// Copyright © 2019 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

//! Packs data onto the GPU.

use crate::concurrent::executor::Executor;
use crate::gpu::options::{RendererGPUFeatures, RendererOptions};
use crate::gpu::renderer::{BlendModeExt, MASK_TILES_ACROSS, MASK_TILES_DOWN};
use crate::gpu_data::{AlphaTileId, BinSegment, Clip, ClipBatchKey, ClipBatchKind, ClipMetadata, ClippedPathInfo, DrawTileBatch, Fill};
use crate::gpu_data::{PathIndex, PrepareTilesBatch, PrepareTilesCPUInfo, PrepareTilesGPUInfo, PrepareTilesModalInfo, PropagateMetadata, RenderCommand, SegmentIndices, Segments, TILE_CTRL_MASK_0_SHIFT};
use crate::gpu_data::{TILE_CTRL_MASK_EVEN_ODD, TILE_CTRL_MASK_WINDING, TileBatchId};
use crate::gpu_data::{TileBatchTexture, TileObjectPrimitive};
use crate::options::{PreparedBuildOptions, PreparedRenderTransform, RenderCommandListener};
use crate::paint::{PaintInfo, PaintMetadata};
use crate::scene::{DisplayItem, Scene};
use crate::tile_map::DenseTileMap;
use crate::tiler::Tiler;
use crate::tiles::{self, DrawTilingPathInfo, PackedTile, TILE_HEIGHT, TILE_WIDTH, TilingPathInfo};
use crate::z_buffer::{DepthMetadata, ZBuffer};
use fxhash::FxHashMap;
use instant::Instant;
use pathfinder_content::effects::{BlendMode, Filter};
use pathfinder_content::fill::FillRule;
use pathfinder_content::outline::{ContourIterFlags, Outline, PointFlags};
use pathfinder_content::render_target::RenderTargetId;
use pathfinder_content::segment::Segment;
use pathfinder_geometry::line_segment::{LineSegment2F, LineSegmentU16};
use pathfinder_geometry::rect::{RectF, RectI};
use pathfinder_geometry::transform2d::Transform2F;
use pathfinder_geometry::vector::{Vector2I, vec2i};
use pathfinder_gpu::TextureSamplingFlags;
use pathfinder_simd::default::{F32x4, I32x4};
use std::collections::VecDeque;
use std::sync::atomic::AtomicUsize;
use std::u32;

pub(crate) const ALPHA_TILE_LEVEL_COUNT: usize = 2;
pub(crate) const ALPHA_TILES_PER_LEVEL: usize = 1 << (32 - ALPHA_TILE_LEVEL_COUNT + 1);

const CURVE_IS_QUADRATIC: u32 = 0x80000000;
const CURVE_IS_CUBIC:     u32 = 0x40000000;

pub(crate) struct SceneBuilder<'a, 'b> {
    scene: &'a mut Scene,
    built_options: &'b PreparedBuildOptions,
    next_alpha_tile_indices: [AtomicUsize; ALPHA_TILE_LEVEL_COUNT],
    pub(crate) listener: RenderCommandListener<'a>,
}

#[derive(Debug)]
pub(crate) struct ObjectBuilder {
    pub built_path: BuiltPath,
    pub fills: Vec<Fill>,
    pub bounds: RectF,
}

#[derive(Debug)]
struct BuiltDrawPath {
    path: BuiltPath,
    clip_path_id: Option<PathIndex>,
    blend_mode: BlendMode,
    filter: Filter,
    color_texture: Option<TileBatchTexture>,
    sampling_flags_1: TextureSamplingFlags,
    mask_0_fill_rule: FillRule,
}

#[derive(Debug)]
pub(crate) struct BuiltPath {
    pub data: BuiltPathData,
    pub tiles: DenseTileMap<TileObjectPrimitive>,
    pub clip_tiles: Option<DenseTileMap<Clip>>,
    pub occluders: Option<Vec<Occluder>>,
    pub fill_rule: FillRule,
}

#[derive(Debug)]
pub(crate) enum BuiltPathData {
    Untiled(BuiltPathUntiledData),
    Tiled(BuiltPathTiledData),
}

#[derive(Debug)]
pub(crate) struct BuiltPathTiledData {
    /// During tiling, or if backdrop computation is done on GPU, this stores the sum of backdrops
    /// for tile columns above the viewport.
    pub backdrops: Vec<i32>,
}

#[derive(Debug)]
pub(crate) struct BuiltPathUntiledData {
    /// The transformed outline.
    pub outline: Outline,
}

#[derive(Clone, Copy, Debug)]
pub struct BuiltClip {
    pub clip: Clip,
    pub key: ClipBatchKey,
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct Occluder {
    pub(crate) coords: Vector2I,
}

impl<'a, 'b> SceneBuilder<'a, 'b> {
    pub(crate) fn new(scene: &'a mut Scene,
                      built_options: &'b PreparedBuildOptions,
                      listener: RenderCommandListener<'a>)
                      -> SceneBuilder<'a, 'b> {
        SceneBuilder {
            scene,
            built_options,
            next_alpha_tile_indices: [AtomicUsize::new(0), AtomicUsize::new(0)],
            listener,
        }
    }

    pub fn build<E>(&mut self, executor: &E) where E: Executor {
        let start_time = Instant::now();

        // Send the start rendering command.
        let bounding_quad = self.built_options.bounding_quad();

        let clip_path_count = self.scene.clip_paths.len();
        let draw_path_count = self.scene.paths.len();
        let total_path_count = clip_path_count + draw_path_count;

        let needs_readable_framebuffer = self.needs_readable_framebuffer();

        self.listener.send(RenderCommand::Start {
            bounding_quad,
            path_count: total_path_count,
            needs_readable_framebuffer,
        });

        let render_transform = match self.built_options.transform {
            PreparedRenderTransform::Transform2D(transform) => transform.inverse(),
            _ => Transform2F::default()
        };

        // Build paint data.
        let PaintInfo {
            render_commands,
            paint_metadata,
            render_target_metadata: _,
        } = self.scene.build_paint_info(render_transform);
        for render_command in render_commands {
            self.listener.send(render_command);
        }

        let effective_view_box = self.scene.effective_view_box(self.built_options);

        let built_clip_paths = executor.build_vector(clip_path_count, |path_index| {
            self.build_clip_path(PathBuildParams {
                path_index,
                view_box: effective_view_box,
                built_options: &self.built_options,
                scene: &self.scene,
            })
        });

        let built_draw_paths = executor.build_vector(draw_path_count, |path_index| {
            self.build_draw_path(DrawPathBuildParams {
                path_build_params: PathBuildParams {
                    path_index,
                    view_box: effective_view_box,
                    built_options: &self.built_options,
                    scene: &self.scene,
                },
                paint_metadata: &paint_metadata,
                built_clip_paths: &built_clip_paths,
            })
        });

        self.finish_building(&paint_metadata, built_draw_paths, built_clip_paths);

        let cpu_build_time = Instant::now() - start_time;
        self.listener.send(RenderCommand::Finish { cpu_build_time });
    }

    fn build_clip_path(&self, params: PathBuildParams) -> BuiltPath {
        let PathBuildParams { path_index, view_box, built_options, scene } = params;
        let path_object = &scene.clip_paths[path_index];
        let outline = scene.apply_render_options(path_object.outline(), built_options);

        let mut tiler = Tiler::new(self,
                                   path_index as u32,
                                   &outline,
                                   path_object.fill_rule(),
                                   view_box,
                                   TilingPathInfo::Clip);

        tiler.generate_tiles();
        self.send_fills(tiler.object_builder.fills);
        tiler.object_builder.built_path
    }

    fn build_draw_path(&self, params: DrawPathBuildParams) -> BuiltDrawPath {
        let DrawPathBuildParams {
            path_build_params: PathBuildParams { path_index, view_box, built_options, scene },
            paint_metadata,
            built_clip_paths,
        } = params;

        let path_object = &scene.paths[path_index];
        let outline = scene.apply_render_options(path_object.outline(), built_options);

        let paint_id = path_object.paint();
        let paint_metadata = &paint_metadata[paint_id.0 as usize];
        let built_clip_path = path_object.clip_path().map(|clip_path_id| {
            &built_clip_paths[clip_path_id.0 as usize]
        });

        let mut tiler = Tiler::new(self,
                                   path_index as u32,
                                   &outline,
                                   path_object.fill_rule(),
                                   view_box,
                                   TilingPathInfo::Draw(DrawTilingPathInfo {
            paint_id,
            paint_metadata,
            blend_mode: path_object.blend_mode(),
            built_clip_path,
            fill_rule: path_object.fill_rule(),
        }));

        tiler.generate_tiles();
        self.send_fills(tiler.object_builder.fills);

        BuiltDrawPath {
            path: tiler.object_builder.built_path,
            clip_path_id: path_object.clip_path().map(|clip_path_id| PathIndex(clip_path_id.0)),
            blend_mode: path_object.blend_mode(),
            filter: paint_metadata.filter(),
            color_texture: paint_metadata.tile_batch_texture(),
            sampling_flags_1: TextureSamplingFlags::empty(),
            mask_0_fill_rule: path_object.fill_rule(),
        }
    }

    fn send_fills(&self, fills: Vec<Fill>) {
        if !fills.is_empty() {
            self.listener.send(RenderCommand::AddFills(fills));
        }
    }

    fn build_tile_batches(&mut self,
                          paint_metadata: &[PaintMetadata],
                          built_draw_paths: Vec<BuiltDrawPath>,
                          built_clip_paths: Vec<BuiltPath>) {
        let gpu_features = self.listener.gpu_features;
        let (mut prepare_commands, mut draw_commands) = (vec![], vec![]);

        let scene_tile_rect = tiles::round_rect_out_to_tile_bounds(self.scene.view_box());
        let mut clip_prepare_batch = PrepareTilesBatch::new(TileBatchId(0),
                                                            scene_tile_rect,
                                                            gpu_features);

        let mut next_batch_id = TileBatchId(1);
        let mut clip_id_to_path_index = FxHashMap::default();

        // Prepare display items.
        for display_item in &self.scene.display_list {
            match *display_item {
                DisplayItem::PushRenderTarget(render_target_id) => {
                    draw_commands.push(RenderCommand::PushRenderTarget(render_target_id))
                }
                DisplayItem::PopRenderTarget => draw_commands.push(RenderCommand::PopRenderTarget),
                DisplayItem::DrawPaths {
                    start_index: start_draw_path_index,
                    end_index: end_draw_path_index,
                } => {
                    let start_time = ::std::time::Instant::now();

                    let mut batches = None;
                    for draw_path_index in start_draw_path_index..end_draw_path_index {
                        let draw_path = &built_draw_paths[draw_path_index as usize];

                        // Try to reuse the current batch if we can. Otherwise, flush it.
                        match batches {
                            Some(PathBatches {
                                draw: DrawTileBatch {
                                    color_texture: ref batch_color_texture,
                                    filter: ref batch_filter,
                                    blend_mode: ref batch_blend_mode,
                                    tile_batch_id: _
                                },
                                prepare: _,
                            }) if draw_path.color_texture == *batch_color_texture &&
                                draw_path.filter == *batch_filter &&
                                draw_path.blend_mode == *batch_blend_mode => {}
                            Some(PathBatches { draw, prepare }) => {
                                prepare_commands.push(RenderCommand::PrepareTiles(prepare));
                                draw_commands.push(RenderCommand::DrawTiles(draw));
                                batches = None;
                            }
                            None => {}
                        }

                        // Create a new batch if necessary.
                        if batches.is_none() {
                            batches = Some(PathBatches {
                                prepare: PrepareTilesBatch::new(next_batch_id,
                                                                scene_tile_rect,
                                                                gpu_features),
                                draw: DrawTileBatch {
                                    tile_batch_id: next_batch_id,
                                    color_texture: draw_path.color_texture,
                                    filter: draw_path.filter,
                                    blend_mode: draw_path.blend_mode,
                                },
                            });
                            next_batch_id.0 += 1;
                        }

                        // Add clip path if necessary.
                        let clip_path = draw_path.clip_path_id.map(|clip_path_id| {
                            match clip_id_to_path_index.get(&clip_path_id) {
                                Some(&clip_path_index) => clip_path_index,
                                None => {
                                    let clip_path_index = clip_path_id.0 as usize;
                                    let clip_path = &built_clip_paths[clip_path_index];
                                    let outline = self.scene.clip_paths[clip_path_index].outline();
                                    let clip_path_index = clip_prepare_batch.push(clip_path,
                                                                                  None,
                                                                                  outline,
                                                                                  gpu_features);
                                    clip_id_to_path_index.insert(clip_path_id, clip_path_index);
                                    clip_path_index
                                }
                            }
                        });

                        let batches = batches.as_mut().unwrap();
                        let outline = &self.scene.paths[draw_path_index as usize].outline();
                        batches.prepare.push(&draw_path.path, clip_path, outline, gpu_features);
                    }

                    let elapsed_time = ::std::time::Instant::now() - start_time;
                    println!("copying: {}ms", elapsed_time.as_secs_f32() * 1000.0);

                    if let Some(PathBatches { draw, prepare }) = batches {
                        prepare_commands.push(RenderCommand::PrepareTiles(prepare));
                        draw_commands.push(RenderCommand::DrawTiles(draw));
                    }
                }
            }
        }

        // Send commands.
        if !clip_prepare_batch.tiles.is_empty() {
            self.listener.send(RenderCommand::PrepareTiles(clip_prepare_batch));
        }
        for command in prepare_commands {
            self.listener.send(command);
        }
        for command in draw_commands {
            self.listener.send(command);
        }
    }

    fn finish_building(&mut self,
                       paint_metadata: &[PaintMetadata],
                       built_draw_paths: Vec<BuiltDrawPath>,
                       built_clip_paths: Vec<BuiltPath>) {
        if !self.listener.gpu_features.contains(RendererGPUFeatures::BIN_ON_GPU) {
            self.listener.send(RenderCommand::FlushFills);
        }

        self.build_tile_batches(paint_metadata, built_draw_paths, built_clip_paths);
    }

    fn needs_readable_framebuffer(&self) -> bool {
        let mut framebuffer_nesting = 0;
        for display_item in &self.scene.display_list {
            match *display_item {
                DisplayItem::PushRenderTarget(_) => framebuffer_nesting += 1,
                DisplayItem::PopRenderTarget => framebuffer_nesting -= 1,
                DisplayItem::DrawPaths { start_index, end_index } => {
                    if framebuffer_nesting > 0 {
                        continue;
                    }
                    for path_index in start_index..end_index {
                        let blend_mode = self.scene.paths[path_index as usize].blend_mode();
                        if blend_mode.needs_readable_framebuffer() {
                            return true;
                        }
                    }
                }
            }
        }
        false
    }
}

struct PathBuildParams<'a> {
    path_index: usize,
    view_box: RectF,
    built_options: &'a PreparedBuildOptions,
    scene: &'a Scene,
}

struct DrawPathBuildParams<'a> {
    path_build_params: PathBuildParams<'a>,
    paint_metadata: &'a [PaintMetadata],
    built_clip_paths: &'a [BuiltPath],
}

impl BuiltPath {
    // If `segments` is `None`, then tiling is being done on CPU. Otherwise, it's done on GPU.
    fn new(path_id: u32,
           path_bounds: RectF,
           view_box_bounds: RectF,
           fill_rule: FillRule,
           tiled_on_cpu: bool,
           tiling_path_info: &TilingPathInfo)
           -> BuiltPath {
        let occludes = match *tiling_path_info {
            TilingPathInfo::Draw(ref draw_tiling_path_info) => {
                draw_tiling_path_info.paint_metadata.is_opaque &&
                    draw_tiling_path_info.blend_mode.occludes_backdrop()
            }
            TilingPathInfo::Clip => true,
        };

        let color = match *tiling_path_info {
            TilingPathInfo::Draw(ref draw_tiling_path_info) => draw_tiling_path_info.paint_id.0,
            TilingPathInfo::Clip => 0,
        };

        let mut ctrl = 0;
        match *tiling_path_info {
            TilingPathInfo::Draw(ref draw_tiling_path_info) => {
                match draw_tiling_path_info.fill_rule {
                    FillRule::EvenOdd => ctrl |= TILE_CTRL_MASK_EVEN_ODD << TILE_CTRL_MASK_0_SHIFT,
                    FillRule::Winding => ctrl |= TILE_CTRL_MASK_WINDING << TILE_CTRL_MASK_0_SHIFT,
                }
            }
            TilingPathInfo::Clip => {}
        };

        let tile_map_bounds = if tiling_path_info.has_destructive_blend_mode() {
            view_box_bounds
        } else {
            path_bounds
        };

        let tiles = DenseTileMap::from_builder(|tile_coord| {
            TileObjectPrimitive {
                tile_x: tile_coord.x() as i16,
                tile_y: tile_coord.y() as i16,
                alpha_tile_id: AlphaTileId(!0),
                path_id,
                color,
                backdrop: 0,
                ctrl: ctrl as u8,
            }
        }, tiles::round_rect_out_to_tile_bounds(tile_map_bounds));

        let clip_tiles = match *tiling_path_info {
            TilingPathInfo::Draw(ref draw_tiling_path_info) if
                    draw_tiling_path_info.built_clip_path.is_some() => {
                Some(DenseTileMap::from_builder(|tile_coord| {
                    Clip {
                        dest_tile_id: AlphaTileId(!0),
                        dest_backdrop: 0,
                        src_tile_id: AlphaTileId(!0),
                        src_backdrop: 0,
                    }
                }, tiles::round_rect_out_to_tile_bounds(tile_map_bounds)))
            }
            _ => None,
        };

        let data = if tiled_on_cpu {
            BuiltPathData::Tiled(BuiltPathTiledData {
                backdrops: vec![0; tiles.rect.width() as usize],
            })
        } else {
            BuiltPathData::Untiled(BuiltPathUntiledData { outline: Outline::new() })
        };

        BuiltPath {
            data,
            tiles,
            clip_tiles,
            fill_rule,
            occluders: if occludes { Some(vec![]) } else { None },
        }
    }
}

impl Occluder {
    #[inline]
    pub(crate) fn new(coords: Vector2I) -> Occluder {
        Occluder { coords }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct TileStats {
    pub solid_tile_count: u32,
    pub alpha_tile_count: u32,
}

// Utilities for built objects

impl ObjectBuilder {
    // If `outline` is `None`, then tiling is being done on CPU. Otherwise, it's done on GPU.
    pub(crate) fn new(path_id: u32,
                      path_bounds: RectF,
                      view_box_bounds: RectF,
                      fill_rule: FillRule,
                      tiled_on_cpu: bool,
                      tiling_path_info: &TilingPathInfo)
                      -> ObjectBuilder {
        let built_path = BuiltPath::new(path_id,
                                        path_bounds,
                                        view_box_bounds,
                                        fill_rule,
                                        tiled_on_cpu,
                                        tiling_path_info);
        ObjectBuilder { built_path, bounds: path_bounds, fills: vec![] }
    }

    pub(crate) fn add_fill(&mut self,
                           scene_builder: &SceneBuilder,
                           segment: LineSegment2F,
                           tile_coords: Vector2I) {
        debug!("add_fill({:?} ({:?}))", segment, tile_coords);

        // Ensure this fill is in bounds. If not, cull it.
        if self.tile_coords_to_local_index(tile_coords).is_none() {
            return;
        }

        debug_assert_eq!(TILE_WIDTH, TILE_HEIGHT);

        // Compute the upper left corner of the tile.
        let tile_size = F32x4::splat(TILE_WIDTH as f32);
        let tile_upper_left = tile_coords.to_f32().0.to_f32x4().xyxy() * tile_size;

        // Convert to 8.8 fixed point.
        let segment = (segment.0 - tile_upper_left) * F32x4::splat(256.0);
        let (min, max) = (F32x4::default(), F32x4::splat((TILE_WIDTH * 256 - 1) as f32));
        let segment = segment.clamp(min, max).to_i32x4();
        let (from_x, from_y, to_x, to_y) = (segment[0], segment[1], segment[2], segment[3]);

        // Cull degenerate fills.
        if from_x == to_x {
            debug!("... culling!");
            return;
        }

        // Allocate a global tile if necessary.
        let alpha_tile_id = self.get_or_allocate_alpha_tile_index(scene_builder, tile_coords);

        // Pack instance data.
        debug!("... OK, pushing");
        self.fills.push(Fill {
            line_segment: LineSegmentU16 {
                from_x: from_x as u16,
                from_y: from_y as u16,
                to_x: to_x as u16,
                to_y: to_y as u16,
            }, 
            alpha_tile_index: alpha_tile_id.0,
        });
    }

    fn get_or_allocate_alpha_tile_index(&mut self,
                                        scene_builder: &SceneBuilder,
                                        tile_coords: Vector2I)
                                        -> AlphaTileId {
        let local_tile_index = self.built_path.tiles.coords_to_index_unchecked(tile_coords);
        let alpha_tile_id = self.built_path.tiles.data[local_tile_index].alpha_tile_id;
        if alpha_tile_id.is_valid() {
            return alpha_tile_id;
        }

        let alpha_tile_id = AlphaTileId::new(&scene_builder.next_alpha_tile_indices, 0);
        self.built_path.tiles.data[local_tile_index].alpha_tile_id = alpha_tile_id;
        alpha_tile_id
    }

    #[inline]
    pub(crate) fn tile_coords_to_local_index(&self, coords: Vector2I) -> Option<u32> {
        self.built_path.tiles.coords_to_index(coords).map(|index| index as u32)
    }

    #[inline]
    pub(crate) fn local_tile_index_to_coords(&self, tile_index: u32) -> Vector2I {
        self.built_path.tiles.index_to_coords(tile_index as usize)
    }

    #[inline]
    pub(crate) fn adjust_alpha_tile_backdrop(&mut self, tile_coords: Vector2I, delta: i8) {
        let backdrops = match self.built_path.data {
            BuiltPathData::Tiled(ref mut tiled_data) => &mut tiled_data.backdrops,
            BuiltPathData::Untiled(_) => unreachable!(),
        };

        let tile_offset = tile_coords - self.built_path.tiles.rect.origin();
        if tile_offset.x() < 0 || tile_offset.x() >= self.built_path.tiles.rect.width() ||
                tile_offset.y() >= self.built_path.tiles.rect.height() {
            return;
        }

        if tile_offset.y() < 0 {
            backdrops[tile_offset.x() as usize] += delta as i32;
            return;
        }

        let local_tile_index = self.built_path.tiles.coords_to_index_unchecked(tile_coords);
        self.built_path.tiles.data[local_tile_index].backdrop += delta;
    }
}

/*
impl<'a> PackedTile<'a> {
    pub(crate) fn add_to(&self,
                         tiles: &mut Vec<BuiltTile>,
                         clips: &mut Vec<BuiltClip>,
                         draw_tiling_path_info: &DrawTilingPathInfo,
                         scene_builder: &SceneBuilder) {
        let draw_tile_page = self.draw_tile.alpha_tile_id.page() as u16;
        let draw_tile_index = self.draw_tile.alpha_tile_id.tile() as u16;
        let draw_tile_backdrop = self.draw_tile.backdrop as i8;

        match self.clip_tile {
            None => {
                /*
                tiles.push(BuiltTile {
                    page: draw_tile_page,
                    tile: Tile::new_alpha(self.tile_coords,
                                          draw_tile_index,
                                          draw_tile_backdrop,
                                          draw_tiling_path_info),
                });
                */
            }
            Some(clip_tile) => {
                let clip_tile_page = clip_tile.alpha_tile_id.page() as u16;
                let clip_tile_index = clip_tile.alpha_tile_id.tile() as u16;
                let clip_tile_backdrop = clip_tile.backdrop;

                let dest_tile_id = AlphaTileId::new(&scene_builder.next_alpha_tile_indices, 1);
                let dest_tile_page = dest_tile_id.page() as u16;
                let dest_tile_index = dest_tile_id.tile() as u16;

                clips.push(BuiltClip {
                    clip: Clip::new(dest_tile_index, draw_tile_index, draw_tile_backdrop),
                    key: ClipBatchKey {
                        src_page: draw_tile_page,
                        dest_page: dest_tile_page,
                        kind: ClipBatchKind::Draw,
                    },
                });
                clips.push(BuiltClip {
                    clip: Clip::new(dest_tile_index, clip_tile_index, clip_tile_backdrop),
                    key: ClipBatchKey {
                        src_page: clip_tile_page,
                        dest_page: dest_tile_page,
                        kind: ClipBatchKind::Clip,
                    },
                });
                /*
                tiles.push(BuiltTile {
                    page: dest_tile_page,
                    tile: Tile::new_alpha(self.tile_coords,
                                          dest_tile_index,
                                          0,
                                          draw_tiling_path_info),
                });
                */
            }
        }
    }
}
*/

/*
impl Tile {
    #[inline]
    fn new_alpha(tile_origin: Vector2I,
                 draw_tile_index: u16,
                 draw_tile_backdrop: i8,
                 draw_tiling_path_info: &DrawTilingPathInfo)
                 -> Tile {
        let mask_0_uv = calculate_mask_uv(draw_tile_index);

        let mut ctrl = 0;
        match draw_tiling_path_info.fill_rule {
            FillRule::EvenOdd => ctrl |= TILE_CTRL_MASK_EVEN_ODD << TILE_CTRL_MASK_0_SHIFT,
            FillRule::Winding => ctrl |= TILE_CTRL_MASK_WINDING << TILE_CTRL_MASK_0_SHIFT,
        }

        Tile {
            tile_x: tile_origin.x() as i16,
            tile_y: tile_origin.y() as i16,
            mask_0_u: mask_0_uv.x() as u8,
            mask_0_v: mask_0_uv.y() as u8,
            mask_0_backdrop: draw_tile_backdrop,
            ctrl: ctrl as u16,
            pad: 0,
            color: draw_tiling_path_info.paint_id.0,
        }
    }

    #[inline]
    pub fn tile_position(&self) -> Vector2I {
        vec2i(self.tile_x as i32, self.tile_y as i32)
    }
}
*/

fn calculate_mask_uv(tile_index: u16) -> Vector2I {
    debug_assert_eq!(MASK_TILES_ACROSS, MASK_TILES_DOWN);
    let mask_u = tile_index as i32 % MASK_TILES_ACROSS as i32;
    let mask_v = tile_index as i32 / MASK_TILES_ACROSS as i32;
    vec2i(mask_u, mask_v)
}

struct PathBatches {
    prepare: PrepareTilesBatch,
    draw: DrawTileBatch,
}

impl PrepareTilesBatch {
    fn new(batch_id: TileBatchId, tile_rect: RectI, gpu_features: RendererGPUFeatures)
           -> PrepareTilesBatch {
        PrepareTilesBatch {
            batch_id,
            path_count: 0,
            tiles: vec![],
            modal: if gpu_features.contains(RendererGPUFeatures::PREPARE_TILES_ON_GPU) {
                PrepareTilesModalInfo::GPU(PrepareTilesGPUInfo {
                    backdrops: vec![],
                    propagate_metadata: vec![],
                    segments: if gpu_features.contains(RendererGPUFeatures::BIN_ON_GPU) {
                        Some(Segments { points: vec![], indices: vec![] })
                    } else {
                        None
                    },
                })
            } else {
                PrepareTilesModalInfo::CPU(PrepareTilesCPUInfo {
                    z_buffer: DenseTileMap::from_builder(|_| 0, tile_rect),
                })
            },
            clipped_path_info: None,
        }
    }

    fn push(&mut self,
            path: &BuiltPath,
            clip_path_id: Option<PathIndex>,
            path_outline: &Outline,
            gpu_features: RendererGPUFeatures)
            -> PathIndex {
        let z_write = path.occluders.is_some();
        let path_index = PathIndex(self.path_count);

        match self.modal {
            PrepareTilesModalInfo::CPU(ref mut cpu_info) if z_write => {
                for tile in &path.tiles.data {
                    if tile.backdrop == 0 || tile.alpha_tile_id != AlphaTileId(!0) {
                        continue;
                    }
                    let tile_coords = vec2i(tile.tile_x as i32, tile.tile_y as i32);
                    let z_value = cpu_info.z_buffer
                                          .get_mut(tile_coords)
                                          .expect("Z value out of bounds!");
                    *z_value = (*z_value).max(path_index.0 as i32);
                }
            }
            PrepareTilesModalInfo::CPU(_) => {}
            PrepareTilesModalInfo::GPU(ref mut gpu_info) => {
                let path_index = PathIndex(gpu_info.propagate_metadata.len() as u32);
                gpu_info.propagate_metadata.push(PropagateMetadata {
                    tile_rect: path.tiles.rect,
                    tile_offset: self.tiles.len() as u32,
                    backdrops_offset: gpu_info.backdrops.len() as u32,
                    z_write: z_write as u32,
                    clip_path: clip_path_id.unwrap_or(PathIndex(!0)),
                });

                match path.data {
                    BuiltPathData::Tiled(ref tiled_data) => {
                        gpu_info.backdrops.extend_from_slice(&tiled_data.backdrops);
                    }
                    BuiltPathData::Untiled(ref untiled_data) => {
                        gpu_info.add_segments(path, path_index, &untiled_data.outline);
                    }
                }
            }
        }

        self.tiles.extend_from_slice(&path.tiles.data);

        if clip_path_id.is_some() {
            if self.clipped_path_info.is_none() {
                self.clipped_path_info = Some(ClippedPathInfo {
                    clip_batch_id: TileBatchId(0),
                    clipped_paths: vec![],
                    max_clipped_tile_count: 0,
                    clips: if !gpu_features.contains(RendererGPUFeatures::PREPARE_TILES_ON_GPU) {
                        Some(vec![])
                    } else {
                        None
                    },
                });
            }

            let clipped_path_info = self.clipped_path_info.as_mut().unwrap();
            clipped_path_info.clipped_paths.push(path_index);
            clipped_path_info.max_clipped_tile_count += path.tiles.data.len() as u32;

            // If clips are computed on CPU, add them to this batch.
            if let Some(ref mut dest_clips) = clipped_path_info.clips {
                let src_tiles = path.clip_tiles
                                    .as_ref()
                                    .expect("Clip tiles weren't computed on CPU!");
                dest_clips.extend_from_slice(&src_tiles.data);
            }
        }

        path_index
    }
}

impl PrepareTilesGPUInfo {
    fn add_segments(&mut self, path: &BuiltPath, path_index: PathIndex, outline: &Outline) {
        for _ in 0..path.tiles.rect.width() {
            self.backdrops.push(0);
        }

        let bin_segments = self.segments.as_mut().unwrap();
        for contour in outline.contours() {
            let point_count = contour.len() as u32;
            bin_segments.points.reserve(point_count as usize);

            for point_index in 0..point_count {
                if !contour.flags_of(point_index).intersects(PointFlags::CONTROL_POINT_0 |
                                                             PointFlags::CONTROL_POINT_1) {
                    let mut flags = 0;
                    if point_index + 1 < point_count &&
                            contour.flags_of(point_index + 1)
                                   .contains(PointFlags::CONTROL_POINT_0) {
                        if point_index + 2 < point_count &&
                                contour.flags_of(point_index + 2)
                                       .contains(PointFlags::CONTROL_POINT_1) {
                            flags = CURVE_IS_CUBIC
                        } else {
                            flags = CURVE_IS_QUADRATIC
                        }
                    }

                    if point_index + 1 < point_count || contour.is_closed() {
                        bin_segments.indices.push(SegmentIndices {
                            first_point_index: bin_segments.points.len() as u32,
                            flags_path_index: path_index.0 | flags,
                        });
                    }
                }

                bin_segments.points.push(contour.position_of(point_index));
            }

            if contour.is_closed() {
                bin_segments.points.push(contour.position_of(0));
            }
        }
    }
}
