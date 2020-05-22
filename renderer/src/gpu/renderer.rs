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
use crate::gpu::options::{DestFramebuffer, RendererOptions};
use crate::gpu::shaders::{BlitBufferProgram, BlitBufferVertexArray, BlitProgram, BlitVertexArray, ClearProgram, ClearVertexArray};
use crate::gpu::shaders::{ClipTileCombineProgram, ClipTileCombineVertexArray, ClipTileCopyProgram, ClipTileCopyVertexArray};
use crate::gpu::shaders::{CopyTileProgram, CopyTileVertexArray, FillProgram, FillVertexArray};
use crate::gpu::shaders::{GenerateClipProgram, MAX_FILLS_PER_BATCH, PropagateProgram, ReprojectionProgram};
use crate::gpu::shaders::{ReprojectionVertexArray, StencilProgram, StencilVertexArray};
use crate::gpu::shaders::{TileProgram, TileVertexArray};
use crate::gpu_data::{Clip, ClipBatchKey, ClipBatchKind, Fill, PathIndex, PrepareTilesBatch, PropagateMetadata, RenderCommand};
use crate::gpu_data::{TextureLocation, TextureMetadataEntry, TexturePageDescriptor, TexturePageId};
use crate::gpu_data::{TileBatchId, TileBatchTexture, TileObjectPrimitive};
use crate::options::BoundingQuad;
use crate::paint::PaintCompositeOp;
use crate::tiles::{TILE_HEIGHT, TILE_WIDTH};
use fxhash::FxHashMap;
use half::f16;
use pathfinder_color::{self as color, ColorF, ColorU};
use pathfinder_content::effects::{BlendMode, BlurDirection, DefringingKernel};
use pathfinder_content::effects::{Filter, PatternFilter};
use pathfinder_content::render_target::RenderTargetId;
use pathfinder_geometry::line_segment::LineSegment2F;
use pathfinder_geometry::rect::RectI;
use pathfinder_geometry::transform3d::Transform4F;
use pathfinder_geometry::util;
use pathfinder_geometry::vector::{Vector2F, Vector2I, Vector4F, vec2f, vec2i};
use pathfinder_gpu::{BlendFactor, BlendOp, BlendState, BufferData, BufferTarget, BufferUploadMode};
use pathfinder_gpu::{ClearOps, ComputeDimensions, ComputeState, DepthFunc, DepthState, Device};
use pathfinder_gpu::{ImageAccess, Primitive, RenderOptions, RenderState, RenderTarget};
use pathfinder_gpu::{StencilFunc, StencilState, TextureBinding, TextureDataRef, TextureFormat};
use pathfinder_gpu::{TextureSamplingFlags, UniformBinding, UniformData};
use pathfinder_resources::ResourceLoader;
use pathfinder_simd::default::{F32x2, F32x4, I32x2};
use std::collections::VecDeque;
use std::f32;
use std::marker::PhantomData;
use std::mem;
use std::ops::{Add, Div};
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

