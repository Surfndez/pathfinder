// pathfinder/renderer/src/gpu/renderer.rs
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

use crate::gpu::debug::DebugUIPresenter;
use crate::gpu::options::{DestFramebuffer, RendererGPUFeatures, RendererOptions};
use crate::gpu::shaders::{BinComputeProgram, BlitBufferProgram, BlitBufferVertexArray};
use crate::gpu::shaders::{BlitProgram, BlitVertexArray, ClearProgram, ClearVertexArray};
use crate::gpu::shaders::{ClipTileCombineProgram, ClipTileCombineVertexArray, ClipTileCopyProgram};
use crate::gpu::shaders::{ClipTileCopyVertexArray, CopyTileProgram, CopyTileVertexArray};
use crate::gpu::shaders::{DiceComputeProgram, FillProgram, FillVertexArray, InitProgram};
use crate::gpu::shaders::{MAX_FILLS_PER_BATCH, PROPAGATE_WORKGROUP_SIZE, ReprojectionProgram};
use crate::gpu::shaders::{ReprojectionVertexArray, StencilProgram, StencilVertexArray, TileFillProgram};
use crate::gpu::shaders::{TilePostPrograms, TileProgram, TileVertexArray};
use crate::gpu_data::{BackdropInfo, Clip, DiceMetadata, Fill, PrepareTilesBatch};
use crate::gpu_data::{PrepareTilesGPUModalInfo, PrepareTilesModalInfo, PropagateMetadata};
use crate::gpu_data::{RenderCommand, Segments, TextureLocation, TextureMetadataEntry};
use crate::gpu_data::{TexturePageDescriptor, TexturePageId, TileBatchTexture};
use crate::gpu_data::{TileObjectPrimitive, TilePathInfo};
use crate::options::BoundingQuad;
use crate::paint::PaintCompositeOp;
use crate::tile_map::DenseTileMap;
use crate::tiles::{TILE_HEIGHT, TILE_WIDTH};
use half::f16;
use pathfinder_color::{self as color, ColorF, ColorU};
use pathfinder_content::effects::{BlendMode, BlurDirection, DefringingKernel};
use pathfinder_content::effects::{Filter, PatternFilter};
use pathfinder_content::render_target::RenderTargetId;
use pathfinder_geometry::line_segment::LineSegment2F;
use pathfinder_geometry::rect::{RectF, RectI};
use pathfinder_geometry::transform2d::Transform2F;
use pathfinder_geometry::transform3d::Transform4F;
use pathfinder_geometry::util;
use pathfinder_geometry::vector::{Vector2F, Vector2I, Vector4F, vec2f, vec2i};
use pathfinder_gpu::{BlendFactor, BlendState, BufferData, BufferTarget, BufferUploadMode};
use pathfinder_gpu::{ClearOps, ComputeDimensions, ComputeState, DepthFunc, DepthState, Device};
use pathfinder_gpu::{FeatureLevel, ImageAccess, Primitive, RenderOptions, RenderState};
use pathfinder_gpu::{RenderTarget, StencilFunc, StencilState, TextureBinding, TextureDataRef};
use pathfinder_gpu::{TextureFormat, TextureSamplingFlags, UniformBinding, UniformData};
use pathfinder_resources::ResourceLoader;
use pathfinder_simd::default::{F32x2, F32x4, I32x2};
use std::collections::VecDeque;
use std::f32;
use std::marker::PhantomData;
use std::mem;
use std::ops::{Add, Div};
use std::slice;
use std::time::Duration;
use std::u32;
use vec_map::VecMap;

static QUAD_VERTEX_POSITIONS: [u16; 8] = [0, 0, 1, 0, 1, 1, 0, 1];
static QUAD_VERTEX_INDICES: [u32; 6] = [0, 1, 3, 1, 2, 3];

pub(crate) const MASK_TILES_ACROSS: u32 = 256;
pub(crate) const MASK_TILES_DOWN: u32 = 256;

// 1.0 / sqrt(2*pi)
const SQRT_2_PI_INV: f32 = 0.3989422804014327;

const TEXTURE_CACHE_SIZE: usize = 8;

const MIN_PATH_INFO_STORAGE_CLASS:               usize = 10;    // 1024 entries
const MIN_DICE_METADATA_STORAGE_CLASS:           usize = 10;    // 1024 entries
const MIN_FILL_STORAGE_CLASS:                    usize = 14;    // 16K entries, 128kB
const MIN_TILE_LINK_MAP_STORAGE_CLASS:           usize = 15;    // 32K entries, 128kB
const MIN_TILE_STORAGE_CLASS:                    usize = 10;    // 1024 entries, 12kB
const MIN_TILE_PROPAGATE_METADATA_STORAGE_CLASS: usize = 8;     // 256 entries
const MIN_CLIP_VERTEX_STORAGE_CLASS:             usize = 10;    // 1024 entries, 16kB

const TEXTURE_METADATA_ENTRIES_PER_ROW: i32 = 128;
const TEXTURE_METADATA_TEXTURE_WIDTH:   i32 = TEXTURE_METADATA_ENTRIES_PER_ROW * 4;
const TEXTURE_METADATA_TEXTURE_HEIGHT:  i32 = 65536 / TEXTURE_METADATA_ENTRIES_PER_ROW;

// FIXME(pcwalton): Shrink this again!
const MASK_FRAMEBUFFER_WIDTH:  i32 = TILE_WIDTH as i32      * MASK_TILES_ACROSS as i32;
const MASK_FRAMEBUFFER_HEIGHT: i32 = TILE_HEIGHT as i32 / 4 * MASK_TILES_DOWN as i32;

const COMBINER_CTRL_COLOR_COMBINE_SRC_IN: i32 =     0x1;
const COMBINER_CTRL_COLOR_COMBINE_DEST_IN: i32 =    0x2;

const COMBINER_CTRL_FILTER_RADIAL_GRADIENT: i32 =   0x1;
const COMBINER_CTRL_FILTER_TEXT: i32 =              0x2;
const COMBINER_CTRL_FILTER_BLUR: i32 =              0x3;

const COMBINER_CTRL_COMPOSITE_NORMAL: i32 =         0x0;
const COMBINER_CTRL_COMPOSITE_MULTIPLY: i32 =       0x1;
const COMBINER_CTRL_COMPOSITE_SCREEN: i32 =         0x2;
const COMBINER_CTRL_COMPOSITE_OVERLAY: i32 =        0x3;
const COMBINER_CTRL_COMPOSITE_DARKEN: i32 =         0x4;
const COMBINER_CTRL_COMPOSITE_LIGHTEN: i32 =        0x5;
const COMBINER_CTRL_COMPOSITE_COLOR_DODGE: i32 =    0x6;
const COMBINER_CTRL_COMPOSITE_COLOR_BURN: i32 =     0x7;
const COMBINER_CTRL_COMPOSITE_HARD_LIGHT: i32 =     0x8;
const COMBINER_CTRL_COMPOSITE_SOFT_LIGHT: i32 =     0x9;
const COMBINER_CTRL_COMPOSITE_DIFFERENCE: i32 =     0xa;
const COMBINER_CTRL_COMPOSITE_EXCLUSION: i32 =      0xb;
const COMBINER_CTRL_COMPOSITE_HUE: i32 =            0xc;
const COMBINER_CTRL_COMPOSITE_SATURATION: i32 =     0xd;
const COMBINER_CTRL_COMPOSITE_COLOR: i32 =          0xe;
const COMBINER_CTRL_COMPOSITE_LUMINOSITY: i32 =     0xf;

const COMBINER_CTRL_COLOR_FILTER_SHIFT: i32 =       4;
const COMBINER_CTRL_COLOR_COMBINE_SHIFT: i32 =      6;
const COMBINER_CTRL_COMPOSITE_SHIFT: i32 =          8;

pub struct Renderer<D> where D: Device {
    // Device
    pub device: D,

    // Core data
    dest_framebuffer: DestFramebuffer<D>,
    options: RendererOptions,
    blit_program: BlitProgram<D>,
    clear_program: ClearProgram<D>,
    fill_program: FillProgram<D>,
    tile_program: TileProgram<D>,
    tile_copy_program: CopyTileProgram<D>,
    tile_clip_combine_program: ClipTileCombineProgram<D>,
    tile_clip_copy_program: ClipTileCopyProgram<D>,
    tile_fill_program: TileFillProgram<D>,
    tile_post_programs: Option<TilePostPrograms<D>>,
    stencil_program: StencilProgram<D>,
    reprojection_program: ReprojectionProgram<D>,
    bin_compute_program: BinComputeProgram<D>,
    dice_compute_program: DiceComputeProgram<D>,
    init_program: InitProgram<D>,
    quad_vertex_positions_buffer: D::Buffer,
    quad_vertex_indices_buffer: D::Buffer,
    tile_link_map: Vec<TileLinks>,
    texture_pages: Vec<Option<TexturePage<D>>>,
    render_targets: Vec<RenderTargetInfo>,
    render_target_stack: Vec<RenderTargetId>,
    area_lut_texture: D::Texture,
    gamma_lut_texture: D::Texture,

    // Scene
    points_buffer: D::Buffer,
    point_indices_buffer: D::Buffer,
    point_index_count: u32,

    // Frames
    front_frame: Frame<D>,
    back_frame: Frame<D>,
    front_frame_fence: Option<D::Fence>,

    // Rendering state
    texture_cache: TextureCache<D>,

    // Debug
    pub stats: RenderStats,
    current_cpu_build_time: Option<Duration>,
    current_timer: Option<PendingTimer<D>>,
    pending_timers: VecDeque<PendingTimer<D>>,
    timer_query_cache: TimerQueryCache<D>,
    pub debug_ui_presenter: DebugUIPresenter<D>,

    // Extra info
    flags: RendererFlags,
}

struct Frame<D> where D: Device {
    framebuffer_flags: FramebufferFlags,
    blit_vertex_array: BlitVertexArray<D>,
    blit_buffer_vertex_array: BlitBufferVertexArray<D>,
    clear_vertex_array: ClearVertexArray<D>,
    path_info_storage_allocator: BufferStorageAllocator<D, TilePathInfo>,
    dice_metadata_storage_allocator: StorageAllocator<D, DiceMetadataStorage<D>>,
    fill_vertex_storage_allocator: StorageAllocator<D, FillVertexStorage<D>>,
    tile_link_map_storage_allocator: BufferStorageAllocator<D, TileLinks>,
    tile_vertex_storage_allocator: StorageAllocator<D, TileVertexStorage<D>>,
    tile_propagate_metadata_storage_allocator: BufferStorageAllocator<D, PropagateMetadata>,
    clip_vertex_storage_allocator: StorageAllocator<D, ClipVertexStorage<D>>,

    // Maps tile batch IDs to tile vertex storage IDs.
    tile_batch_info: VecMap<TileBatchInfo>,

    quads_vertex_indices_buffer: D::Buffer,
    quads_vertex_indices_length: usize,
    buffered_fills: Vec<Fill>,
    pending_fills: Vec<Fill>,
    max_alpha_tile_index: u32,
    allocated_alpha_tile_page_count: u32,
    mask_framebuffer: Option<D::Framebuffer>,
    stencil_vertex_array: StencilVertexArray<D>,
    reprojection_vertex_array: ReprojectionVertexArray<D>,
    dest_blend_framebuffer: D::Framebuffer,
    intermediate_dest_framebuffer: D::Framebuffer,
    texture_metadata_texture: D::Texture,
    backdrops_buffer: D::Buffer,
    z_buffer: D::Buffer,
    z_buffer_framebuffer: D::Framebuffer,
    initial_tile_map_buffer: D::Buffer,
}

impl<D> Renderer<D> where D: Device {
    pub fn new(device: D,
               resources: &dyn ResourceLoader,
               dest_framebuffer: DestFramebuffer<D>,
               options: RendererOptions)
               -> Renderer<D> {
        let blit_program = BlitProgram::new(&device, resources);
        let blit_buffer_program = BlitBufferProgram::new(&device, resources);
        let clear_program = ClearProgram::new(&device, resources);
        let fill_program = FillProgram::new(&device, resources, &options);
        let tile_program = TileProgram::new(&device, resources);
        let tile_copy_program = CopyTileProgram::new(&device, resources);
        let tile_clip_combine_program = ClipTileCombineProgram::new(&device, resources);
        let tile_clip_copy_program = ClipTileCopyProgram::new(&device, resources);
        let tile_fill_program = TileFillProgram::new(&device, resources);
        let stencil_program = StencilProgram::new(&device, resources);
        let reprojection_program = ReprojectionProgram::new(&device, resources);

        let postprocess_tiles_on_gpu =
            options.gpu_features.contains(RendererGPUFeatures::PREPARE_TILES_ON_GPU);
        let tile_post_programs = match (postprocess_tiles_on_gpu, device.feature_level()) {
            (true, FeatureLevel::D3D11) => Some(TilePostPrograms::new(&device, resources)),
            _ => None,
        };
        let bin_compute_program = BinComputeProgram::new(&device, resources);
        let dice_compute_program = DiceComputeProgram::new(&device, resources);
        let init_program = InitProgram::new(&device, resources);

        let area_lut_texture =
            device.create_texture_from_png(resources, "area-lut", TextureFormat::RGBA8);
        let gamma_lut_texture =
            device.create_texture_from_png(resources, "gamma-lut", TextureFormat::R8);

        let quad_vertex_positions_buffer = device.create_buffer(BufferUploadMode::Static);
        device.allocate_buffer(&quad_vertex_positions_buffer,
                               BufferData::Memory(&QUAD_VERTEX_POSITIONS),
                               BufferTarget::Vertex);
        let quad_vertex_indices_buffer = device.create_buffer(BufferUploadMode::Static);
        device.allocate_buffer(&quad_vertex_indices_buffer,
                               BufferData::Memory(&QUAD_VERTEX_INDICES),
                               BufferTarget::Index);

        let points_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        let point_indices_buffer = device.create_buffer(BufferUploadMode::Dynamic);

        let window_size = dest_framebuffer.window_size(&device);

        let timer_query_cache = TimerQueryCache::new(&device);
        let debug_ui_presenter = DebugUIPresenter::new(&device, resources, window_size);

        let front_frame = Frame::new(&device,
                                     &blit_program,
                                     &blit_buffer_program,
                                     &clear_program,
                                     &reprojection_program,
                                     &stencil_program,
                                     &quad_vertex_positions_buffer,
                                     &quad_vertex_indices_buffer,
                                     window_size);
        let back_frame = Frame::new(&device,
                                    &blit_program,
                                    &blit_buffer_program,
                                    &clear_program,
                                    &reprojection_program,
                                    &stencil_program,
                                    &quad_vertex_positions_buffer,
                                    &quad_vertex_indices_buffer,
                                    window_size);

        Renderer {
            device,

            dest_framebuffer,
            options,
            blit_program,
            clear_program,
            fill_program,
            tile_program,
            tile_copy_program,
            tile_clip_combine_program,
            tile_clip_copy_program,
            tile_fill_program,
            tile_post_programs,
            bin_compute_program,
            dice_compute_program,
            init_program,
            quad_vertex_positions_buffer,
            quad_vertex_indices_buffer,
            tile_link_map: vec![],
            texture_pages: vec![],
            render_targets: vec![],
            render_target_stack: vec![],

            points_buffer,
            point_indices_buffer,
            point_index_count: 0,

            front_frame,
            back_frame,
            front_frame_fence: None,

            area_lut_texture,
            gamma_lut_texture,

            stencil_program,

            reprojection_program,

            stats: RenderStats::default(),
            current_cpu_build_time: None,
            current_timer: None,
            pending_timers: VecDeque::new(),
            timer_query_cache,
            debug_ui_presenter,

            texture_cache: TextureCache::new(),

            flags: RendererFlags::empty(),
        }
    }

