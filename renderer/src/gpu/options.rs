// pathfinder/renderer/src/gpu/options.rs
//
// Copyright © 2019 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

use pathfinder_color::ColorF;
use pathfinder_geometry::rect::RectI;
use pathfinder_geometry::vector::Vector2I;
use pathfinder_gpu::Device;

/// Options that influence rendering.
pub struct RendererOptions {
    /// The background color. If not present, transparent is assumed.
    pub background_color: Option<ColorF>,
    /// Options controlling how the renderer uses the GPU.
    pub gpu_features: RendererGPUFeatures,
}

bitflags! {
    /// Options controlling how the renderer uses the GPU.
    pub struct RendererGPUFeatures: u8 {
        /// Perform fill calculation in software using compute shader on DX11-class hardware.
        /// 
        /// If this flag is not set, or the hardware is not DX11-class, fill calculation is done
        /// with the hardware rasterizer, which is usually moderately slower.
        const FILL_IN_COMPUTE = 0x01;

        /// Perform tile preparation--backdrop computation, Z-buffering, and clipping--on the GPU,
        /// using compute shader on DX11-class hardware.
        /// 
        /// If this flag is not set, or the hardware is not DX11-class, these are done on CPU.
        /// There is usually little performance difference between the CPU and GPU here, but this
        /// flag is necessary for GPU tiling.
        const PREPARE_TILES_ON_GPU = 0x02;

        /// Perform tile assignment/binning on GPU, using Shader Storage Buffer Objects on
        /// DX11-class hardware.
        /// 
        /// If this flag is not set, or the hardware is not DX11-class, these are done on CPU.
        const BIN_ON_GPU = 0x04;
    }
}

impl Default for RendererOptions {
    #[inline]
    fn default() -> RendererOptions {
        RendererOptions {
            background_color: None,
            gpu_features: RendererGPUFeatures::all(),
        }
    }
}

#[derive(Clone)]
pub enum DestFramebuffer<D> where D: Device {
    Default {
        viewport: RectI,
        window_size: Vector2I,
    },
    Other(D::Framebuffer),
}

impl<D> Default for DestFramebuffer<D> where D: Device {
    #[inline]
    fn default() -> DestFramebuffer<D> {
        DestFramebuffer::Default { viewport: RectI::default(), window_size: Vector2I::default() }
    }
}

impl<D> DestFramebuffer<D>
where
    D: Device,
{
    #[inline]
    pub fn full_window(window_size: Vector2I) -> DestFramebuffer<D> {
        let viewport = RectI::new(Vector2I::default(), window_size);
        DestFramebuffer::Default { viewport, window_size }
    }

    #[inline]
    pub fn window_size(&self, device: &D) -> Vector2I {
        match *self {
            DestFramebuffer::Default { window_size, .. } => window_size,
            DestFramebuffer::Other(ref framebuffer) => {
                device.texture_size(device.framebuffer_texture(framebuffer))
            }
        }
    }
}