const MIN_FILL_STORAGE_CLASS:                    usize = 14;    // 16K entries, 128kB
const MIN_FILL_TILE_MAP_STORAGE_CLASS:           usize = 15;    // 32K entries, 128kB
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
    blit_buffer_program: BlitBufferProgram<D>,
    clear_program: ClearProgram<D>,
    fill_program: FillProgram<D>,
    tile_program: TileProgram<D>,
    tile_copy_program: CopyTileProgram<D>,
    tile_clip_combine_program: ClipTileCombineProgram<D>,
    tile_clip_copy_program: ClipTileCopyProgram<D>,
    generate_clip_program: GenerateClipProgram<D>,
    stencil_program: StencilProgram<D>,
    reprojection_program: ReprojectionProgram<D>,
    propagate_program: PropagateProgram<D>,
    quad_vertex_positions_buffer: D::Buffer,
    quad_vertex_indices_buffer: D::Buffer,
    fill_tile_map: Vec<i32>,
    texture_pages: Vec<Option<TexturePage<D>>>,
    render_targets: Vec<RenderTargetInfo>,
    render_target_stack: Vec<RenderTargetId>,
    area_lut_texture: D::Texture,
    gamma_lut_texture: D::Texture,

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
    fill_vertex_storage_allocator: StorageAllocator<D, FillVertexStorage<D>>,
    fill_tile_map_storage_allocator: StorageAllocator<D, D::Buffer>,  
    tile_vertex_storage_allocator: StorageAllocator<D, TileVertexStorage<D>>,
    tile_propagate_metadata_storage_allocator: StorageAllocator<D, D::Buffer>,
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
        let generate_clip_program = GenerateClipProgram::new(&device, resources);
        let stencil_program = StencilProgram::new(&device, resources);
        let reprojection_program = ReprojectionProgram::new(&device, resources);
        let propagate_program = PropagateProgram::new(&device, resources);

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

        let window_size = dest_framebuffer.window_size(&device);

        let timer_query_cache = TimerQueryCache::new(&device);
        let debug_ui_presenter = DebugUIPresenter::new(&device, resources, window_size);

        let front_frame = Frame::new(&device,
                                     &blit_program,
                                     &blit_buffer_program,
                                     &clear_program,
                                     &tile_clip_combine_program,
                                     &tile_clip_copy_program,
                                     &reprojection_program,
                                     &stencil_program,
                                     &quad_vertex_positions_buffer,
                                     &quad_vertex_indices_buffer,
                                     window_size);
        let back_frame = Frame::new(&device,
                                    &blit_program,
                                    &blit_buffer_program,
                                    &clear_program,
                                    &tile_clip_combine_program,
                                    &tile_clip_copy_program,
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
            blit_buffer_program,
            clear_program,
            fill_program,
            tile_program,
            tile_copy_program,
            tile_clip_combine_program,
            tile_clip_copy_program,
            generate_clip_program,
            propagate_program,
            quad_vertex_positions_buffer,
            quad_vertex_indices_buffer,
            fill_tile_map: vec![],
            texture_pages: vec![],
            render_targets: vec![],
            render_target_stack: vec![],

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

    pub fn begin_scene(&mut self) {
        self.back_frame.framebuffer_flags = FramebufferFlags::empty();

        self.device.begin_commands();
        self.current_timer = Some(PendingTimer::new());
        self.stats = RenderStats::default();

        let framebuffer_tile_size = self.framebuffer_tile_size();
        let z_buffer_length = framebuffer_tile_size.x() as usize *
            framebuffer_tile_size.y() as usize;
        let mut z_buffer_data = vec![0; z_buffer_length];
        self.device.upload_to_buffer::<i32>(&self.back_frame.z_buffer,
                                            0,
                                            &z_buffer_data,
                                            BufferTarget::Storage);

        self.back_frame.max_alpha_tile_index = 0;
    }

    pub fn render_command(&mut self, command: &RenderCommand) {
        println!("render command: {:?}", command);
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
            RenderCommand::BeginTileDrawing => {}
            RenderCommand::PushRenderTarget(render_target_id) => {
                self.push_render_target(render_target_id)
            }
            RenderCommand::PopRenderTarget => self.pop_render_target(),
            RenderCommand::PrepareTiles(ref batch) => self.prepare_tiles(batch),
            RenderCommand::DrawTiles(ref batch) => {
                let batch_info = self.back_frame.tile_batch_info[batch.tile_batch_id.0 as usize];
                self.draw_tiles(batch_info.tile_count,
                                batch_info.tile_vertex_storage_id,
                                batch.color_texture,
                                batch.blend_mode,
                                batch.filter)
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

        self.back_frame.fill_vertex_storage_allocator.end_frame();
        self.back_frame.fill_tile_map_storage_allocator.end_frame();
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
        let alpha_tile_pages_needed =
            ((self.back_frame.max_alpha_tile_index + 0xffff) >> 16) as u32;
        if alpha_tile_pages_needed <= self.back_frame.allocated_alpha_tile_page_count {
            return;
        }

        let new_size = vec2i(MASK_FRAMEBUFFER_WIDTH,
                             MASK_FRAMEBUFFER_HEIGHT * alpha_tile_pages_needed as i32);
        let mask_texture = self.device.create_texture(TextureFormat::RGBA16F, new_size);
        self.back_frame.mask_framebuffer = Some(self.device.create_framebuffer(mask_texture));
        self.back_frame.allocated_alpha_tile_page_count = alpha_tile_pages_needed;

        // TODO(pcwalton): Copy over existing content if needed!
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

    fn upload_tiles(&mut self, tiles: &[TileObjectPrimitive]) -> StorageID {
        //debug_assert!(tiles.len() <= MAX_TILES_PER_BATCH);

        let tile_program = &self.tile_program;
        let tile_copy_program = &self.tile_copy_program;
        let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
        let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
        let storage_id = self.back_frame.tile_vertex_storage_allocator.allocate(&self.device,
                                                                                tiles.len() as u64,
                                                                                |device, size| {
            TileVertexStorage::new(size,
                                   device,
                                   tile_program,
                                   tile_copy_program,
                                   quad_vertex_positions_buffer,
                                   quad_vertex_indices_buffer)
        });

        let vertex_buffer = &self.back_frame
                                 .tile_vertex_storage_allocator
                                 .get(storage_id)
                                 .vertex_buffer;
        self.device.upload_to_buffer(vertex_buffer, 0, tiles, BufferTarget::Vertex);

        self.ensure_index_buffer(tiles.len());

        storage_id
    }

    fn upload_propagate_data(&mut self,
                             propagate_metadata: &[PropagateMetadata],
                             backdrops: &[i32])
                             -> StorageID {
        println!("propagate metadata: {:#?}", propagate_metadata);

        let device = &self.device;
        let propagate_metadata_storage_id = self.back_frame
                                                .tile_propagate_metadata_storage_allocator
                                                .allocate(device,
                                                          propagate_metadata.len() as u64,
                                                          |device, size| {
            let buffer = device.create_buffer(BufferUploadMode::Dynamic);
            device.allocate_buffer::<PropagateMetadata>(&buffer,
                                                        BufferData::Uninitialized(size as usize),
                                                        BufferTarget::Storage);
            buffer
        });

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

    fn add_fills(&mut self, fill_batch: &[Fill]) {
        if fill_batch.is_empty() {
            return;
        }

        self.stats.fill_count += fill_batch.len();

        let preserve_alpha_mask_contents = self.back_frame.max_alpha_tile_index > 0;

        self.back_frame.pending_fills.reserve(fill_batch.len());
        for fill in fill_batch {
            self.back_frame.max_alpha_tile_index =
                self.back_frame.max_alpha_tile_index.max(fill.alpha_tile_index + 1);
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
        match self.fill_program {
            FillProgram::Raster(_) => self.draw_buffered_fills_via_raster(),
            FillProgram::Compute(_) => self.draw_buffered_fills_via_compute(),
        }
    }

    fn draw_buffered_fills_via_raster(&mut self) {
        let fill_raster_program = match self.fill_program {
            FillProgram::Raster(ref fill_raster_program) => fill_raster_program,
            _ => unreachable!(),
        };

        let mask_viewport = self.mask_viewport();

        let buffered_fills = &mut self.back_frame.buffered_fills;
        if buffered_fills.is_empty() {
            return;
        }

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
                                       quad_vertex_indices_buffer)
            })
        };
        let fill_vertex_storage = self.back_frame.fill_vertex_storage_allocator.get(storage_id);

        let fill_vertex_array =
            fill_vertex_storage.vertex_array.as_ref().expect("Where's the vertex array?");

        self.device.upload_to_buffer(&fill_vertex_storage.vertex_buffer,
                                     0,
                                     &buffered_fills,
                                     BufferTarget::Vertex);

        let mut clear_color = None;
        if !self.back_frame
                .framebuffer_flags
                .contains(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY) {
            clear_color = Some(ColorF::default());
        };

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        debug_assert!(buffered_fills.len() <= u32::MAX as usize);
        self.device.draw_elements_instanced(6, buffered_fills.len() as u32, &RenderState {
            target: &RenderTarget::Framebuffer(self.back_frame.mask_framebuffer.as_ref().unwrap()),
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
            storage_buffers: &[],
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
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().fill_times.push(TimerFuture::new(timer_query));

        self.back_frame.framebuffer_flags.insert(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY);
        buffered_fills.clear();
    }

    fn draw_buffered_fills_via_compute(&mut self) {
        let fill_compute_program = match self.fill_program {
            FillProgram::Compute(ref fill_compute_program) => fill_compute_program,
            _ => unreachable!(),
        };

        let buffered_fills = &mut self.back_frame.buffered_fills;
        if buffered_fills.is_empty() {
            return;
        }

        // Allocate buffered fill buffer.
        let fill_vertex_storage_id = {
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
                                       quad_vertex_indices_buffer)
            })
        };
        let fill_vertex_storage = self.back_frame
                                      .fill_vertex_storage_allocator
                                      .get(fill_vertex_storage_id);

        // Initialize the tile map.
        self.fill_tile_map.clear();

        // Create a linked list running through all our fills.
        let (mut first_fill_tile, mut last_fill_tile) = (u32::MAX, 0);
        for (fill_index, fill) in buffered_fills.iter_mut().enumerate() {
            let fill_tile_index = fill.alpha_tile_index as usize;
            while fill_tile_index >= self.fill_tile_map.len() {
                self.fill_tile_map.push(-1);
            }
            fill.alpha_tile_index = self.fill_tile_map[fill_tile_index] as u32;
            self.fill_tile_map[fill_tile_index] = fill_index as i32;
            first_fill_tile = first_fill_tile.min(fill_tile_index as u32);
            last_fill_tile = last_fill_tile.max(fill_tile_index as u32);
        }
        let fill_tile_count = last_fill_tile - first_fill_tile + 1;

        // Allocate fill tile map.
        let fill_map_storage_id =
            self.back_frame.fill_tile_map_storage_allocator.allocate(&self.device,
                                                                     last_fill_tile as u64,
                                                                     |device, size| {
                let buffer = device.create_buffer(BufferUploadMode::Dynamic);
                device.allocate_buffer::<i32>(&buffer,
                                              BufferData::Uninitialized(size as usize),
                                              BufferTarget::Storage);
                buffer
            });
        let fill_map_buffer =
            self.back_frame.fill_tile_map_storage_allocator.get(fill_map_storage_id);

        self.device.upload_to_buffer(&fill_vertex_storage.vertex_buffer,
                                     0,
                                     &buffered_fills,
                                     BufferTarget::Storage);
        self.device.upload_to_buffer(fill_map_buffer,
                                     0,
                                     &self.fill_tile_map,
                                     BufferTarget::Storage);

        let mask_framebuffer = self.back_frame
                                   .mask_framebuffer
                                   .as_ref()
                                   .expect("Where's the mask framebuffer?");
        let image_texture = self.device.framebuffer_texture(mask_framebuffer);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        debug_assert!(buffered_fills.len() <= u32::MAX as usize);
        let dimensions = ComputeDimensions { x: 1, y: 1, z: fill_tile_count as u32 };
        self.device.dispatch_compute(dimensions, &ComputeState {
            program: &fill_compute_program.program,
            textures: &[(&fill_compute_program.area_lut_texture, &self.area_lut_texture)],
            images: &[(&fill_compute_program.dest_image, image_texture, ImageAccess::Write)],
            uniforms: &[
                (&fill_compute_program.first_tile_index_uniform,
                 UniformData::Int(first_fill_tile as i32)),
            ],
            storage_buffers: &[
                (&fill_compute_program.fills_storage_buffer, &fill_vertex_storage.vertex_buffer),
                (&fill_compute_program.fill_tile_map_storage_buffer, fill_map_buffer),
            ],
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().fill_times.push(TimerFuture::new(timer_query));

        self.back_frame.framebuffer_flags.insert(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY);
        buffered_fills.clear();
    }

    fn clip_tiles(&mut self,
                  clip_storage_id: StorageID,
                  tile_storage_id: StorageID,
                  max_clipped_tile_count: u32) {
        // FIXME(pcwalton): Recycle these.
        let mask_framebuffer = self.back_frame
                                   .mask_framebuffer
                                   .as_ref()
                                   .expect("Where's the mask framebuffer?");
        let mask_texture = self.device.framebuffer_texture(mask_framebuffer);
        let mask_texture_size = self.device.texture_size(&mask_texture);
        let temp_texture = self.device.create_texture(TextureFormat::RGBA16F, mask_texture_size);
        let temp_framebuffer = self.device.create_framebuffer(temp_texture);

        println!("mask_texture_size={:?} mask_clipped_tile_count={}",
                 mask_texture_size,
                 max_clipped_tile_count);

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

        /*

        self.device.allocate_buffer(&self.back_frame.tile_clip_vertex_array.vertex_buffer,
                                    BufferData::Memory(&batch.clips),
                                    BufferTarget::Vertex);

        if !self.back_frame.alpha_tile_pages.contains_key(&dest_page) {
            let alpha_tile_page = AlphaTilePage::new(&mut self.device);
            self.back_frame.alpha_tile_pages.insert(dest_page, alpha_tile_page);
        }

        let mut clear_color = None;
        if !self.back_frame.alpha_tile_pages[&dest_page].framebuffer_is_dirty {
            clear_color = Some(ColorF::default());
        };

        let blend = match kind {
            ClipBatchKind::Draw => None,
            ClipBatchKind::Clip => {
                Some(BlendState {
                    src_rgb_factor: BlendFactor::One,
                    src_alpha_factor: BlendFactor::One,
                    dest_rgb_factor: BlendFactor::One,
                    dest_alpha_factor: BlendFactor::One,
                    op: BlendOp::Min,
                })
            }
        };

        let mask_viewport = self.mask_viewport();

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        {
            let dest_framebuffer = &self.back_frame.alpha_tile_pages[&dest_page].framebuffer;
            let src_framebuffer = &self.back_frame.alpha_tile_pages[&src_page].framebuffer;
            let src_texture = self.device.framebuffer_texture(&src_framebuffer);

            debug_assert!(batch.clips.len() <= u32::MAX as usize);
            self.device.draw_elements_instanced(6, batch.clips.len() as u32, &RenderState {
                target: &RenderTarget::Framebuffer(dest_framebuffer),
                program: &self.tile_clip_program.program,
                vertex_array: &self.back_frame.tile_clip_vertex_array.vertex_array,
                primitive: Primitive::Triangles,
                textures: &[(&self.tile_clip_program.src_texture, src_texture)],
                images: &[],
                uniforms: &[],
                viewport: mask_viewport,
                options: RenderOptions {
                    blend,
                    clear_ops: ClearOps { color: clear_color, ..ClearOps::default() },
                    ..RenderOptions::default()
                },
            });

            self.device.end_timer_query(&timer_query);
            self.current_timer.as_mut().unwrap().fill_times.push(TimerFuture::new(timer_query));
        }

        self.back_frame.framebuffer_flags.insert(FramebufferFlags::MASK_FRAMEBUFFER_IS_DIRTY);
        */
    }

    fn prepare_tiles(&mut self, batch: &PrepareTilesBatch) {
        let count = batch.tiles.len();
        self.stats.alpha_tile_count += count;
        let tile_vertex_storage_id = self.upload_tiles(&batch.tiles);
        let propagate_metadata_storage_id = self.upload_propagate_data(&batch.propagate_metadata,
                                                                       &batch.backdrops);
        self.propagate_tiles(batch.propagate_metadata.len() as u32,
                             tile_vertex_storage_id,
                             propagate_metadata_storage_id);

        // TODO(pcwalton): Z-buffering.

        self.back_frame.tile_batch_info.insert(batch.batch_id.0 as usize, TileBatchInfo {
            tile_count: batch.tiles.len() as u32,
            tile_vertex_storage_id,
            propagate_metadata_storage_id,
        });

        // Perform clipping if necessary.
        if let Some(ref clipped_path_info) = batch.clipped_path_info {
            let clip_storage_id =
                self.prepare_clip_tiles(tile_vertex_storage_id,
                                        propagate_metadata_storage_id,
                                        clipped_path_info.clip_batch_id,
                                        &clipped_path_info.clipped_paths,
                                        clipped_path_info.max_clipped_tile_count);
            self.clip_tiles(clip_storage_id,
                            tile_vertex_storage_id,
                            clipped_path_info.max_clipped_tile_count);
        }
    }

    fn tile_transform(&self) -> Transform4F {
        let draw_viewport = self.draw_viewport().size().to_f32();
        let scale = Vector4F::new(2.0 / draw_viewport.x(), -2.0 / draw_viewport.y(), 1.0, 1.0);
        Transform4F::from_scale(scale).translate(Vector4F::new(-1.0, 1.0, 0.0, 1.0))
    }

    fn propagate_tiles(&mut self,
                       path_count: u32,
                       tile_storage_id: StorageID,
                       propagate_metadata_storage_id: StorageID) {
        let alpha_tile_buffer = &self.back_frame
                                     .tile_vertex_storage_allocator
                                     .get(tile_storage_id)
                                     .vertex_buffer;
        let propagate_metadata_storage_buffer = &self.back_frame
                                                     .tile_propagate_metadata_storage_allocator
                                                     .get(propagate_metadata_storage_id);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let dimensions = ComputeDimensions { x: 1, y: path_count, z: 1 };
        self.device.dispatch_compute(dimensions, &ComputeState {
            program: &self.propagate_program.program,
            textures: &[],
            images: &[],
            uniforms: &[
                (&self.propagate_program.framebuffer_tile_size_uniform,
                 UniformData::IVec2(self.framebuffer_tile_size().0)),
            ],
            storage_buffers: &[
                (&self.propagate_program.metadata_storage_buffer,
                 propagate_metadata_storage_buffer),
                (&self.propagate_program.backdrops_storage_buffer,
                 &self.back_frame.backdrops_buffer),
                (&self.propagate_program.alpha_tiles_storage_buffer, alpha_tile_buffer),
                (&self.propagate_program.z_buffer_storage_buffer,
                 &self.back_frame.z_buffer),
            ],
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().propagate_times.push(TimerFuture::new(timer_query));
    }

    fn prepare_z_buffer(&mut self) {
        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let z_buffer_size = self.framebuffer_tile_size();

        self.device.draw_elements(6, &RenderState {
            target: &RenderTarget::Framebuffer(&self.back_frame.z_buffer_framebuffer),
            program: &self.blit_buffer_program.program,
            vertex_array: &self.back_frame.blit_buffer_vertex_array.vertex_array,
            primitive: Primitive::Triangles,
            textures: &[],
            images: &[],
            storage_buffers: &[
                (&self.blit_buffer_program.buffer_storage_buffer, &self.back_frame.z_buffer),
            ],
            uniforms: &[
                (&self.blit_buffer_program.buffer_size_uniform,
                 UniformData::IVec2(z_buffer_size.0)),
                 
            ],
            viewport: RectI::new(Vector2I::zero(), z_buffer_size),
            options: RenderOptions::default(),
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().propagate_times.push(TimerFuture::new(timer_query));
    }

    fn prepare_clip_tiles(&mut self,
                          tile_storage_id: StorageID,
                          tile_propagate_metadata_storage_id: StorageID,
                          clip_batch_id: TileBatchId,
                          clipped_paths: &[PathIndex],
                          max_clipped_tile_count: u32)
                          -> StorageID {
        let clip_tile_batch_info = self.back_frame.tile_batch_info[clip_batch_id.0 as usize];
        let clip_propagate_metadata_storage_id =
            clip_tile_batch_info.propagate_metadata_storage_id;
        let clip_tile_vertex_storage_id = clip_tile_batch_info.tile_vertex_storage_id;

        let tile_propagate_metadata_buffer = self.back_frame
                                                 .tile_propagate_metadata_storage_allocator
                                                 .get(tile_propagate_metadata_storage_id);
        let clip_propagate_metadata_buffer = self.back_frame
                                                 .tile_propagate_metadata_storage_allocator
                                                 .get(clip_propagate_metadata_storage_id);

        // Allocate paths.
        // FIXME(pcwalton): Reuse buffers.
        let clipped_path_indices_buffer = self.device.create_buffer(BufferUploadMode::Dynamic);
        self.device.allocate_buffer::<PathIndex>(&clipped_path_indices_buffer,
                                                 BufferData::Memory(clipped_paths),
                                                 BufferTarget::Storage);
        println!("clipped path indices={:?}", clipped_paths);

        let alpha_tile_buffer = &self.back_frame
                                     .tile_vertex_storage_allocator
                                     .get(tile_storage_id)
                                     .vertex_buffer;
        let clip_tile_buffer = &self.back_frame
                                    .tile_vertex_storage_allocator
                                    .get(clip_tile_vertex_storage_id)
                                    .vertex_buffer;

        // Allocate vertex buffer.
        let tile_clip_combine_program = &self.tile_clip_combine_program;
        let tile_clip_copy_program = &self.tile_clip_copy_program;
        let quad_vertex_positions_buffer = &self.quad_vertex_positions_buffer;
        let quad_vertex_indices_buffer = &self.quad_vertex_indices_buffer;
        let clip_storage_id =
            self.back_frame.clip_vertex_storage_allocator.allocate(&self.device,
                                                                   max_clipped_tile_count as u64,
                                                                   |device, size| {
            ClipVertexStorage::new(size,
                                   device,
                                   tile_clip_combine_program,
                                   tile_clip_copy_program,
                                   quad_vertex_positions_buffer,
                                   quad_vertex_indices_buffer)
        });

        let clip_vertex_storage = self.back_frame
                                      .clip_vertex_storage_allocator
                                      .get(clip_storage_id);


        let initial_clip_vertex_buffer = vec![Clip::default(); max_clipped_tile_count as usize];
        self.device.upload_to_buffer(&clip_vertex_storage.vertex_buffer,
                                     0,
                                     &initial_clip_vertex_buffer,
                                     BufferTarget::Vertex);

        let timer_query = self.timer_query_cache.alloc(&self.device);
        self.device.begin_timer_query(&timer_query);

        let viewport_size = self.main_viewport().size();
        let dimensions = viewport_size + Vector2I::splat(255);
        let dimensions = ComputeDimensions {
            x: dimensions.x() as u32 / 256,
            y: dimensions.y() as u32 / 256,
            z: clipped_paths.len() as u32,
        };

        self.device.dispatch_compute(dimensions, &ComputeState {
            program: &self.generate_clip_program.program,
            textures: &[],
            images: &[],
            uniforms: &[],
            storage_buffers: &[
                (&self.generate_clip_program.clipped_path_indices_storage_buffer,
                 &clipped_path_indices_buffer),
                (&self.generate_clip_program.draw_propagate_metadata_storage_buffer,
                 tile_propagate_metadata_buffer),
                (&self.generate_clip_program.clip_propagate_metadata_storage_buffer,
                 clip_propagate_metadata_buffer),
                (&self.generate_clip_program.draw_tiles_storage_buffer, alpha_tile_buffer),
                (&self.generate_clip_program.clip_tiles_storage_buffer, clip_tile_buffer),
                (&self.generate_clip_program.clip_vertex_storage_buffer,
                 &clip_vertex_storage.vertex_buffer),
            ],
        });

        self.device.end_timer_query(&timer_query);
        self.current_timer.as_mut().unwrap().propagate_times.push(TimerFuture::new(timer_query));

        clip_storage_id
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
            uniforms: &[],
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
           tile_clip_combine_program: &ClipTileCombineProgram<D>,
           tile_clip_copy_program: &ClipTileCopyProgram<D>,
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

        let fill_vertex_storage_allocator = StorageAllocator::new(MIN_FILL_STORAGE_CLASS);
        let fill_tile_map_storage_allocator =
            StorageAllocator::new(MIN_FILL_TILE_MAP_STORAGE_CLASS);
        let tile_vertex_storage_allocator = StorageAllocator::new(MIN_TILE_STORAGE_CLASS);
        let tile_propagate_metadata_storage_allocator =
            StorageAllocator::new(MIN_TILE_PROPAGATE_METADATA_STORAGE_CLASS);
        let clip_vertex_storage_allocator = StorageAllocator::new(MIN_CLIP_VERTEX_STORAGE_CLASS);

        let texture_metadata_texture_size = vec2i(TEXTURE_METADATA_TEXTURE_WIDTH,
                                                  TEXTURE_METADATA_TEXTURE_HEIGHT);
        let texture_metadata_texture = device.create_texture(TextureFormat::RGBA16F,
                                                             texture_metadata_texture_size);

        let intermediate_dest_texture = device.create_texture(TextureFormat::RGBA8, window_size);
        let intermediate_dest_framebuffer = device.create_framebuffer(intermediate_dest_texture);

        let dest_blend_texture = device.create_texture(TextureFormat::RGBA8, window_size);
        let dest_blend_framebuffer = device.create_framebuffer(dest_blend_texture);

        let propagate_metadata_buffer = device.create_buffer(BufferUploadMode::Dynamic);
        let backdrops_buffer = device.create_buffer(BufferUploadMode::Dynamic);

        let framebuffer_tile_size = pixel_size_to_tile_size(window_size);
        let z_buffer_texture = device.create_texture(TextureFormat::R32I, framebuffer_tile_size);
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

        Frame {
            blit_vertex_array,
            blit_buffer_vertex_array,
            clear_vertex_array,
            tile_vertex_storage_allocator,
            fill_vertex_storage_allocator,
            fill_tile_map_storage_allocator,
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
    propagate_metadata_storage_id: StorageID,
}

// Buffer management

struct StorageAllocator<D, S> where D: Device {
    buckets: Vec<StorageAllocatorBucket<S>>,
    min_size_class: usize,
    phantom: PhantomData<D>,
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

struct FillVertexStorage<D> where D: Device {
    vertex_buffer: D::Buffer,
    // Will be `None` if we're using compute.
    vertex_array: Option<FillVertexArray<D>>,
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

impl<D> FillVertexStorage<D> where D: Device {
    fn new(size: u64,
           device: &D,
           fill_program: &FillProgram<D>,
           quad_vertex_positions_buffer: &D::Buffer,
           quad_vertex_indices_buffer: &D::Buffer)
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

        FillVertexStorage { vertex_buffer, vertex_array }
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
        PendingTimer { fill_times: vec![], propagate_times: vec![], tile_times: vec![] }
    }

    fn poll(&mut self, device: &D) -> Vec<D::TimerQuery> {
        let mut old_queries = vec![];
        for future in self.fill_times.iter_mut().chain(self.propagate_times.iter_mut())
                                                .chain(self.tile_times.iter_mut()) {
            if let Some(old_query) = future.poll(device) {
                old_queries.push(old_query)
            }
        }
        old_queries
    }

    fn total_time(&self) -> Option<RenderTime> {
        let fill_time = total_time_of_timer_futures(&self.fill_times);
        let propagate_time = total_time_of_timer_futures(&self.propagate_times);
        let tile_time = total_time_of_timer_futures(&self.tile_times);
        match (fill_time, propagate_time, tile_time) {
            (Some(fill_time), Some(propagate_time), Some(tile_time)) => {
                Some(RenderTime { fill_time, propagate_time, tile_time })
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
    pub fill_time: Duration,
    pub propagate_time: Duration,
    pub tile_time: Duration,
}

impl Default for RenderTime {
    #[inline]
    fn default() -> RenderTime {
        RenderTime {
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
    let tile_size = vec2i(TILE_WIDTH as i32, TILE_HEIGHT as i32);
    let size = pixel_size + tile_size;
    vec2i(size.x() / TILE_WIDTH as i32, size.y() / TILE_HEIGHT as i32)
}