    #[inline]
    pub fn gpu_features(&self) -> RendererGPUFeatures {
        self.options.gpu_features
    }

    pub fn begin_scene(&mut self) {
        self.back_frame.framebuffer_flags = FramebufferFlags::empty();

        self.device.begin_commands();
        self.current_timer = Some(PendingTimer::new());
        self.stats = RenderStats::default();

        let framebuffer_tile_size = self.framebuffer_tile_size();
        let z_buffer_length = framebuffer_tile_size.x() as usize *
            framebuffer_tile_size.y() as usize;
        self.device.upload_to_buffer::<i32>(&self.back_frame.z_buffer,
                                            0,
                                            &vec![0; z_buffer_length],
                                            BufferTarget::Storage);

        self.back_frame.max_alpha_tile_index = 0;
    }

    pub fn render_command(&mut self, command: &RenderCommand) {
        debug!("render command: {:?}", command);
        match *command {
            RenderCommand::Start { bounding_quad, path_count, needs_readable_framebuffer } => {
                self.start_rendering(bounding_quad, path_count, needs_readable_framebuffer);
            }
            RenderCommand::AllocateTexturePage { page_id, ref descriptor } => {
                self.allocate_texture_page(page_id, descriptor)
            }
            RenderCommand::UploadTexelData { ref texels, location } => {
                self.upload_texel_data(texels, location)
            }
            RenderCommand::DeclareRenderTarget { id, location } => {
                self.declare_render_target(id, location)
            }
            RenderCommand::UploadTextureMetadata(ref metadata) => {
                self.upload_texture_metadata(metadata)
            }
            RenderCommand::AddFills(ref fills) => self.add_fills(fills),
            RenderCommand::FlushFills => {
                self.draw_buffered_fills();
            }
            RenderCommand::UploadScene(ref segments) => self.upload_scene(segments),
            RenderCommand::BeginTileDrawing => {}
            RenderCommand::PushRenderTarget(render_target_id) => {
                self.push_render_target(render_target_id)
            }
            RenderCommand::PopRenderTarget => self.pop_render_target(),
            RenderCommand::PrepareTiles(ref batch) => self.prepare_tiles(batch),
            RenderCommand::DrawTiles(ref batch) => {
                /*
                let batch_info = self.back_frame.tile_batch_info[batch.tile_batch_id.0 as usize];
                self.draw_tiles(batch_info.tile_count,
                                batch_info.tile_vertex_storage_id,
                                batch.color_texture,
                                batch.blend_mode,
                                batch.filter)
                                */
            }
            RenderCommand::Finish { cpu_build_time } => {
                self.stats.cpu_build_time = cpu_build_time;
            }
        }
    }

    pub fn end_scene(&mut self) {
        self.clear_dest_framebuffer_if_necessary();
        self.blit_intermediate_dest_framebuffer_if_necessary();

        let old_front_frame_fence = self.front_frame_fence.take();
        self.front_frame_fence = Some(self.device.add_fence());
        self.device.end_commands();

        self.back_frame.path_info_storage_allocator.end_frame();
        self.back_frame.dice_metadata_storage_allocator.end_frame();
        self.back_frame.fill_vertex_storage_allocator.end_frame();
        self.back_frame.tile_link_map_storage_allocator.end_frame();
        self.back_frame.tile_vertex_storage_allocator.end_frame();
        self.back_frame.tile_propagate_metadata_storage_allocator.end_frame();
        self.back_frame.clip_vertex_storage_allocator.end_frame();

        self.back_frame.tile_batch_info.clear();

        if let Some(timer) = self.current_timer.take() {
            self.pending_timers.push_back(timer);
        }
        self.current_cpu_build_time = None;

        if let Some(old_front_frame_fence) = old_front_frame_fence {
            self.device.wait_for_fence(&old_front_frame_fence);
        }

        mem::swap(&mut self.front_frame, &mut self.back_frame);
    }

    fn start_rendering(&mut self,
                       bounding_quad: BoundingQuad,
                       path_count: usize,
                       mut needs_readable_framebuffer: bool) {
        if let DestFramebuffer::Other(_) = self.dest_framebuffer {
            needs_readable_framebuffer = false;
        }

        // FIXME(pcwalton): Bogus!
        needs_readable_framebuffer = true;

        if self.flags.contains(RendererFlags::USE_DEPTH) {
            self.draw_stencil(&bounding_quad);
        }
        self.stats.path_count = path_count;

        self.flags.set(RendererFlags::INTERMEDIATE_DEST_FRAMEBUFFER_NEEDED,
                       needs_readable_framebuffer);

        self.render_targets.clear();
    }

    pub fn draw_debug_ui(&self) {
        self.debug_ui_presenter.draw(&self.device);
    }

    pub fn shift_rendering_time(&mut self) -> Option<RenderTime> {
        if let Some(mut pending_timer) = self.pending_timers.pop_front() {
            for old_query in pending_timer.poll(&self.device) {
                self.timer_query_cache.free(old_query);
            }
            if let Some(render_time) = pending_timer.total_time() {
                return Some(render_time);
            }
            self.pending_timers.push_front(pending_timer);
        }
        None
    }

    #[inline]
    pub fn dest_framebuffer(&self) -> &DestFramebuffer<D> {
        &self.dest_framebuffer
    }

    #[inline]
    pub fn replace_dest_framebuffer(
        &mut self,
        new_dest_framebuffer: DestFramebuffer<D>,
    ) -> DestFramebuffer<D> {
        mem::replace(&mut self.dest_framebuffer, new_dest_framebuffer)
    }

    #[inline]
    pub fn set_options(&mut self, new_options: RendererOptions) {
        self.options = new_options
    }

    #[inline]
    pub fn set_main_framebuffer_size(&mut self, new_framebuffer_size: Vector2I) {
        self.debug_ui_presenter.ui_presenter.set_framebuffer_size(new_framebuffer_size);
    }

    #[inline]
    pub fn disable_depth(&mut self) {
        self.flags.remove(RendererFlags::USE_DEPTH);
    }

    #[inline]
    pub fn enable_depth(&mut self) {
        self.flags.insert(RendererFlags::USE_DEPTH);
    }

    #[inline]
    pub fn quad_vertex_positions_buffer(&self) -> &D::Buffer {
        &self.quad_vertex_positions_buffer
    }

    #[inline]
    pub fn quad_vertex_indices_buffer(&self) -> &D::Buffer {
        &self.quad_vertex_indices_buffer
    }

    fn reallocate_alpha_tile_pages_if_necessary(&mut self, copy_existing: bool) {
        // FIXME(pcwalton): Do this properly!
        /*let alpha_tile_pages_needed =
            ((self.back_frame.max_alpha_tile_index + 0xffff) >> 16) as u32;*/
        let alpha_tile_pages_needed = 3;
        if alpha_tile_pages_needed <= self.back_frame.allocated_alpha_tile_page_count {
            return;
        }

        let new_size = vec2i(MASK_FRAMEBUFFER_WIDTH,
                             MASK_FRAMEBUFFER_HEIGHT * alpha_tile_pages_needed as i32);
        let mask_texture = self.device.create_texture(TextureFormat::RGBA16F, new_size);
        let old_mask_framebuffer =
            mem::replace(&mut self.back_frame.mask_framebuffer,
                         Some(self.device.create_framebuffer(mask_texture)));
        self.back_frame.allocated_alpha_tile_page_count = alpha_tile_pages_needed;

        // Copy over existing content if needed.
        let old_mask_framebuffer = match old_mask_framebuffer {
            Some(old_mask_framebuffer) if copy_existing => old_mask_framebuffer,
            Some(_) | None => return,
        };
        let old_mask_texture = self.device.framebuffer_texture(&old_mask_framebuffer);
        let old_size = self.device.texture_size(old_mask_texture);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        self.device.draw_elements(6, &RenderState {
            target: &RenderTarget::Framebuffer(self.back_frame.mask_framebuffer.as_ref().unwrap()),
            program: &self.blit_program.program,
            vertex_array: &self.back_frame.blit_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[(&self.blit_program.src_texture, old_mask_texture)],
            images: &[],
            storage_buffers: &[],
            uniforms: &[
                (&self.blit_program.framebuffer_size_uniform,
                 UniformData::Vec2(new_size.to_f32().0)),
                (&self.blit_program.dest_rect_uniform,
                 UniformData::Vec4(RectF::new(Vector2F::zero(), old_size.to_f32()).0)),
            ],
            viewport: RectI::new(Vector2I::default(), new_size),
            options: RenderOptions {
                clear_ops: ClearOps {
                    color: Some(ColorF::new(0.0, 0.0, 0.0, 1.0)),
                    ..ClearOps::default()
                },
                ..RenderOptions::default()
            },
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().fill_times.push(TimerFuture::new(timer_query));
    }

    fn allocate_texture_page(&mut self,
                             page_id: TexturePageId,
                             descriptor: &TexturePageDescriptor) {
        // Fill in IDs up to the requested page ID.
        let page_index = page_id.0 as usize;
        while self.texture_pages.len() < page_index + 1 {
            self.texture_pages.push(None);
        }

        // Clear out any existing texture.
        if let Some(old_texture_page) = self.texture_pages[page_index].take() {
            let old_texture = self.device.destroy_framebuffer(old_texture_page.framebuffer);
            self.texture_cache.release_texture(old_texture);
        }

        // Allocate texture.
        let texture_size = descriptor.size;
        let texture = self.texture_cache.create_texture(&mut self.device,
                                                        TextureFormat::RGBA8,
                                                        texture_size);
        let framebuffer = self.device.create_framebuffer(texture);
        self.texture_pages[page_index] = Some(TexturePage {
            framebuffer,
            must_preserve_contents: false,
        });
    }

    fn upload_texel_data(&mut self, texels: &[ColorU], location: TextureLocation) {
        let texture_page = self.texture_pages[location.page.0 as usize]
                               .as_mut()
                               .expect("Texture page not allocated yet!");
        let texture = self.device.framebuffer_texture(&texture_page.framebuffer);
        let texels = color::color_slice_to_u8_slice(texels);
        self.device.upload_to_texture(texture, location.rect, TextureDataRef::U8(texels));
        texture_page.must_preserve_contents = true;
    }

    fn declare_render_target(&mut self,
                             render_target_id: RenderTargetId,
                             location: TextureLocation) {
        while self.render_targets.len() < render_target_id.render_target as usize + 1 {
            self.render_targets.push(RenderTargetInfo {
                location: TextureLocation { page: TexturePageId(!0), rect: RectI::default() },
            });
        }
        let mut render_target = &mut self.render_targets[render_target_id.render_target as usize];
        debug_assert_eq!(render_target.location.page, TexturePageId(!0));
        render_target.location = location;
    }

    fn upload_texture_metadata(&mut self, metadata: &[TextureMetadataEntry]) {
        let padded_texel_size =
            (util::alignup_i32(metadata.len() as i32, TEXTURE_METADATA_ENTRIES_PER_ROW) *
             TEXTURE_METADATA_TEXTURE_WIDTH * 4) as usize;
        let mut texels = Vec::with_capacity(padded_texel_size);
        for entry in metadata {
            let base_color = entry.base_color.to_f32();
            texels.extend_from_slice(&[
                f16::from_f32(entry.color_0_transform.m11()),
                f16::from_f32(entry.color_0_transform.m21()),
                f16::from_f32(entry.color_0_transform.m12()),
                f16::from_f32(entry.color_0_transform.m22()),
                f16::from_f32(entry.color_0_transform.m13()),
                f16::from_f32(entry.color_0_transform.m23()),
                f16::default(),
                f16::default(),
                f16::from_f32(base_color.r()),
                f16::from_f32(base_color.g()),
                f16::from_f32(base_color.b()),
                f16::from_f32(base_color.a()),
                f16::default(),
                f16::default(),
                f16::default(),
                f16::default(),
            ]);
        }
        while texels.len() < padded_texel_size {
            texels.push(f16::default())
        }

        let texture = &mut self.back_frame.texture_metadata_texture;
        let width = TEXTURE_METADATA_TEXTURE_WIDTH;
        let height = texels.len() as i32 / (4 * TEXTURE_METADATA_TEXTURE_WIDTH);
        let rect = RectI::new(Vector2I::zero(), Vector2I::new(width, height));
        self.device.upload_to_texture(texture, rect, TextureDataRef::F16(&texels));
    }

    fn upload_scene(&mut self, segments: &Segments) {
        self.device.allocate_buffer(&self.points_buffer,
                                    BufferData::Memory(&segments.points),
                                    BufferTarget::Storage);
        self.device.allocate_buffer(&self.point_indices_buffer,
                                    BufferData::Memory(&segments.indices),
                                    BufferTarget::Storage);
        self.point_index_count = segments.indices.len() as u32;
    }

    fn allocate_tiles(&mut self, tile_count: u32) -> StorageID {
        let tile_program = &self.tile_program;
        let tile_copy_program = &self.tile_copy_program;
        let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
        let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
        self.back_frame.tile_vertex_storage_allocator.allocate(&self.device,
                                                               tile_count as u64,
                                                               |device, size| {
            TileVertexStorage::new(size,
                                   device,
                                   tile_program,
                                   tile_copy_program,
                                   quad_vertex_positions_buffer,
                                   quad_vertex_indices_buffer)
        })
    }

    fn upload_tiles(&mut self, storage_id: StorageID, tiles: &[TileObjectPrimitive]) {
        let vertex_buffer = &self.back_frame
                                 .tile_vertex_storage_allocator
                                 .get(storage_id)
                                 .vertex_buffer;
        self.device.upload_to_buffer(vertex_buffer, 0, tiles, BufferTarget::Vertex);

        self.ensure_index_buffer(tiles.len());
    }

    fn allocate_tile_link_map(&mut self, tile_count: u32) -> StorageID {
        self.back_frame.tile_link_map_storage_allocator.allocate(&self.device,
                                                                 tile_count as u64,
                                                                 BufferTarget::Storage)
    }

    fn initialize_tiles(&mut self,
                        tile_storage_id: StorageID,
                        tile_link_map_storage_id: StorageID,
                        tile_count: u32,
                        tile_path_info: &[TilePathInfo]) {
        let path_info_storage_id =
            self.back_frame.path_info_storage_allocator.allocate(&self.device,
                                                                 tile_path_info.len() as u64,
                                                                 BufferTarget::Storage);
        let tile_path_info_buffer = self.back_frame
                                        .path_info_storage_allocator
                                        .get(path_info_storage_id);
        self.device.upload_to_buffer(tile_path_info_buffer,
                                     0,
                                     tile_path_info,
                                     BufferTarget::Storage);

        // TODO(pcwalton): Buffer reuse!
        let framebuffer_tile_size = self.framebuffer_tile_size();
        let framebuffer_tile_count = framebuffer_tile_size.x() * framebuffer_tile_size.y();
        let mut initial_tile_map_data: Vec<u32> = vec![!0; framebuffer_tile_count as usize];
        self.device.upload_to_buffer(&self.back_frame.initial_tile_map_buffer,
                                     0,
                                     &initial_tile_map_data,
                                     BufferTarget::Storage);

        let tiles_buffer = &self.back_frame
                                .tile_vertex_storage_allocator
                                .get(tile_storage_id)
                                .vertex_buffer;

        // Fetch tile link map.
        let tile_link_map_buffer = &self.back_frame
                                        .tile_link_map_storage_allocator
                                        .get(tile_link_map_storage_id);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let compute_dimensions = ComputeDimensions { x: (tile_count + 63) / 64, y: 1, z: 1 };
        self.device.dispatch_compute(compute_dimensions, &ComputeState {
            program: &self.init_program.program,
            textures: &[],
            uniforms: &[
                (&self.init_program.path_count_uniform,
                 UniformData::Int(tile_path_info.len() as i32)),
                (&self.init_program.tile_count_uniform, UniformData::Int(tile_count as i32)),
                (&self.init_program.framebuffer_tile_size_uniform,
                 UniformData::IVec2(self.framebuffer_tile_size().0)),
            ],
            images: &[],
            storage_buffers: &[
                (&self.init_program.tiles_storage_buffer, tiles_buffer),
                (&self.init_program.tile_path_info_storage_buffer, &tile_path_info_buffer),
                (&self.init_program.tile_link_map_storage_buffer, &tile_link_map_buffer),
                (&self.init_program.initial_tile_map_storage_buffer,
                 &self.back_frame.initial_tile_map_buffer),
            ],
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().bin_times.push(TimerFuture::new(timer_query));

        self.device.end_commands();
        self.device.begin_commands();
    }

    fn upload_propagate_data(&mut self,
                             propagate_metadata: &[PropagateMetadata],
                             backdrops: &[BackdropInfo])
                             -> StorageID {
        let device = &self.device;
        let propagate_metadata_storage_id = self.back_frame
                                                .tile_propagate_metadata_storage_allocator
                                                .allocate(device,
                                                          propagate_metadata.len() as u64,
                                                          BufferTarget::Storage);
        let propagate_metadata_buffer = self.back_frame
                                            .tile_propagate_metadata_storage_allocator
                                            .get(propagate_metadata_storage_id);
        device.upload_to_buffer(propagate_metadata_buffer,
                                0,
                                propagate_metadata,
                                BufferTarget::Storage);

        self.device.allocate_buffer(&self.back_frame.backdrops_buffer,
                                    BufferData::Memory(backdrops),
                                    BufferTarget::Storage);

        propagate_metadata_storage_id
    }

    fn ensure_index_buffer(&mut self, mut length: usize) {
        length = length.next_power_of_two();
        if self.back_frame.quads_vertex_indices_length >= length {
            return;
        }

        // TODO(pcwalton): Generate these with SIMD.
        let mut indices: Vec<u32> = Vec::with_capacity(length * 6);
        for index in 0..(length as u32) {
            indices.extend_from_slice(&[
                index * 4 + 0, index * 4 + 1, index * 4 + 2,
                index * 4 + 1, index * 4 + 3, index * 4 + 2,
            ]);
        }

        self.device.allocate_buffer(&self.back_frame.quads_vertex_indices_buffer,
                                    BufferData::Memory(&indices),
                                    BufferTarget::Index);

        self.back_frame.quads_vertex_indices_length = length;
    }

    fn dice_segments(&mut self,
                     dice_metadata: &[DiceMetadata],
                     batch_segment_count: u32,
                     transform: Transform2F)
                     -> (D::Buffer, u32) {
        // FIXME(pcwalton): Buffer reuse
        let output_segments_buffer = self.device.create_buffer(BufferUploadMode::Dynamic);

        let dice_metadata_storage_id =
            self.back_frame.dice_metadata_storage_allocator.allocate(&self.device,
                                                                     dice_metadata.len() as u64,
                                                                     DiceMetadataStorage::new);
        let dice_metadata_storage = self.back_frame
                                        .dice_metadata_storage_allocator
                                        .get(dice_metadata_storage_id);

        let index_count = self.point_index_count;
        self.device.upload_to_buffer(&dice_metadata_storage.indirect_draw_params_buffer,
                                     0,
                                     &[0, 0, 0, 0, index_count, 0, 0, 0],
                                     BufferTarget::Storage);
        // FIXME(pcwalton): Better memory management!!
        self.device.allocate_buffer::<[u32; 8]>(&output_segments_buffer,
                                                BufferData::Uninitialized(3 * 1024 * 1024),
                                                BufferTarget::Storage);
        self.device.upload_to_buffer(&dice_metadata_storage.metadata_buffer,
                                     0,
                                     dice_metadata,
                                     BufferTarget::Storage);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let compute_dimensions = ComputeDimensions {
            x: (batch_segment_count + 63) / 64,
            y: 1,
            z: 1,
        };

        self.device.dispatch_compute(compute_dimensions, &ComputeState {
            program: &self.dice_compute_program.program,
            textures: &[],
            uniforms: &[
                (&self.dice_compute_program.transform_uniform,
                 UniformData::Mat2(transform.matrix.0)),
                (&self.dice_compute_program.translation_uniform,
                 UniformData::Vec2(transform.vector.0)),
                 // FIXME(pcwalton): This is wrong!
                (&self.dice_compute_program.path_count_uniform,
                 UniformData::Int(dice_metadata.len() as i32)),
                (&self.dice_compute_program.last_batch_segment_index_uniform,
                 UniformData::Int(batch_segment_count as i32)),
            ],
            images: &[],
            storage_buffers: &[
                (&self.dice_compute_program.compute_indirect_params_storage_buffer,
                 &dice_metadata_storage.indirect_draw_params_buffer),
                (&self.dice_compute_program.points_storage_buffer, &self.points_buffer),
                (&self.dice_compute_program.input_indices_storage_buffer,
                 &self.point_indices_buffer),
                (&self.dice_compute_program.output_segments_storage_buffer,
                 &output_segments_buffer),
                (&self.dice_compute_program.dice_metadata_storage_buffer,
                 &dice_metadata_storage.metadata_buffer),
            ],
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().bin_times.push(TimerFuture::new(timer_query));

        self.device.end_commands();
        self.device.begin_commands();

        let indirect_compute_params =
            self.device.read_buffer(&dice_metadata_storage.indirect_draw_params_buffer,
                                    BufferTarget::Storage,
                                    0..8);
        (output_segments_buffer, indirect_compute_params[5])
    }

    fn bin_segments_via_compute(&mut self,
                                segments_buffer: D::Buffer,
                                segment_count: u32,
                                propagate_metadata_storage_id: StorageID,
                                tile_storage_id: StorageID,
                                tile_link_map_storage_id: StorageID,
                                tile_count: u32)
                                -> FillStorageInfo {
        // FIXME(pcwalton): Don't hardcode 3M fills!!
        let fill_storage_id = {
            let fill_program = &self.fill_program;
            let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
            let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
            let gpu_features = self.gpu_features();
            self.back_frame
                .fill_vertex_storage_allocator
                .allocate(&self.device, 3 * 1024 * 1024, |device, size| {
                FillVertexStorage::new(size,
                                       device,
                                       fill_program,
                                       quad_vertex_positions_buffer,
                                       quad_vertex_indices_buffer,
                                       gpu_features)
            })
        };
        let fill_vertex_storage =
            self.back_frame.fill_vertex_storage_allocator.get(fill_storage_id);

        let alpha_tile_buffer = &self.back_frame
                                     .tile_vertex_storage_allocator
                                     .get(tile_storage_id)
                                     .vertex_buffer;
        let propagate_metadata_storage_buffer = self.back_frame
                                                    .tile_propagate_metadata_storage_allocator
                                                    .get(propagate_metadata_storage_id);

        // FIXME(pcwalton): Buffer reuse
        let indirect_draw_params_buffer =
            fill_vertex_storage.indirect_draw_params_buffer
                               .as_ref()
                               .expect("Where's the indirect draw params buffer?");
        self.device.upload_to_buffer::<u32>(&indirect_draw_params_buffer,
                                            0,
                                            &[6, 0, 0, 0, 0, segment_count, 0, 0],
                                            BufferTarget::Storage);

        let mut storage_buffers = vec![
            (&self.bin_compute_program.metadata_storage_buffer, propagate_metadata_storage_buffer),
            (&self.bin_compute_program.fills_storage_buffer, &fill_vertex_storage.vertex_buffer),
            (&self.bin_compute_program.indirect_draw_params_storage_buffer,
             indirect_draw_params_buffer),
            (&self.bin_compute_program.tiles_storage_buffer, alpha_tile_buffer),
            (&self.bin_compute_program.segments_storage_buffer, &segments_buffer),
            (&self.bin_compute_program.backdrops_storage_buffer,
             &self.back_frame.backdrops_buffer),
        ];

        let tile_link_map_storage_id = if self.gpu_features()
                                              .contains(RendererGPUFeatures::FILL_IN_COMPUTE) {
            let tile_link_map_buffer =
                self.back_frame.tile_link_map_storage_allocator.get(tile_link_map_storage_id);

            storage_buffers.push((&self.bin_compute_program.tile_link_map_storage_buffer,
                                  &tile_link_map_buffer));
            Some(tile_link_map_storage_id)
        } else {
            // Need to initialize the buffer with some random old buffer we have lying around on
            // Metal.
            storage_buffers.push((&self.bin_compute_program.tile_link_map_storage_buffer,
                                  &self.back_frame.z_buffer));
            None
        };

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let compute_dimensions = ComputeDimensions {
            x: (segment_count as u32 + 63) / 64,
            y: 1,
            z: 1,
        };

        self.device.dispatch_compute(compute_dimensions, &ComputeState {
            program: &self.bin_compute_program.program,
            textures: &[],
            uniforms: &[
                (&self.bin_compute_program.fill_in_compute_enabled_uniform,
                 UniformData::Int(tile_link_map_storage_id.is_some() as i32)),
            ],
            images: &[],
            storage_buffers: &storage_buffers,
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().bin_times.push(TimerFuture::new(timer_query));

        self.device.end_commands();
        self.device.begin_commands();

        let indirect_draw_params = self.device.read_buffer(indirect_draw_params_buffer,
                                                           BufferTarget::Storage,
                                                           0..8);

        if self.gpu_features().contains(RendererGPUFeatures::FILL_IN_COMPUTE) {
            FillStorageInfo::Compute(FillComputeStorageInfo {
                fill_storage_id,
                tile_link_map_storage_id: tile_link_map_storage_id.unwrap(),
                // FIXME(pcwalton): Don't process all tiles!
                first_fill_tile: 0,
                fill_tile_count: tile_count,
            })
        } else {
            let fill_count = indirect_draw_params[1];
            FillStorageInfo::Raster(FillRasterStorageInfo { fill_storage_id, fill_count })
        }
    }

    fn add_fills(&mut self, fill_batch: &[Fill]) {
        if fill_batch.is_empty() {
            return;
        }

        self.stats.fill_count += fill_batch.len();

        let preserve_alpha_mask_contents = self.back_frame.max_alpha_tile_index > 0;

        self.back_frame.pending_fills.reserve(fill_batch.len());
        for fill in fill_batch {
            self.back_frame.max_alpha_tile_index =
                self.back_frame.max_alpha_tile_index.max(fill.link + 1);
            self.back_frame.pending_fills.push(*fill);
        }

        self.reallocate_alpha_tile_pages_if_necessary(preserve_alpha_mask_contents);

        if self.back_frame.buffered_fills.len() + self.back_frame.pending_fills.len() >
                MAX_FILLS_PER_BATCH {
            self.draw_buffered_fills();
        }

        self.back_frame.buffered_fills.extend(self.back_frame.pending_fills.drain(..));
    }

    fn draw_buffered_fills(&mut self) {
        if self.back_frame.buffered_fills.is_empty() {
            return;
        }

        match self.fill_program {
            FillProgram::Raster(_) => {
                let fill_storage_info = self.upload_buffered_fills_for_raster();
                self.draw_fills_via_raster(fill_storage_info.fill_storage_id,
                                           None,
                                           PrimitiveCount::Direct(fill_storage_info.fill_count));
            }
            FillProgram::Compute(_) => {
                let fill_storage_info = self.upload_buffered_fills_for_compute();
                self.draw_fills_via_compute(fill_storage_info, None);
            }
        }
    }

    fn upload_buffered_fills_for_raster(&mut self) -> FillRasterStorageInfo {
        let gpu_features = self.gpu_features();
        let buffered_fills = &mut self.back_frame.buffered_fills;
        debug_assert!(!buffered_fills.is_empty());

        let storage_id = {
            let fill_program = &self.fill_program;
            let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
            let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
            self.back_frame
                .fill_vertex_storage_allocator
                .allocate(&self.device, MAX_FILLS_PER_BATCH as u64, |device, size| {
                FillVertexStorage::new(size,
                                       device,
                                       fill_program,
                                       quad_vertex_positions_buffer,
                                       quad_vertex_indices_buffer,
                                       gpu_features)
            })
        };
        let fill_vertex_storage = self.back_frame.fill_vertex_storage_allocator.get(storage_id);

        debug_assert!(buffered_fills.len() <= u32::MAX as usize);
        self.device.upload_to_buffer(&fill_vertex_storage.vertex_buffer,
                                     0,
                                     &buffered_fills,
                                     BufferTarget::Vertex);

        let fill_count = buffered_fills.len() as u32;
        buffered_fills.clear();

        FillRasterStorageInfo { fill_storage_id: storage_id, fill_count }
    }

    fn upload_buffered_fills_for_compute(&mut self) -> FillComputeStorageInfo {
        let gpu_features = self.gpu_features();
        let buffered_fills = &mut self.back_frame.buffered_fills;
        debug_assert!(!buffered_fills.is_empty());

        // Allocate buffered fill buffer.
        let fill_storage_id = {
            let fill_program = &self.fill_program;
            let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
            let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
            self.back_frame.fill_vertex_storage_allocator.allocate(&self.device,
                                                                   MAX_FILLS_PER_BATCH as u64,
                                                                   |device, size| {
                FillVertexStorage::new(size,
                                       device,
                                       fill_program,
                                       quad_vertex_positions_buffer,
                                       quad_vertex_indices_buffer,
                                       gpu_features)
            })
        };

        // Initialize the tile link map.
        self.tile_link_map.clear();

        // Create a linked list running through all our fills. This is where we convert the `link`
        // field from referring to the alpha tile index to referring to the next fill in the list.
        let (mut first_fill_tile, mut last_fill_tile) = (u32::MAX, 0);
        for (fill_index, fill) in buffered_fills.iter_mut().enumerate() {
            let tile_link_index = fill.link as usize;
            while tile_link_index >= self.tile_link_map.len() {
                self.tile_link_map.push(TileLinks { next_alpha_tile: !0, next_fill: !0 });
            }
            fill.link = self.tile_link_map[tile_link_index].next_fill as u32;
            self.tile_link_map[tile_link_index].next_fill = fill_index as u32;
            first_fill_tile = first_fill_tile.min(tile_link_index as u32);
            last_fill_tile = last_fill_tile.max(tile_link_index as u32);
        }
        let fill_tile_count = last_fill_tile - first_fill_tile + 1;

        // Allocate tile link map.
        let tile_link_map_storage_id = self.back_frame
                                           .tile_link_map_storage_allocator
                                           .allocate(&self.device,
                                                     last_fill_tile as u64,
                                                     BufferTarget::Storage);

        buffered_fills.clear();

        FillComputeStorageInfo {
            fill_storage_id,
            tile_link_map_storage_id,
            first_fill_tile,
            fill_tile_count,
        }
    }

    fn draw_fills_via_raster(&mut self,
                             fill_storage_id: StorageID,
                             tile_storage_id: Option<StorageID>,
                             fill_count: PrimitiveCount) {
        let fill_raster_program = match self.fill_program {
            FillProgram::Raster(ref fill_raster_program) => fill_raster_program,
            _ => unreachable!(),
        };
        let mask_viewport = self.mask_viewport();
        let fill_vertex_storage = self.back_frame   
                                      .fill_vertex_storage_allocator
                                      .get(fill_storage_id);
        let fill_vertex_array =
            fill_vertex_storage.vertex_array.as_ref().expect("Where's the vertex array?");

        let mut clear_color = None;
        if !self.back_frame
                .framebuffer_flags
                .contains(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY) {
            clear_color = Some(ColorF::default());
        };

        let mut storage_buffers = vec![];
        if let Some(tile_storage_id) = tile_storage_id {
            let alpha_tile_buffer = &self.back_frame
                                        .tile_vertex_storage_allocator
                                        .get(tile_storage_id)
                                        .vertex_buffer;
            storage_buffers.push((fill_raster_program.tiles_storage_buffer
                                                     .as_ref()
                                                     .expect("Where's the tile storage buffer?"),
                                  alpha_tile_buffer));
        }

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let render_state = RenderState {
            target: &RenderTarget::Framebuffer(self.back_frame
                                                   .mask_framebuffer
                                                   .as_ref()
                                                   .expect("Where's the mask framebuffer?")),
            program: &fill_raster_program.program,
            vertex_array: &fill_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[(&fill_raster_program.area_lut_texture, &self.area_lut_texture)],
            uniforms: &[
                (&fill_raster_program.framebuffer_size_uniform,
                 UniformData::Vec2(mask_viewport.size().to_f32().0)),
                (&fill_raster_program.tile_size_uniform,
                 UniformData::Vec2(F32x2::new(TILE_WIDTH as f32, TILE_HEIGHT as f32))),
            ],
            images: &[],
            storage_buffers: &storage_buffers,
            viewport: mask_viewport,
            options: RenderOptions {
                blend: Some(BlendState {
                    src_rgb_factor: BlendFactor::One,
                    src_alpha_factor: BlendFactor::One,
                    dest_rgb_factor: BlendFactor::One,
                    dest_alpha_factor: BlendFactor::One,
                    ..BlendState::default()
                }),
                clear_ops: ClearOps { color: clear_color, ..ClearOps::default() },
                ..RenderOptions::default()
            },
        };

        match fill_count {
            PrimitiveCount::Direct(fill_count) => {
                self.device.draw_elements_instanced(6, fill_count, &render_state)
            }
            PrimitiveCount::Indirect => {
                let indirect_buffer =
                    fill_vertex_storage.indirect_draw_params_buffer
                                       .as_ref()
                                       .expect("Where's the fill vertex storage buffer?");
                self.device.draw_elements_indirect(indirect_buffer, &render_state)
            }
        }

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().fill_times.push(TimerFuture::new(timer_query));

        self.back_frame.framebuffer_flags.insert(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY);
    }

    fn draw_fills_via_compute(&mut self,
                              fill_storage_info: FillComputeStorageInfo,
                              tile_storage_id: Option<StorageID>) {
        let FillComputeStorageInfo {
            fill_storage_id,
            tile_link_map_storage_id,
            first_fill_tile,
            fill_tile_count,
        } = fill_storage_info;

        let fill_compute_program = match self.fill_program {
            FillProgram::Compute(ref fill_compute_program) => fill_compute_program,
            _ => unreachable!(),
        };

        let fill_vertex_storage = self.back_frame   
                                      .fill_vertex_storage_allocator
                                      .get(fill_storage_id);

        let tile_link_map_buffer =
            self.back_frame.tile_link_map_storage_allocator.get(tile_link_map_storage_id);

        let mask_framebuffer = self.back_frame
                                   .mask_framebuffer
                                   .as_ref()
                                   .expect("Where's the mask framebuffer?");
        let image_texture = self.device.framebuffer_texture(mask_framebuffer);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let mut storage_buffers = vec![
            (&fill_compute_program.fills_storage_buffer, &fill_vertex_storage.vertex_buffer),
            (&fill_compute_program.tile_link_map_storage_buffer, tile_link_map_buffer),
        ];

        match tile_storage_id {
            Some(tile_storage_id) => {
                let tiles_buffer = &self.back_frame
                                        .tile_vertex_storage_allocator
                                        .get(tile_storage_id)
                                        .vertex_buffer;
                storage_buffers.push((&fill_compute_program.tiles_storage_buffer, &tiles_buffer));
            }
            None => {
                // Work around a Metal bug by assigning any old shader to this buffer slot.
                storage_buffers.push((&fill_compute_program.tiles_storage_buffer,
                                      &self.back_frame.z_buffer));
            }
        }

        // This setup is an annoying workaround for the 64K limit of compute invocation in OpenGL.
        // TODO(pcwalton): Indirect compute dispatch!
        let dimensions = ComputeDimensions {
            x: fill_tile_count.min(1 << 16),
            y: (fill_tile_count + 0xffff) >> 16,
            z: 1,
        };
        let fill_tile_range = I32x2::new(0, fill_tile_count as i32) +
            I32x2::splat(first_fill_tile as i32);

        self.device.dispatch_compute(dimensions, &ComputeState {
            program: &fill_compute_program.program,
            textures: &[(&fill_compute_program.area_lut_texture, &self.area_lut_texture)],
            images: &[(&fill_compute_program.dest_image, image_texture, ImageAccess::Write)],
            uniforms: &[
                (&fill_compute_program.tile_range_uniform, UniformData::IVec2(fill_tile_range)),
                (&fill_compute_program.binned_on_gpu_uniform,
                 UniformData::Int(tile_storage_id.is_some() as i32)),
            ],
            storage_buffers: &storage_buffers,
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().fill_times.push(TimerFuture::new(timer_query));

        self.back_frame.framebuffer_flags.insert(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY);
    }

    fn clip_tiles(&mut self, clip_storage_id: StorageID, max_clipped_tile_count: u32) {
        // FIXME(pcwalton): Recycle these.
        let mask_framebuffer = self.back_frame
                                   .mask_framebuffer
                                   .as_ref()
                                   .expect("Where's the mask framebuffer?");
        let mask_texture = self.device.framebuffer_texture(mask_framebuffer);
        let mask_texture_size = self.device.texture_size(&mask_texture);
        let temp_texture = self.device.create_texture(TextureFormat::RGBA16F, mask_texture_size);
        let temp_framebuffer = self.device.create_framebuffer(temp_texture);

        let clip_vertex_storage =
            self.back_frame.clip_vertex_storage_allocator.get(clip_storage_id);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        // Copy out tiles.
        //
        // TODO(pcwalton): Don't do this on GL4.
        self.device.draw_elements_instanced(6, max_clipped_tile_count * 2, &RenderState {
            target: &RenderTarget::Framebuffer(&temp_framebuffer),
            program: &self.tile_clip_copy_program.program,
            vertex_array: &clip_vertex_storage.tile_clip_copy_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[
                (&self.tile_clip_copy_program.src_texture,
                 self.device.framebuffer_texture(mask_framebuffer)),
            ],
            images: &[],
            uniforms: &[
                (&self.tile_clip_copy_program.framebuffer_size_uniform,
                 UniformData::Vec2(mask_texture_size.to_f32().0)),
            ],
            storage_buffers: &[],
            viewport: RectI::new(Vector2I::zero(), mask_texture_size),
            options: RenderOptions::default(),
        });

        // Combine clip tiles.
        self.device.draw_elements_instanced(6, max_clipped_tile_count, &RenderState {
            target: &RenderTarget::Framebuffer(mask_framebuffer),
            program: &self.tile_clip_combine_program.program,
            vertex_array: &clip_vertex_storage.tile_clip_combine_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[
                (&self.tile_clip_combine_program.src_texture,
                 self.device.framebuffer_texture(&temp_framebuffer)),
            ],
            images: &[],
            uniforms: &[
                (&self.tile_clip_combine_program.framebuffer_size_uniform,
                 UniformData::Vec2(mask_texture_size.to_f32().0)),
            ],
            storage_buffers: &[],
            viewport: RectI::new(Vector2I::zero(), mask_texture_size),
            options: RenderOptions::default(),
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().tile_times.push(TimerFuture::new(timer_query));
    }

    // Computes backdrops, performs clipping, and populates Z buffers.
    fn prepare_tiles(&mut self, batch: &PrepareTilesBatch) {
        // Upload tiles to GPU or initialize them as appropriate.
        self.stats.alpha_tile_count += batch.tile_count as usize;
        let tile_vertex_storage_id = self.allocate_tiles(batch.tile_count);
        let tile_link_map_storage_id = self.allocate_tile_link_map(batch.tile_count);
        match batch.modal {
            PrepareTilesModalInfo::CPU(ref cpu_info) => {
                self.upload_tiles(tile_vertex_storage_id, &cpu_info.tiles);
            }
            PrepareTilesModalInfo::GPU(ref gpu_info) => {
                match gpu_info.modal {
                    PrepareTilesGPUModalInfo::CPUBinning { ref tiles, .. } => {
                        self.upload_tiles(tile_vertex_storage_id, tiles);
                        // FIXME(pcwalton): Initialize fill vertex tile map!
                    }
                    PrepareTilesGPUModalInfo::GPUBinning { ref tile_path_info, .. } => {
                        self.initialize_tiles(tile_vertex_storage_id,
                                              tile_link_map_storage_id,
                                              batch.tile_count,
                                              tile_path_info)
                    }
                }
            }
        }

        // Fetch and/or allocate clip storage as needed.
        let clip_storage_ids = match batch.clipped_path_info {
            Some(ref clipped_path_info) => {
                let clip_batch_id = clipped_path_info.clip_batch_id;
                let clip_tile_batch_info =
                    self.back_frame.tile_batch_info[clip_batch_id.0 as usize];
                Some(ClipStorageIDs {
                    metadata: clip_tile_batch_info.propagate_metadata_storage_id,
                    tiles: clip_tile_batch_info.tile_vertex_storage_id,
                    vertices: self.allocate_clip_storage(clipped_path_info.max_clipped_tile_count),
                })
            }
            None => None,
        };

        // Propagate backdrops, bin fills, render fills, and/or perform clipping on GPU if
        // necessary.
        let mut fill_storage_id = None;
        let propagate_metadata_storage_id = match batch.modal {
            PrepareTilesModalInfo::CPU(_) => None,
            PrepareTilesModalInfo::GPU(ref gpu_info) => {
                let propagate_metadata_storage_id =
                    self.upload_propagate_data(&gpu_info.propagate_metadata, &gpu_info.backdrops);

                // Bin and render fills if requested.
                if let PrepareTilesGPUModalInfo::GPUBinning {
                    ref dice_metadata,
                    transform,
                    ..
                } = gpu_info.modal {
                    let (segments_buffer, segment_count) =
                        self.dice_segments(dice_metadata, batch.segment_count, transform);
                    let fill_storage_info =
                        self.bin_segments_via_compute(segments_buffer,
                                                      segment_count,
                                                      propagate_metadata_storage_id,
                                                      tile_vertex_storage_id,
                                                      tile_link_map_storage_id,
                                                      batch.tile_count);
                    // FIXME(pcwalton): Don't unconditionally pass true for copying here.
                    self.reallocate_alpha_tile_pages_if_necessary(true);
                    match fill_storage_info {
                        FillStorageInfo::Raster(fill_storage_info) => {
                            fill_storage_id = Some(fill_storage_info.fill_storage_id);
                            self.draw_fills_via_raster(
                                fill_storage_info.fill_storage_id,
                                Some(tile_vertex_storage_id),
                                PrimitiveCount::Direct(fill_storage_info.fill_count));
                        }
                        FillStorageInfo::Compute(fill_storage_info) => {
                            fill_storage_id = Some(fill_storage_info.fill_storage_id);
                            self.draw_fills_via_compute(fill_storage_info,
                                                        Some(tile_vertex_storage_id));
                        }
                    }
                }

                self.propagate_tiles(gpu_info.backdrops.len() as u32,
                                     tile_vertex_storage_id,
                                     propagate_metadata_storage_id,
                                     clip_storage_ids.as_ref());
                Some(propagate_metadata_storage_id)
            }
        };

        // Record tile batch info.
        self.back_frame.tile_batch_info.insert(batch.batch_id.0 as usize, TileBatchInfo {
            tile_count: batch.tile_count,
            tile_vertex_storage_id,
            propagate_metadata_storage_id,
        });

        // Perform occlusion culling.
        match batch.modal {
            PrepareTilesModalInfo::GPU(_) => self.prepare_z_buffer(),
            PrepareTilesModalInfo::CPU(ref cpu_info) => self.upload_z_buffer(&cpu_info.z_buffer),
        } 

        // Perform clipping if necessary.
        if let (Some(clip_storage_ids), Some(clipped_path_info)) =
                (clip_storage_ids.as_ref(), batch.clipped_path_info.as_ref()) {
            // Upload clip tiles to GPU if they were computed on CPU.
            if clip_storage_ids.metadata.is_none() {
                let clips = clipped_path_info.clips.as_ref().expect("Where are the clips?");
                self.upload_clip_tiles(clip_storage_ids.vertices, clips);
            }

            self.clip_tiles(clip_storage_ids.vertices, clipped_path_info.max_clipped_tile_count);
        }

        self.draw_and_fill_tiles(tile_vertex_storage_id,
                                 fill_storage_id.unwrap(),
                                 tile_link_map_storage_id);
    }

    fn tile_transform(&self) -> Transform4F {
        let draw_viewport = self.draw_viewport().size().to_f32();
        let scale = Vector4F::new(2.0 / draw_viewport.x(), -2.0 / draw_viewport.y(), 1.0, 1.0);
        Transform4F::from_scale(scale).translate(Vector4F::new(-1.0, 1.0, 0.0, 1.0))
    }

    fn propagate_tiles(&mut self,
                       column_count: u32,
                       tile_storage_id: StorageID,
                       propagate_metadata_storage_id: StorageID,
                       clip_storage_ids: Option<&ClipStorageIDs>) {
        let propagate_program = &self.tile_post_programs
                                     .as_ref()
                                     .expect("GPU tile postprocessing is disabled!")
                                     .propagate_program;

        let alpha_tile_buffer = &self.back_frame
                                     .tile_vertex_storage_allocator
                                     .get(tile_storage_id)
                                     .vertex_buffer;
        let propagate_metadata_storage_buffer = self.back_frame
                                                    .tile_propagate_metadata_storage_allocator
                                                    .get(propagate_metadata_storage_id);

        let mut storage_buffers = vec![
            (&propagate_program.draw_metadata_storage_buffer, propagate_metadata_storage_buffer),
            (&propagate_program.backdrops_storage_buffer, &self.back_frame.backdrops_buffer),
            (&propagate_program.draw_tiles_storage_buffer, alpha_tile_buffer),
            (&propagate_program.z_buffer_storage_buffer, &self.back_frame.z_buffer),
        ];

        if let Some(clip_storage_ids) = clip_storage_ids {
            let clip_metadata_storage_id =
                clip_storage_ids.metadata.expect("Where's the clip metadata storage?");
            let clip_metadata_buffer = self.back_frame
                                           .tile_propagate_metadata_storage_allocator
                                           .get(clip_metadata_storage_id);
            let clip_tile_buffer = &self.back_frame
                                        .tile_vertex_storage_allocator
                                        .get(clip_storage_ids.tiles)
                                        .vertex_buffer;
            let clip_vertex_storage = self.back_frame
                                          .clip_vertex_storage_allocator
                                          .get(clip_storage_ids.vertices);
            storage_buffers.push((&propagate_program.clip_metadata_storage_buffer,
                                  clip_metadata_buffer));
            storage_buffers.push((&propagate_program.clip_tiles_storage_buffer,
                                  clip_tile_buffer));
            storage_buffers.push((&propagate_program.clip_vertex_storage_buffer,
                                  &clip_vertex_storage.vertex_buffer));
        }

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let dimensions = ComputeDimensions {
            x: (column_count + PROPAGATE_WORKGROUP_SIZE - 1) / PROPAGATE_WORKGROUP_SIZE,
            y: 1,
            z: 1,
        };
        self.device.dispatch_compute(dimensions, &ComputeState {
            program: &propagate_program.program,
            textures: &[],
            images: &[],
            uniforms: &[
                (&propagate_program.framebuffer_tile_size_uniform,
                 UniformData::IVec2(self.framebuffer_tile_size().0)),
                (&propagate_program.column_count_uniform, UniformData::Int(column_count as i32)),
            ],
            storage_buffers: &storage_buffers,
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().propagate_times.push(TimerFuture::new(timer_query));
    }

    fn prepare_z_buffer(&mut self) {
        let blit_buffer_program = &self.tile_post_programs
                                       .as_ref()
                                       .expect("GPU tile postprocessing is disabled!")
                                       .blit_buffer_program;

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let z_buffer_size = self.framebuffer_tile_size();

        self.device.draw_elements(6, &RenderState {
            target: &RenderTarget::Framebuffer(&self.back_frame.z_buffer_framebuffer),
            program: &blit_buffer_program.program,
            vertex_array: &self.back_frame.blit_buffer_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[],
            images: &[],
            storage_buffers: &[
                (&blit_buffer_program.buffer_storage_buffer, &self.back_frame.z_buffer),
            ],
            uniforms: &[
                (&blit_buffer_program.buffer_size_uniform, UniformData::IVec2(z_buffer_size.0)),
                 
            ],
            viewport: RectI::new(Vector2I::zero(), z_buffer_size),
            options: RenderOptions::default(),
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().propagate_times.push(TimerFuture::new(timer_query));
    }

    fn upload_z_buffer(&mut self, z_buffer: &DenseTileMap<i32>) {
        // TODO(pcwalton)
        let z_buffer_texture =
            self.device.framebuffer_texture(&self.back_frame.z_buffer_framebuffer);
        debug_assert_eq!(z_buffer.rect.origin(), Vector2I::default());
        debug_assert_eq!(z_buffer.rect.size(), self.device.texture_size(z_buffer_texture));
        unsafe {
            let z_data: &[i32] = &z_buffer.data;
            let z_data: &[u8] = slice::from_raw_parts(z_data.as_ptr() as *const u8,
                                                      z_data.len() * 4);
            self.device.upload_to_texture(z_buffer_texture,
                                          z_buffer.rect,
                                          TextureDataRef::U8(&z_data));
        }
    }

    fn allocate_clip_storage(&mut self, max_clipped_tile_count: u32) -> StorageID {
        let tile_clip_combine_program = &self.tile_clip_combine_program;
        let tile_clip_copy_program = &self.tile_clip_copy_program;
        let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
        let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
        self.back_frame.clip_vertex_storage_allocator.allocate(&self.device,
                                                               max_clipped_tile_count as u64,
                                                               |device, size| {
            ClipVertexStorage::new(size,
                                   device,
                                   tile_clip_combine_program,
                                   tile_clip_copy_program,
                                   quad_vertex_positions_buffer,
                                   quad_vertex_indices_buffer)
        })
    }

    // Uploads clip tiles from CPU to GPU.
    fn upload_clip_tiles(&mut self, clip_vertex_storage_id: StorageID, clips: &[Clip]) {
        let clip_vertex_storage = self.back_frame
                                      .clip_vertex_storage_allocator
                                      .get(clip_vertex_storage_id);
        self.device.upload_to_buffer(&clip_vertex_storage.vertex_buffer,
                                     0,
                                     clips,
                                     BufferTarget::Vertex);
    }

    fn draw_tiles(&mut self,
                  tile_count: u32,
                  storage_id: StorageID,
                  color_texture_0: Option<TileBatchTexture>,
                  blend_mode: BlendMode,
                  filter: Filter) {
        // TODO(pcwalton): Disable blend for solid tiles.

        let needs_readable_framebuffer = blend_mode.needs_readable_framebuffer();
        if needs_readable_framebuffer {
            self.copy_alpha_tiles_to_dest_blend_texture(tile_count, storage_id);
        }

        let clear_color = self.clear_color_for_draw_operation();
        let draw_viewport = self.draw_viewport();

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let z_buffer_texture =
            self.device.framebuffer_texture(&self.back_frame.z_buffer_framebuffer);
        let mut textures = vec![
            (&self.tile_program.texture_metadata_texture,
             &self.back_frame.texture_metadata_texture),
            (&self.tile_program.z_buffer_texture, z_buffer_texture),
        ];
        let mut uniforms = vec![
            (&self.tile_program.z_buffer_texture_size_uniform,
             UniformData::IVec2(self.device.texture_size(z_buffer_texture).0)),
            (&self.tile_program.transform_uniform,
             UniformData::Mat4(self.tile_transform().to_columns())),
            (&self.tile_program.tile_size_uniform,
             UniformData::Vec2(F32x2::new(TILE_WIDTH as f32, TILE_HEIGHT as f32))),
            (&self.tile_program.framebuffer_size_uniform,
             UniformData::Vec2(draw_viewport.size().to_f32().0)),
            (&self.tile_program.texture_metadata_size_uniform,
             UniformData::IVec2(I32x2::new(TEXTURE_METADATA_TEXTURE_WIDTH,
                                           TEXTURE_METADATA_TEXTURE_HEIGHT))),
        ];

        if needs_readable_framebuffer {
            textures.push((&self.tile_program.dest_texture,
                           self.device
                               .framebuffer_texture(&self.back_frame.dest_blend_framebuffer)));
        }

        if let Some(ref mask_framebuffer) = self.back_frame.mask_framebuffer {
            let mask_texture = self.device.framebuffer_texture(mask_framebuffer);
            uniforms.push((&self.tile_program.mask_texture_size_0_uniform,
                           UniformData::Vec2(self.device.texture_size(mask_texture).to_f32().0)));
            textures.push((&self.tile_program.mask_texture_0, mask_texture));
        }

        // TODO(pcwalton): Refactor.
        let mut ctrl = 0;
        match color_texture_0 {
            Some(color_texture) => {
                let color_texture_page = self.texture_page(color_texture.page);
                let color_texture_size = self.device.texture_size(color_texture_page).to_f32();
                self.device.set_texture_sampling_mode(color_texture_page,
                                                      color_texture.sampling_flags);
                textures.push((&self.tile_program.color_texture_0, color_texture_page));
                uniforms.push((&self.tile_program.color_texture_size_0_uniform,
                               UniformData::Vec2(color_texture_size.0)));

                ctrl |= color_texture.composite_op.to_combine_mode() <<
                    COMBINER_CTRL_COLOR_COMBINE_SHIFT;
            }
            None => {
                uniforms.push((&self.tile_program.color_texture_size_0_uniform,
                               UniformData::Vec2(F32x2::default())));
            }
        }

        ctrl |= blend_mode.to_composite_ctrl() << COMBINER_CTRL_COMPOSITE_SHIFT;

        match filter {
            Filter::None => self.set_uniforms_for_no_filter(&mut uniforms),
            Filter::RadialGradient { line, radii, uv_origin } => {
                ctrl |= COMBINER_CTRL_FILTER_RADIAL_GRADIENT << COMBINER_CTRL_COLOR_FILTER_SHIFT;
                self.set_uniforms_for_radial_gradient_filter(&mut uniforms, line, radii, uv_origin)
            }
            Filter::PatternFilter(PatternFilter::Text {
                fg_color,
                bg_color,
                defringing_kernel,
                gamma_correction,
            }) => {
                ctrl |= COMBINER_CTRL_FILTER_TEXT << COMBINER_CTRL_COLOR_FILTER_SHIFT;
                self.set_uniforms_for_text_filter(&mut textures,
                                                  &mut uniforms,
                                                  fg_color,
                                                  bg_color,
                                                  defringing_kernel,
                                                  gamma_correction);
            }
            Filter::PatternFilter(PatternFilter::Blur { direction, sigma }) => {
                ctrl |= COMBINER_CTRL_FILTER_BLUR << COMBINER_CTRL_COLOR_FILTER_SHIFT;
                self.set_uniforms_for_blur_filter(&mut uniforms, direction, sigma);
            }
        }

        uniforms.push((&self.tile_program.ctrl_uniform, UniformData::Int(ctrl)));

        let vertex_array = &self.back_frame
                                .tile_vertex_storage_allocator
                                .get(storage_id)
                                .tile_vertex_array
                                .vertex_array;

        self.device.draw_elements_instanced(6, tile_count, &RenderState {
            target: &self.draw_render_target(),
            program: &self.tile_program.program,
            vertex_array,
            primitive: Primitive::Triangles,
            textures: &textures,
            images: &[],
            storage_buffers: &[],
            uniforms: &uniforms,
            viewport: draw_viewport,
            options: RenderOptions {
                blend: blend_mode.to_blend_state(),
                stencil: self.stencil_state(),
                clear_ops: ClearOps { color: clear_color, ..ClearOps::default() },
                ..RenderOptions::default()
            },
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().tile_times.push(TimerFuture::new(timer_query));

        self.preserve_draw_framebuffer();
    }

    fn draw_and_fill_tiles(&mut self,
                           tile_storage_id: StorageID,
                           fill_storage_id: StorageID,
                           tile_link_map_storage_id: StorageID) {
        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let dest_texture = self.device.framebuffer_texture(&self.back_frame
                                                                .intermediate_dest_framebuffer);

        let fill_vertex_storage =
            self.back_frame.fill_vertex_storage_allocator.get(fill_storage_id);

        let tiles_buffer = &self.back_frame
                                .tile_vertex_storage_allocator
                                .get(tile_storage_id)
                                .vertex_buffer;

        let tile_link_map_buffer =
            self.back_frame.tile_link_map_storage_allocator.get(tile_link_map_storage_id);

        let framebuffer_tile_size = self.framebuffer_tile_size();
        let compute_dimensions = ComputeDimensions {
            x: framebuffer_tile_size.x() as u32,
            y: framebuffer_tile_size.y() as u32,
            z: 1,
        };
        self.device.dispatch_compute(compute_dimensions, &ComputeState {
            program: &self.tile_fill_program.program,
            textures: &[(&self.tile_fill_program.area_lut_texture, &self.area_lut_texture)],
            uniforms: &[
                (&self.tile_fill_program.framebuffer_tile_size_uniform,
                 UniformData::IVec2(framebuffer_tile_size.0)),
            ],
            images: &[(&self.tile_fill_program.dest_image, &dest_texture, ImageAccess::Write)],
            storage_buffers: &[
                (&self.tile_fill_program.fills_storage_buffer, &fill_vertex_storage.vertex_buffer),
                (&self.tile_fill_program.tile_link_map_storage_buffer, &tile_link_map_buffer),
                (&self.tile_fill_program.tiles_storage_buffer, &tiles_buffer),
                (&self.tile_fill_program.initial_tile_map_storage_buffer,
                 &self.back_frame.initial_tile_map_buffer),
            ],
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().bin_times.push(TimerFuture::new(timer_query));
    }

    fn copy_alpha_tiles_to_dest_blend_texture(&mut self, tile_count: u32, storage_id: StorageID) {
        let draw_viewport = self.draw_viewport();

        let mut textures = vec![];
        let mut uniforms = vec![
            (&self.tile_copy_program.transform_uniform,
             UniformData::Mat4(self.tile_transform().to_columns())),
            (&self.tile_copy_program.tile_size_uniform,
             UniformData::Vec2(F32x2::new(TILE_WIDTH as f32, TILE_HEIGHT as f32))),
        ];

        let draw_framebuffer = match self.draw_render_target() {
            RenderTarget::Framebuffer(framebuffer) => framebuffer,
            RenderTarget::Default => panic!("Can't copy alpha tiles from default framebuffer!"),
        };
        let draw_texture = self.device.framebuffer_texture(&draw_framebuffer);

        textures.push((&self.tile_copy_program.src_texture, draw_texture));
        uniforms.push((&self.tile_copy_program.framebuffer_size_uniform,
                       UniformData::Vec2(draw_viewport.size().to_f32().0)));

        let vertex_array = &self.back_frame
                                .tile_vertex_storage_allocator
                                .get(storage_id)
                                .tile_copy_vertex_array
                                .vertex_array;

        self.device.draw_elements(tile_count * 6, &RenderState {
            target: &RenderTarget::Framebuffer(&self.back_frame.dest_blend_framebuffer),
            program: &self.tile_copy_program.program,
            vertex_array,
            primitive: Primitive::Triangles,
            textures: &textures,
            images: &[],
            storage_buffers: &[],
            uniforms: &uniforms,
            viewport: draw_viewport,
            options: RenderOptions {
                clear_ops: ClearOps {
                    color: Some(ColorF::new(1.0, 0.0, 0.0, 1.0)),
                    ..ClearOps::default()
                },
                ..RenderOptions::default()
            },
        });
    }

    fn draw_stencil(&mut self, quad_positions: &[Vector4F]) {
        self.device.allocate_buffer(&self.back_frame.stencil_vertex_array.vertex_buffer,
                                    BufferData::Memory(quad_positions),
                                    BufferTarget::Vertex);

        // Create indices for a triangle fan. (This is OK because the clipped quad should always be
        // convex.)
        let mut indices: Vec<u32> = vec![];
        for index in 1..(quad_positions.len() as u32 - 1) {
            indices.extend_from_slice(&[0, index as u32, index + 1]);
        }
        self.device.allocate_buffer(&self.back_frame.stencil_vertex_array.index_buffer,
                                    BufferData::Memory(&indices),
                                    BufferTarget::Index);

        self.device.draw_elements(indices.len() as u32, &RenderState {
            target: &self.draw_render_target(),
            program: &self.stencil_program.program,
            vertex_array: &self.back_frame.stencil_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[],
            images: &[],
            storage_buffers: &[],
            uniforms: &[],
            viewport: self.draw_viewport(),
            options: RenderOptions {
                // FIXME(pcwalton): Should we really write to the depth buffer?
                depth: Some(DepthState { func: DepthFunc::Less, write: true }),
                stencil: Some(StencilState {
                    func: StencilFunc::Always,
                    reference: 1,
                    mask: 1,
                    write: true,
                }),
                color_mask: false,
                clear_ops: ClearOps { stencil: Some(0), ..ClearOps::default() },
                ..RenderOptions::default()
            },
        });
    }

    pub fn reproject_texture(
        &mut self,
        texture: &D::Texture,
        old_transform: &Transform4F,
        new_transform: &Transform4F,
    ) {
        let clear_color = self.clear_color_for_draw_operation();

        self.device.draw_elements(6, &RenderState {
            target: &self.draw_render_target(),
            program: &self.reprojection_program.program,
            vertex_array: &self.back_frame.reprojection_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[(&self.reprojection_program.texture, texture)],
            images: &[],
            storage_buffers: &[],
            uniforms: &[
                (&self.reprojection_program.old_transform_uniform,
                 UniformData::from_transform_3d(old_transform)),
                (&self.reprojection_program.new_transform_uniform,
                 UniformData::from_transform_3d(new_transform)),
            ],
            viewport: self.draw_viewport(),
            options: RenderOptions {
                blend: BlendMode::SrcOver.to_blend_state(),
                depth: Some(DepthState { func: DepthFunc::Less, write: false, }),
                clear_ops: ClearOps { color: clear_color, ..ClearOps::default() },
                ..RenderOptions::default()
            },
        });

        self.preserve_draw_framebuffer();
    }

    pub fn draw_render_target(&self) -> RenderTarget<D> {
        match self.render_target_stack.last() {
            Some(&render_target_id) => {
                let texture_page_id = self.render_target_location(render_target_id).page;
                let framebuffer = self.texture_page_framebuffer(texture_page_id);
                RenderTarget::Framebuffer(framebuffer)
            }
            None => {
                if self.flags.contains(RendererFlags::INTERMEDIATE_DEST_FRAMEBUFFER_NEEDED) {
                    RenderTarget::Framebuffer(&self.back_frame.intermediate_dest_framebuffer)
                } else {
                    match self.dest_framebuffer {
                        DestFramebuffer::Default { .. } => RenderTarget::Default,
                        DestFramebuffer::Other(ref framebuffer) => {
                            RenderTarget::Framebuffer(framebuffer)
                        }
                    }
                }
            }
        }
    }

    fn push_render_target(&mut self, render_target_id: RenderTargetId) {
        self.render_target_stack.push(render_target_id);
    }

    fn pop_render_target(&mut self) {
        self.render_target_stack.pop().expect("Render target stack underflow!");
    }

    fn set_uniforms_for_no_filter<'a>(&'a self,
                                      uniforms: &mut Vec<(&'a D::Uniform, UniformData)>) {
        uniforms.extend_from_slice(&[
            (&self.tile_program.filter_params_0_uniform, UniformData::Vec4(F32x4::default())),
            (&self.tile_program.filter_params_1_uniform, UniformData::Vec4(F32x4::default())),
            (&self.tile_program.filter_params_2_uniform, UniformData::Vec4(F32x4::default())),
        ]);
    }

    fn set_uniforms_for_radial_gradient_filter<'a>(
            &'a self,
            uniforms: &mut Vec<(&'a D::Uniform, UniformData)>,
            line: LineSegment2F,
            radii: F32x2,
            uv_origin: Vector2F) {
        uniforms.extend_from_slice(&[
            (&self.tile_program.filter_params_0_uniform,
             UniformData::Vec4(line.from().0.concat_xy_xy(line.vector().0))),
            (&self.tile_program.filter_params_1_uniform,
             UniformData::Vec4(radii.concat_xy_xy(uv_origin.0))),
            (&self.tile_program.filter_params_2_uniform, UniformData::Vec4(F32x4::default())),
        ]);
    }

    fn set_uniforms_for_text_filter<'a>(
            &'a self,
            textures: &mut Vec<TextureBinding<'a, D::TextureParameter, D::Texture>>,
            uniforms: &mut Vec<UniformBinding<'a, D::Uniform>>,
            fg_color: ColorF,
            bg_color: ColorF,
            defringing_kernel: Option<DefringingKernel>,
            gamma_correction: bool) {
        textures.push((&self.tile_program.gamma_lut_texture, &self.gamma_lut_texture));

        match defringing_kernel {
            Some(ref kernel) => {
                uniforms.push((&self.tile_program.filter_params_0_uniform,
                               UniformData::Vec4(F32x4::from_slice(&kernel.0))));
            }
            None => {
                uniforms.push((&self.tile_program.filter_params_0_uniform,
                               UniformData::Vec4(F32x4::default())));
            }
        }

        let mut params_2 = fg_color.0;
        params_2.set_w(gamma_correction as i32 as f32);

        uniforms.extend_from_slice(&[
            (&self.tile_program.filter_params_1_uniform, UniformData::Vec4(bg_color.0)),
            (&self.tile_program.filter_params_2_uniform, UniformData::Vec4(params_2)),
        ]);
    }

    fn set_uniforms_for_blur_filter<'a>(&'a self,
                                        uniforms: &mut Vec<(&'a D::Uniform, UniformData)>,
                                        direction: BlurDirection,
                                        sigma: f32) {
        let sigma_inv = 1.0 / sigma;
        let gauss_coeff_x = SQRT_2_PI_INV * sigma_inv;
        let gauss_coeff_y = f32::exp(-0.5 * sigma_inv * sigma_inv);
        let gauss_coeff_z = gauss_coeff_y * gauss_coeff_y;

        let src_offset = match direction {
            BlurDirection::X => vec2f(1.0, 0.0),
            BlurDirection::Y => vec2f(0.0, 1.0),
        };

        let support = f32::ceil(1.5 * sigma) * 2.0;

        uniforms.extend_from_slice(&[
            (&self.tile_program.filter_params_0_uniform,
             UniformData::Vec4(src_offset.0.concat_xy_xy(F32x2::new(support, 0.0)))),
            (&self.tile_program.filter_params_1_uniform,
             UniformData::Vec4(F32x4::new(gauss_coeff_x, gauss_coeff_y, gauss_coeff_z, 0.0))),
            (&self.tile_program.filter_params_2_uniform, UniformData::Vec4(F32x4::default())),
        ]);
    }

    fn clear_dest_framebuffer_if_necessary(&mut self) {
        let background_color = match self.options.background_color {
            None => return,
            Some(background_color) => background_color,
        };

        if self.back_frame
               .framebuffer_flags
               .contains(FramebufferFlags::DEST_FRAMEBUFFER_IS_DIRTY) {
            return;
        }

        let main_viewport = self.main_viewport();
        let uniforms = [
            (&self.clear_program.rect_uniform, UniformData::Vec4(main_viewport.to_f32().0)),
            (&self.clear_program.framebuffer_size_uniform,
             UniformData::Vec2(main_viewport.size().to_f32().0)),
            (&self.clear_program.color_uniform, UniformData::Vec4(background_color.0)),
        ];

        self.device.draw_elements(6, &RenderState {
            target: &RenderTarget::Default,
            program: &self.clear_program.program,
            vertex_array: &self.back_frame.clear_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[],
            images: &[],
            storage_buffers: &[],
            uniforms: &uniforms[..],
            viewport: main_viewport,
            options: RenderOptions::default(),
        });
    }

    fn blit_intermediate_dest_framebuffer_if_necessary(&mut self) {
        if !self.flags.contains(RendererFlags::INTERMEDIATE_DEST_FRAMEBUFFER_NEEDED) {
            return;
        }

        let main_viewport = self.main_viewport();

        let textures = [
            (&self.blit_program.src_texture,
             self.device.framebuffer_texture(&self.back_frame.intermediate_dest_framebuffer))
        ];

        self.device.draw_elements(6, &RenderState {
            target: &RenderTarget::Default,
            program: &self.blit_program.program,
            vertex_array: &self.back_frame.blit_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &textures[..],
            images: &[],
            storage_buffers: &[],
            uniforms: &[
                (&self.blit_program.framebuffer_size_uniform,
                 UniformData::Vec2(main_viewport.size().to_f32().0)),
                (&self.blit_program.dest_rect_uniform,
                 UniformData::Vec4(RectF::new(Vector2F::zero(), main_viewport.size().to_f32()).0)),
            ],
            viewport: main_viewport,
            options: RenderOptions {
                clear_ops: ClearOps {
                    color: Some(ColorF::new(0.0, 0.0, 0.0, 1.0)),
                    ..ClearOps::default()
                },
                ..RenderOptions::default()
            },
        });
    }

    fn stencil_state(&self) -> Option<StencilState> {
        if !self.flags.contains(RendererFlags::USE_DEPTH) {
            return None;
        }

        Some(StencilState {
            func: StencilFunc::Equal,
            reference: 1,
            mask: 1,
            write: false,
        })
    }

    fn clear_color_for_draw_operation(&self) -> Option<ColorF> {
        let must_preserve_contents = match self.render_target_stack.last() {
            Some(&render_target_id) => {
                let texture_page = self.render_target_location(render_target_id).page;
                self.texture_pages[texture_page.0 as usize]
                    .as_ref()
                    .expect("Draw target texture page not allocated!")
                    .must_preserve_contents
            }
            None => {
                self.back_frame
                    .framebuffer_flags
                    .contains(FramebufferFlags::DEST_FRAMEBUFFER_IS_DIRTY)
            }
        };

        if must_preserve_contents {
            None
        } else if self.render_target_stack.is_empty() {
            self.options.background_color
        } else {
            Some(ColorF::default())
        }
    }

    fn preserve_draw_framebuffer(&mut self) {
        match self.render_target_stack.last() {
            Some(&render_target_id) => {
                let texture_page = self.render_target_location(render_target_id).page;
                self.texture_pages[texture_page.0 as usize]
                    .as_mut()
                    .expect("Draw target texture page not allocated!")
                    .must_preserve_contents = true;
            }
            None => {
                self.back_frame
                    .framebuffer_flags
                    .insert(FramebufferFlags::DEST_FRAMEBUFFER_IS_DIRTY);
            }
        }
    }

    pub fn draw_viewport(&self) -> RectI {
        match self.render_target_stack.last() {
            Some(&render_target_id) => self.render_target_location(render_target_id).rect,
            None => self.main_viewport(),
        }
    }

    fn main_viewport(&self) -> RectI {
        match self.dest_framebuffer {
            DestFramebuffer::Default { viewport, .. } => viewport,
            DestFramebuffer::Other(ref framebuffer) => {
                let size = self
                    .device
                    .texture_size(self.device.framebuffer_texture(framebuffer));
                RectI::new(Vector2I::default(), size)
            }
        }
    }

    fn mask_viewport(&self) -> RectI {
        let page_count = self.back_frame.allocated_alpha_tile_page_count as i32;
        let height = MASK_FRAMEBUFFER_HEIGHT * page_count;
        RectI::new(Vector2I::default(), vec2i(MASK_FRAMEBUFFER_WIDTH, height))
    }

    fn render_target_location(&self, render_target_id: RenderTargetId) -> TextureLocation {
        self.render_targets[render_target_id.render_target as usize].location
    }

    fn texture_page_framebuffer(&self, id: TexturePageId) -> &D::Framebuffer {
        &self.texture_pages[id.0 as usize]
             .as_ref()
             .expect("Texture page not allocated!")
             .framebuffer
    }

    fn texture_page(&self, id: TexturePageId) -> &D::Texture {
        self.device.framebuffer_texture(&self.texture_page_framebuffer(id))
    }

    fn framebuffer_tile_size(&self) -> Vector2I {
        pixel_size_to_tile_size(self.dest_framebuffer.window_size(&self.device))
    }
}

impl<D> Frame<D> where D: Device {
    // FIXME(pcwalton): This signature shouldn't be so big. Make a struct.
    fn new(device: &D,
           blit_program: &BlitProgram<D>,
           blit_buffer_program: &BlitBufferProgram<D>,
           clear_program: &ClearProgram<D>,
           reprojection_program: &ReprojectionProgram<D>,
           stencil_program: &StencilProgram<D>,
           quad_vertex_positions_buffer: &D::Buffer,
           quad_vertex_indices_buffer: &D::Buffer,
           window_size: Vector2I)
           -> Frame<D> {
        let quads_vertex_indices_buffer = device.create_buffer(BufferUploadMode::Dynamic);

        let blit_vertex_array = BlitVertexArray::new(device,
                                                     &blit_program,
                                                     &quad_vertex_positions_buffer,
                                                     &quad_vertex_indices_buffer);
        let blit_buffer_vertex_array = BlitBufferVertexArray::new(device,
                                                                  &blit_buffer_program,
                                                                  &quad_vertex_positions_buffer,
                                                                  &quad_vertex_indices_buffer);
        let clear_vertex_array = ClearVertexArray::new(device,
                                                       &clear_program,
                                                       &quad_vertex_positions_buffer,
                                                       &quad_vertex_indices_buffer);
        let reprojection_vertex_array = ReprojectionVertexArray::new(device,
                                                                     &reprojection_program,
                                                                     &quad_vertex_positions_buffer,
                                                                     &quad_vertex_indices_buffer);
        let stencil_vertex_array = StencilVertexArray::new(device, &stencil_program);

        let path_info_storage_allocator = BufferStorageAllocator::new(MIN_PATH_INFO_STORAGE_CLASS);
        let dice_metadata_storage_allocator =
            StorageAllocator::new(MIN_DICE_METADATA_STORAGE_CLASS);
        let fill_vertex_storage_allocator = StorageAllocator::new(MIN_FILL_STORAGE_CLASS);
        let tile_link_map_storage_allocator =
            BufferStorageAllocator::new(MIN_TILE_LINK_MAP_STORAGE_CLASS);
        let tile_vertex_storage_allocator = StorageAllocator::new(MIN_TILE_STORAGE_CLASS);
        let tile_propagate_metadata_storage_allocator =
            BufferStorageAllocator::new(MIN_TILE_PROPAGATE_METADATA_STORAGE_CLASS);
        let clip_vertex_storage_allocator = StorageAllocator::new(MIN_CLIP_VERTEX_STORAGE_CLASS);

        let texture_metadata_texture_size = vec2i(TEXTURE_METADATA_TEXTURE_WIDTH,
                                                  TEXTURE_METADATA_TEXTURE_HEIGHT);
        let texture_metadata_texture = device.create_texture(TextureFormat::RGBA16F,
                                                             texture_metadata_texture_size);

        let intermediate_dest_texture = device.create_texture(TextureFormat::RGBA8, window_size);
        let intermediate_dest_framebuffer = device.create_framebuffer(intermediate_dest_texture);

        let dest_blend_texture = device.create_texture(TextureFormat::RGBA8, window_size);
        let dest_blend_framebuffer = device.create_framebuffer(dest_blend_texture);

        let backdrops_buffer = device.create_buffer(BufferUploadMode::Dynamic);

        let framebuffer_tile_size = pixel_size_to_tile_size(window_size);
        let z_buffer_texture = device.create_texture(TextureFormat::RGBA8, framebuffer_tile_size);
        device.set_texture_sampling_mode(&z_buffer_texture,
                                         TextureSamplingFlags::NEAREST_MIN |
                                         TextureSamplingFlags::NEAREST_MAG);
        let z_buffer_framebuffer = device.create_framebuffer(z_buffer_texture);
        let z_buffer = device.create_buffer(BufferUploadMode::Static);
        let z_buffer_length = framebuffer_tile_size.x() as usize *
            framebuffer_tile_size.y() as usize;
        device.allocate_buffer::<i32>(&z_buffer,
                                      BufferData::Uninitialized(z_buffer_length),
                                      BufferTarget::Storage);

        let initial_tile_map_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        device.allocate_buffer::<u32>(&initial_tile_map_buffer,   
                                      BufferData::Uninitialized(z_buffer_length),
                                      BufferTarget::Storage);

        Frame {
            blit_vertex_array,
            blit_buffer_vertex_array,
            clear_vertex_array,
            path_info_storage_allocator,
            dice_metadata_storage_allocator,
            tile_vertex_storage_allocator,
            fill_vertex_storage_allocator,
            tile_link_map_storage_allocator,
            tile_propagate_metadata_storage_allocator,
            clip_vertex_storage_allocator,
            reprojection_vertex_array,
            stencil_vertex_array,
            quads_vertex_indices_buffer,
            quads_vertex_indices_length: 0,
            texture_metadata_texture,
            buffered_fills: vec![],
            pending_fills: vec![],
            max_alpha_tile_index: 0,
            allocated_alpha_tile_page_count: 0,
            tile_batch_info: VecMap::new(),
            mask_framebuffer: None,
            intermediate_dest_framebuffer,
            dest_blend_framebuffer,
            backdrops_buffer,
            initial_tile_map_buffer,
            z_buffer_framebuffer,
            z_buffer,
            framebuffer_flags: FramebufferFlags::empty(),
        }
    }
}

#[derive(Clone, Copy)]
struct TileBatchInfo {
    tile_count: u32,
    tile_vertex_storage_id: StorageID,
    // Only present if we're doing tile preparation on GPU.
    propagate_metadata_storage_id: Option<StorageID>,
}

// Buffer management

struct StorageAllocator<D, S> where D: Device {
    buckets: Vec<StorageAllocatorBucket<S>>,
    min_size_class: usize,
    phantom: PhantomData<D>,
}

struct BufferStorageAllocator<D, T> where D: Device {
    allocator: StorageAllocator<D, D::Buffer>,
    phantom: PhantomData<T>,
}

struct StorageAllocatorBucket<S> {
    free: Vec<S>,
    in_use: Vec<S>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct StorageID {
    bucket: usize,
    index: usize,
}

impl<D, S> StorageAllocator<D, S> where D: Device {
    fn new(min_size_class: usize) -> StorageAllocator<D, S> {
        StorageAllocator { buckets: vec![], min_size_class, phantom: PhantomData }
    }

    fn allocate<F>(&mut self, device: &D, size: u64, allocator: F) -> StorageID
                   where D: Device, F: FnOnce(&D, u64) -> S {
        let size_class = (64 - (size.leading_zeros() as usize)).max(self.min_size_class);
        let bucket_index = size_class - self.min_size_class;
        while self.buckets.len() < bucket_index + 1 {
            self.buckets.push(StorageAllocatorBucket { free: vec![], in_use: vec![] });
        }

        let bucket = &mut self.buckets[bucket_index];
        match bucket.free.pop() {
            Some(storage) => bucket.in_use.push(storage),
            None => bucket.in_use.push(allocator(device, 1 << size_class as u64)),
        }
        StorageID { bucket: bucket_index, index: bucket.in_use.len() - 1 }
    }

    fn get(&self, storage_id: StorageID) -> &S {
        &self.buckets[storage_id.bucket].in_use[storage_id.index]
    }

    fn end_frame(&mut self) {
        for bucket in &mut self.buckets {
            bucket.free.extend(mem::replace(&mut bucket.in_use, vec![]).into_iter())
        }
    }
}

impl<D, T> BufferStorageAllocator<D, T> where D: Device {
    fn new(min_size_class: usize) -> BufferStorageAllocator<D, T> {
        BufferStorageAllocator {
            allocator: StorageAllocator::new(min_size_class),
            phantom: PhantomData,
        }
    }

    fn allocate(&mut self, device: &D, size: u64, target: BufferTarget) -> StorageID
                where D: Device {
        self.allocator.allocate(device, size, |device, size| {
            let buffer = device.create_buffer(BufferUploadMode::Dynamic);
            device.allocate_buffer::<T>(&buffer, BufferData::Uninitialized(size as usize), target);
            buffer
        })
    }

    fn get(&self, storage_id: StorageID) -> &D::Buffer {
        self.allocator.get(storage_id)
    }

    fn end_frame(&mut self) {
        self.allocator.end_frame()
    }
}

struct DiceMetadataStorage<D> where D: Device {
    metadata_buffer: D::Buffer,
    indirect_draw_params_buffer: D::Buffer,
}

struct FillVertexStorage<D> where D: Device {
    vertex_buffer: D::Buffer,
    // Will be `None` if we're using compute.
    vertex_array: Option<FillVertexArray<D>>,
    indirect_draw_params_buffer: Option<D::Buffer>,
}

struct TileVertexStorage<D> where D: Device {
    tile_vertex_array: TileVertexArray<D>,
    tile_copy_vertex_array: CopyTileVertexArray<D>,
    vertex_buffer: D::Buffer,
}

struct ClipVertexStorage<D> where D: Device {
    tile_clip_copy_vertex_array: ClipTileCopyVertexArray<D>,
    tile_clip_combine_vertex_array: ClipTileCombineVertexArray<D>,
    vertex_buffer: D::Buffer,
}

impl<D> DiceMetadataStorage<D> where D: Device {
    fn new(device: &D, size: u64) -> DiceMetadataStorage<D> {
        let metadata_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        let indirect_draw_params_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        device.allocate_buffer::<DiceMetadata>(&metadata_buffer,
                                               BufferData::Uninitialized(size as usize),
                                               BufferTarget::Storage);
        device.allocate_buffer::<u32>(&indirect_draw_params_buffer,
                                      BufferData::Uninitialized(8),
                                      BufferTarget::Storage);
        DiceMetadataStorage { metadata_buffer, indirect_draw_params_buffer }
    }
}

impl<D> FillVertexStorage<D> where D: Device {
    fn new(size: u64,
           device: &D,
           fill_program: &FillProgram<D>,
           quad_vertex_positions_buffer: &D::Buffer,
           quad_vertex_indices_buffer: &D::Buffer,
           gpu_features: RendererGPUFeatures)
           -> FillVertexStorage<D> {
        let vertex_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        let vertex_buffer_data: BufferData<Fill> = BufferData::Uninitialized(size as usize);
        device.allocate_buffer(&vertex_buffer, vertex_buffer_data, BufferTarget::Vertex);

        let vertex_array = match *fill_program {
            FillProgram::Raster(ref fill_raster_program) => {
                Some(FillVertexArray::new(device,
                                          fill_raster_program,
                                          &vertex_buffer,
                                          quad_vertex_positions_buffer,
                                          quad_vertex_indices_buffer))
            }
            FillProgram::Compute(_) => None,
        };

        let indirect_draw_params_buffer =
            if gpu_features.contains(RendererGPUFeatures::BIN_ON_GPU) {
                let indirect_draw_params_buffer = device.create_buffer(BufferUploadMode::Static);
                device.allocate_buffer::<u32>(&indirect_draw_params_buffer,
                                              BufferData::Uninitialized(8),
                                              BufferTarget::Storage);
                Some(indirect_draw_params_buffer)
            } else {
                None
            };

        FillVertexStorage { vertex_buffer, vertex_array, indirect_draw_params_buffer }
    }
}

impl<D> TileVertexStorage<D> where D: Device {
    fn new(size: u64,
           device: &D,
           tile_program: &TileProgram<D>,
           tile_copy_program: &CopyTileProgram<D>,
           quad_vertex_positions_buffer: &D::Buffer,
           quad_vertex_indices_buffer: &D::Buffer)
           -> TileVertexStorage<D> {
        let vertex_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        device.allocate_buffer::<TileObjectPrimitive>(&vertex_buffer,
                                                      BufferData::Uninitialized(size as usize),
                                                      BufferTarget::Vertex);
        let tile_vertex_array = TileVertexArray::new(device,
                                                     &tile_program,
                                                     &vertex_buffer,
                                                     &quad_vertex_positions_buffer,
                                                     &quad_vertex_indices_buffer);
        let tile_copy_vertex_array = CopyTileVertexArray::new(device,
                                                              &tile_copy_program,
                                                              &vertex_buffer,
                                                              &quad_vertex_indices_buffer);
        TileVertexStorage { vertex_buffer, tile_vertex_array, tile_copy_vertex_array }
    }
}

impl<D> ClipVertexStorage<D> where D: Device {
    fn new(size: u64,
           device: &D,
           tile_clip_combine_program: &ClipTileCombineProgram<D>,
           tile_clip_copy_program: &ClipTileCopyProgram<D>,
           quad_vertex_positions_buffer: &D::Buffer,
           quad_vertex_indices_buffer: &D::Buffer)
           -> ClipVertexStorage<D> {
        let vertex_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        device.allocate_buffer::<Clip>(&vertex_buffer,
                                       BufferData::Uninitialized(size as usize),
                                       BufferTarget::Vertex);
        let tile_clip_combine_vertex_array =
            ClipTileCombineVertexArray::new(device,
                                            &tile_clip_combine_program,
                                            &vertex_buffer,
                                            &quad_vertex_positions_buffer,
                                            &quad_vertex_indices_buffer);
        let tile_clip_copy_vertex_array =
            ClipTileCopyVertexArray::new(device,
                                         &tile_clip_copy_program,
                                         &vertex_buffer,
                                         &quad_vertex_positions_buffer,
                                         &quad_vertex_indices_buffer);
        ClipVertexStorage {
            vertex_buffer,
            tile_clip_combine_vertex_array,
            tile_clip_copy_vertex_array,
        }
    }
}

// Render stats

#[derive(Clone, Copy, Debug, Default)]
pub struct RenderStats {
    pub path_count: usize,
    pub fill_count: usize,
    pub alpha_tile_count: usize,
    pub solid_tile_count: usize,
    pub cpu_build_time: Duration,
}

impl Add<RenderStats> for RenderStats {
    type Output = RenderStats;
    fn add(self, other: RenderStats) -> RenderStats {
        RenderStats {
            path_count: self.path_count + other.path_count,
            solid_tile_count: self.solid_tile_count + other.solid_tile_count,
            alpha_tile_count: self.alpha_tile_count + other.alpha_tile_count,
            fill_count: self.fill_count + other.fill_count,
            cpu_build_time: self.cpu_build_time + other.cpu_build_time,
        }
    }
}

impl Div<usize> for RenderStats {
    type Output = RenderStats;
    fn div(self, divisor: usize) -> RenderStats {
        RenderStats {
            path_count: self.path_count / divisor,
            solid_tile_count: self.solid_tile_count / divisor,
            alpha_tile_count: self.alpha_tile_count / divisor,
            fill_count: self.fill_count / divisor,
            cpu_build_time: self.cpu_build_time / divisor as u32,
        }
    }
}

struct TimerQueryCache<D> where D: Device {
    free_queries: Vec<D::TimerQuery>,
}

struct PendingTimer<D> where D: Device {
    bin_times: Vec<TimerFuture<D>>,
    fill_times: Vec<TimerFuture<D>>,
    propagate_times: Vec<TimerFuture<D>>,
    tile_times: Vec<TimerFuture<D>>,
}

enum TimerFuture<D> where D: Device {
    Pending(D::TimerQuery),
    Resolved(Duration),
}

impl<D> TimerQueryCache<D> where D: Device {
    fn new(_: &D) -> TimerQueryCache<D> {
        TimerQueryCache { free_queries: vec![] }
    }

    fn alloc(&mut self, device: &D) -> D::TimerQuery {
        self.free_queries.pop().unwrap_or_else(|| device.create_timer_query())
    }

    fn free(&mut self, old_query: D::TimerQuery) {
        self.free_queries.push(old_query);
    }
}

impl<D> PendingTimer<D> where D: Device {
    fn new() -> PendingTimer<D> {
        PendingTimer {
            bin_times: vec![],
            fill_times: vec![],
            propagate_times: vec![],
            tile_times: vec![],
        }
    }

    fn poll(&mut self, device: &D) -> Vec<D::TimerQuery> {
        let mut old_queries = vec![];
        for future in self.bin_times.iter_mut().chain(self.fill_times.iter_mut())
                                               .chain(self.propagate_times.iter_mut())
                                               .chain(self.tile_times.iter_mut()) {
            if let Some(old_query) = future.poll(device) {
                old_queries.push(old_query)
            }
        }
        old_queries
    }

    fn total_time(&self) -> Option<RenderTime> {
        let bin_time = total_time_of_timer_futures(&self.bin_times);
        let fill_time = total_time_of_timer_futures(&self.fill_times);
        let propagate_time = total_time_of_timer_futures(&self.propagate_times);
        let tile_time = total_time_of_timer_futures(&self.tile_times);
        match (bin_time, fill_time, propagate_time, tile_time) {
            (Some(bin_time), Some(fill_time), Some(propagate_time), Some(tile_time)) => {
                Some(RenderTime { bin_time, fill_time, propagate_time, tile_time })
            }
            _ => None,
        }
    }
}

impl<D> TimerFuture<D> where D: Device {
    fn new(query: D::TimerQuery) -> TimerFuture<D> {
        TimerFuture::Pending(query)
    }

    fn poll(&mut self, device: &D) -> Option<D::TimerQuery> {
        let duration = match *self {
            TimerFuture::Pending(ref query) => device.try_recv_timer_query(query),
            TimerFuture::Resolved(_) => None,
        };
        match duration {
            None => None,
            Some(duration) => {
                match mem::replace(self, TimerFuture::Resolved(duration)) {
                    TimerFuture::Resolved(_) => unreachable!(),
                    TimerFuture::Pending(old_query) => Some(old_query),
                }
            }
        }
    }
}

fn total_time_of_timer_futures<D>(futures: &[TimerFuture<D>]) -> Option<Duration> where D: Device {
    let mut total = Duration::default();
    for future in futures {
        match *future {
            TimerFuture::Pending(_) => return None,
            TimerFuture::Resolved(time) => total += time,
        }
    }
    Some(total)
}

#[derive(Clone, Copy, Debug)]
pub struct RenderTime {
    pub bin_time: Duration,
    pub fill_time: Duration,
    pub propagate_time: Duration,
    pub tile_time: Duration,
}

impl Default for RenderTime {
    #[inline]
    fn default() -> RenderTime {
        RenderTime {
            bin_time: Duration::new(0, 0),
            fill_time: Duration::new(0, 0),
            propagate_time: Duration::new(0, 0),
            tile_time: Duration::new(0, 0),
        }
    }
}

impl Add<RenderTime> for RenderTime {
    type Output = RenderTime;

    #[inline]
    fn add(self, other: RenderTime) -> RenderTime {
        RenderTime {
            bin_time: self.bin_time + other.bin_time,
            fill_time: self.fill_time + other.fill_time,
            propagate_time: self.propagate_time + other.propagate_time,
            tile_time: self.tile_time + other.tile_time,
        }
    }
}

impl Div<usize> for RenderTime {
    type Output = RenderTime;

    #[inline]
    fn div(self, divisor: usize) -> RenderTime {
        let divisor = divisor as u32;
        RenderTime {
            bin_time: self.bin_time / divisor,
            fill_time: self.fill_time / divisor,
            propagate_time: self.propagate_time / divisor,
            tile_time: self.tile_time / divisor,
        }
    }
}

bitflags! {
    struct FramebufferFlags: u8 {
        const MASK_FRAMEBUFFER_IS_DIRTY = 0x01;
        const DEST_FRAMEBUFFER_IS_DIRTY = 0x02;
    }
}

struct TextureCache<D> where D: Device {
    textures: Vec<D::Texture>,
}

impl<D> TextureCache<D> where D: Device {
    fn new() -> TextureCache<D> {
        TextureCache { textures: vec![] }
    }

    fn create_texture(&mut self, device: &mut D, format: TextureFormat, size: Vector2I)
                      -> D::Texture {
        for index in 0..self.textures.len() {
            if device.texture_size(&self.textures[index]) == size &&
                    device.texture_format(&self.textures[index]) == format {
                return self.textures.remove(index);
            }
        }

        device.create_texture(format, size)
    }

    fn release_texture(&mut self, texture: D::Texture) {
        if self.textures.len() == TEXTURE_CACHE_SIZE {
            self.textures.pop();
        }
        self.textures.insert(0, texture);
    }
}

struct TexturePage<D> where D: Device {
    framebuffer: D::Framebuffer,
    must_preserve_contents: bool,
}

struct RenderTargetInfo {
    location: TextureLocation,
}

trait ToBlendState {
    fn to_blend_state(self) -> Option<BlendState>;
}

impl ToBlendState for BlendMode {
    fn to_blend_state(self) -> Option<BlendState> {
        match self {
            BlendMode::Clear => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::Zero,
                    dest_rgb_factor: BlendFactor::Zero,
                    src_alpha_factor: BlendFactor::Zero,
                    dest_alpha_factor: BlendFactor::Zero,
                    ..BlendState::default()
                })
            }
            BlendMode::SrcOver => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::One,
                    dest_rgb_factor: BlendFactor::OneMinusSrcAlpha,
                    src_alpha_factor: BlendFactor::One,
                    dest_alpha_factor: BlendFactor::OneMinusSrcAlpha,
                    ..BlendState::default()
                })
            }
            BlendMode::DestOver => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::OneMinusDestAlpha,
                    dest_rgb_factor: BlendFactor::One,
                    src_alpha_factor: BlendFactor::OneMinusDestAlpha,
                    dest_alpha_factor: BlendFactor::One,
                    ..BlendState::default()
                })
            }
            BlendMode::SrcIn => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::DestAlpha,
                    dest_rgb_factor: BlendFactor::Zero,
                    src_alpha_factor: BlendFactor::DestAlpha,
                    dest_alpha_factor: BlendFactor::Zero,
                    ..BlendState::default()
                })
            }
            BlendMode::DestIn => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::Zero,
                    dest_rgb_factor: BlendFactor::SrcAlpha,
                    src_alpha_factor: BlendFactor::Zero,
                    dest_alpha_factor: BlendFactor::SrcAlpha,
                    ..BlendState::default()
                })
            }
            BlendMode::SrcOut => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::OneMinusDestAlpha,
                    dest_rgb_factor: BlendFactor::Zero,
                    src_alpha_factor: BlendFactor::OneMinusDestAlpha,
                    dest_alpha_factor: BlendFactor::Zero,
                    ..BlendState::default()
                })
            }
            BlendMode::DestOut => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::Zero,
                    dest_rgb_factor: BlendFactor::OneMinusSrcAlpha,
                    src_alpha_factor: BlendFactor::Zero,
                    dest_alpha_factor: BlendFactor::OneMinusSrcAlpha,
                    ..BlendState::default()
                })
            }
            BlendMode::SrcAtop => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::DestAlpha,
                    dest_rgb_factor: BlendFactor::OneMinusSrcAlpha,
                    src_alpha_factor: BlendFactor::DestAlpha,
                    dest_alpha_factor: BlendFactor::OneMinusSrcAlpha,
                    ..BlendState::default()
                })
            }
            BlendMode::DestAtop => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::OneMinusDestAlpha,
                    dest_rgb_factor: BlendFactor::SrcAlpha,
                    src_alpha_factor: BlendFactor::OneMinusDestAlpha,
                    dest_alpha_factor: BlendFactor::SrcAlpha,
                    ..BlendState::default()
                })
            }
            BlendMode::Xor => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::OneMinusDestAlpha,
                    dest_rgb_factor: BlendFactor::OneMinusSrcAlpha,
                    src_alpha_factor: BlendFactor::OneMinusDestAlpha,
                    dest_alpha_factor: BlendFactor::OneMinusSrcAlpha,
                    ..BlendState::default()
                })
            }
            BlendMode::Lighter => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::One,
                    dest_rgb_factor: BlendFactor::One,
                    src_alpha_factor: BlendFactor::One,
                    dest_alpha_factor: BlendFactor::One,
                    ..BlendState::default()
                })
            }
            BlendMode::Copy |
            BlendMode::Darken |
            BlendMode::Lighten |
            BlendMode::Multiply |
            BlendMode::Screen |
            BlendMode::HardLight |
            BlendMode::Overlay |
            BlendMode::ColorDodge |
            BlendMode::ColorBurn |
            BlendMode::SoftLight |
            BlendMode::Difference |
            BlendMode::Exclusion |
            BlendMode::Hue |
            BlendMode::Saturation |
            BlendMode::Color |
            BlendMode::Luminosity => {
                // Blending is done manually in the shader.
                None
            }
        }
    }
}

pub trait BlendModeExt {
    fn needs_readable_framebuffer(self) -> bool;
}

impl BlendModeExt for BlendMode {
    fn needs_readable_framebuffer(self) -> bool {
        match self {
            BlendMode::Clear |
            BlendMode::SrcOver |
            BlendMode::DestOver |
            BlendMode::SrcIn |
            BlendMode::DestIn |
            BlendMode::SrcOut |
            BlendMode::DestOut |
            BlendMode::SrcAtop |
            BlendMode::DestAtop |
            BlendMode::Xor |
            BlendMode::Lighter |
            BlendMode::Copy => false,
            BlendMode::Lighten |
            BlendMode::Darken |
            BlendMode::Multiply |
            BlendMode::Screen |
            BlendMode::HardLight |
            BlendMode::Overlay |
            BlendMode::ColorDodge |
            BlendMode::ColorBurn |
            BlendMode::SoftLight |
            BlendMode::Difference |
            BlendMode::Exclusion |
            BlendMode::Hue |
            BlendMode::Saturation |
            BlendMode::Color |
            BlendMode::Luminosity => true,
        }
    }
}

bitflags! {
    struct RendererFlags: u8 {
        // Whether we need a depth buffer.
        const USE_DEPTH = 0x01;
        // Whether an intermediate destination framebuffer is needed.
        //
        // This will be true if any exotic blend modes are used at the top level (not inside a
        // render target), *and* the output framebuffer is the default framebuffer.
        const INTERMEDIATE_DEST_FRAMEBUFFER_NEEDED = 0x02;
    }
}

trait ToCompositeCtrl {
    fn to_composite_ctrl(&self) -> i32;
}

impl ToCompositeCtrl for BlendMode {
    fn to_composite_ctrl(&self) -> i32 {
        match *self {
            BlendMode::SrcOver |
            BlendMode::SrcAtop |
            BlendMode::DestOver |
            BlendMode::DestOut |
            BlendMode::Xor |
            BlendMode::Lighter |
            BlendMode::Clear |
            BlendMode::Copy |
            BlendMode::SrcIn |
            BlendMode::SrcOut |
            BlendMode::DestIn |
            BlendMode::DestAtop => COMBINER_CTRL_COMPOSITE_NORMAL,
            BlendMode::Multiply => COMBINER_CTRL_COMPOSITE_MULTIPLY,
            BlendMode::Darken => COMBINER_CTRL_COMPOSITE_DARKEN,
            BlendMode::Lighten => COMBINER_CTRL_COMPOSITE_LIGHTEN,
            BlendMode::Screen => COMBINER_CTRL_COMPOSITE_SCREEN,
            BlendMode::Overlay => COMBINER_CTRL_COMPOSITE_OVERLAY,
            BlendMode::ColorDodge => COMBINER_CTRL_COMPOSITE_COLOR_DODGE,
            BlendMode::ColorBurn => COMBINER_CTRL_COMPOSITE_COLOR_BURN,
            BlendMode::HardLight => COMBINER_CTRL_COMPOSITE_HARD_LIGHT,
            BlendMode::SoftLight => COMBINER_CTRL_COMPOSITE_SOFT_LIGHT,
            BlendMode::Difference => COMBINER_CTRL_COMPOSITE_DIFFERENCE,
            BlendMode::Exclusion => COMBINER_CTRL_COMPOSITE_EXCLUSION,
            BlendMode::Hue => COMBINER_CTRL_COMPOSITE_HUE,
            BlendMode::Saturation => COMBINER_CTRL_COMPOSITE_SATURATION,
            BlendMode::Color => COMBINER_CTRL_COMPOSITE_COLOR,
            BlendMode::Luminosity => COMBINER_CTRL_COMPOSITE_LUMINOSITY,
        }
    }
}

trait ToCombineMode {
    fn to_combine_mode(self) -> i32;
}

impl ToCombineMode for PaintCompositeOp {
    fn to_combine_mode(self) -> i32 {
        match self {
            PaintCompositeOp::DestIn => COMBINER_CTRL_COLOR_COMBINE_DEST_IN,
            PaintCompositeOp::SrcIn => COMBINER_CTRL_COLOR_COMBINE_SRC_IN,
        }
    }
}

fn pixel_size_to_tile_size(pixel_size: Vector2I) -> Vector2I {
    // Round up.
    let tile_size = vec2i(TILE_WIDTH as i32 - 1, TILE_HEIGHT as i32 - 1);
    let size = pixel_size + tile_size;
    vec2i(size.x() / TILE_WIDTH as i32, size.y() / TILE_HEIGHT as i32)
}

#[derive(Clone, Copy)]
struct ClipStorageIDs {
    metadata: Option<StorageID>,
    tiles: StorageID,
    vertices: StorageID,
}

#[derive(Clone)]
struct FillRasterStorageInfo {
    fill_storage_id: StorageID,
    fill_count: u32,
}

#[derive(Clone)]
struct FillComputeStorageInfo {
    fill_storage_id: StorageID,
    tile_link_map_storage_id: StorageID,
    fill_tile_count: u32,
    first_fill_tile: u32,
}

#[derive(Clone)]
enum FillStorageInfo {
    Raster(FillRasterStorageInfo),
    Compute(FillComputeStorageInfo),
}

#[derive(Clone, Copy)]
enum PrimitiveCount {
    Direct(u32),
    Indirect,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(C)]
struct TileLinks {
    next_fill: u32,
    next_alpha_tile: u32,
}
