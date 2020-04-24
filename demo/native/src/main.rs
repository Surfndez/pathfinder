// pathfinder/demo/native/src/main.rs
//
// Copyright © 2019 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

//! A demo app for Pathfinder using SDL 2.

use euclid::default::Size2D;
use gl::types::GLuint;
use gl;
use nfd::Response;
use pathfinder_demo::window::{Event, Keycode, SVGPath, View, Window, WindowSize};
use pathfinder_demo::{DemoApp, Options};
use pathfinder_geometry::rect::RectI;
use pathfinder_geometry::vector::{Vector2I, vec2i};
use pathfinder_resources::ResourceLoader;
use pathfinder_resources::fs::FilesystemResourceLoader;
use std::collections::VecDeque;
use std::path::PathBuf;
use std::ptr;
use surfman::{Adapter, Connection, Context, ContextAttributeFlags, ContextAttributes, ContextDescriptor, Device, GLApi, GLVersion as SurfmanGLVersion, Surface};
use surfman::{SurfaceAccess, SurfaceTexture, SurfaceType, declare_surfman};
use winit::{ControlFlow, ElementState, Event as WinitEvent, EventsLoop, MouseButton, Touch, VirtualKeyCode, Window as WinitWindow, WindowBuilder, WindowEvent};
use winit::dpi::{LogicalSize, PhysicalSize};

declare_surfman!();

/*
#[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
use foreign_types::ForeignTypeRef;
#[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
use metal::{CAMetalLayer, CoreAnimationLayerRef};
#[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
use pathfinder_metal::MetalDevice;
#[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
use sdl2::hint;
#[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
use sdl2::render::Canvas;
#[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
use sdl2_sys::SDL_RenderGetMetalLayer;
*/

#[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
use pathfinder_gl::{GLDevice, GLVersion};

/*
#[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
use sdl2::video::{GLContext, GLProfile};
*/

#[cfg(not(windows))]
use jemallocator;

#[cfg(not(windows))]
#[global_allocator]
static ALLOC: jemallocator::Jemalloc = jemallocator::Jemalloc;

const DEFAULT_WINDOW_WIDTH: u32 = 1067;
const DEFAULT_WINDOW_HEIGHT: u32 = 800;

fn main() {
    color_backtrace::install();
    pretty_env_logger::init();

    let window = WindowImpl::new();
    let window_size = window.size();
    let options = Options::default();
    let mut app = DemoApp::new(window, window_size, options);

    while !app.should_exit {
        let mut events = vec![];
        if !app.dirty {
            events.push(app.window.get_event());
        }
        while let Some(event) = app.window.try_get_event() {
            events.push(event);
        }

        let scene_count = app.prepare_frame(events);
        app.draw_scene();
        app.begin_compositing();
        for scene_index in 0..scene_count {
            app.composite_scene(scene_index);
        }
        app.finish_drawing_frame();
    }
}

/*
thread_local! {
    static SDL_CONTEXT: Sdl = sdl2::init().unwrap();
    static SDL_VIDEO: VideoSubsystem = SDL_CONTEXT.with(|context| context.video().unwrap());
    static SDL_EVENT: EventSubsystem = SDL_CONTEXT.with(|context| context.event().unwrap());
}*/

struct WindowImpl {
    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    window: WinitWindow,
    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    context: Context,

    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    canvas: Canvas<WinitWindow>,
    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    metal_layer: *mut CAMetalLayer,

    event_loop: EventsLoop,
    pending_events: VecDeque<Event>,
    mouse_position: Vector2I,
    mouse_down: bool,

    connection: Connection,
    device: Device,

    #[allow(dead_code)]
    resource_loader: FilesystemResourceLoader,
    selected_file: Option<PathBuf>,
}

impl Window for WindowImpl {
    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    fn gl_version(&self) -> GLVersion {
        GLVersion::GL3
    }

    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    fn gl_default_framebuffer(&self) -> GLuint {
        self.device.context_surface_info(&self.context).unwrap().unwrap().framebuffer_object
    }

    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    fn metal_layer(&self) -> &CoreAnimationLayerRef {
        unsafe { CoreAnimationLayerRef::from_ptr(self.metal_layer) }
    }

    fn viewport(&self, view: View) -> RectI {
        let WindowSize { logical_size, backing_scale_factor } = self.size();
        let mut size = (logical_size.to_f32() * backing_scale_factor).to_i32();
        let mut x_offset = 0;
        if let View::Stereo(index) = view {
            size.set_x(size.x() / 2);
            x_offset = size.x() * (index as i32);
        }
        RectI::new(vec2i(x_offset, 0), size)
    }

    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    fn make_current(&mut self, _view: View) {
        self.device.make_context_current(&self.context).unwrap();
    }

    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    fn make_current(&mut self, _: View) {}

    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    fn present(&mut self, _: &mut GLDevice) {
        let fbo = self.device
                      .context_surface_info(&self.context)
                      .unwrap()
                      .unwrap()
                      .framebuffer_object;
        let mut surface = self.device
                              .unbind_surface_from_context(&mut self.context)
                              .unwrap()
                              .unwrap();
        self.device.present_surface(&mut self.context, &mut surface).unwrap();
        self.device.bind_surface_to_context(&mut self.context, surface).unwrap();
    }

    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    fn present(&mut self, device: &mut MetalDevice) {
        device.present_drawable();
    }

    fn resource_loader(&self) -> &dyn ResourceLoader {
        &self.resource_loader
    }

    fn present_open_svg_dialog(&mut self) {
        /*
        if let Ok(Response::Okay(path)) = nfd::open_file_dialog(Some("svg"), None) {
            self.selected_file = Some(PathBuf::from(path));
            WindowImpl::push_user_event(self.open_svg_message_type, 0);
        }
        */
        // TODO(pcwalton)
    }

    fn run_save_dialog(&self, extension: &str) -> Result<PathBuf, ()> {
        match nfd::open_save_dialog(Some(extension), None) {
            Ok(Response::Okay(file)) => Ok(PathBuf::from(file)),
            _ => Err(()),
        }
    }

    fn create_user_event_id(&self) -> u32 {
        // TODO(pcwalton)
        0
    }

    fn push_user_event(message_type: u32, message_data: u32) {
        // TODO(pcwalton)
    }
}

impl WindowImpl {
    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    fn new() -> WindowImpl {
        let mut event_loop = EventsLoop::new();
        let dpi = event_loop.get_primary_monitor().get_hidpi_factor();
        let window_size = Size2D::new(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT);
        let logical_size = LogicalSize::new(window_size.width as f64, window_size.height as f64);
        let window = WindowBuilder::new().with_title("Pathfinder Demo")
                                         .with_dimensions(logical_size)
                                         .build(&event_loop)
                                         .unwrap();
        window.show();

        let connection = Connection::from_winit_window(&window).unwrap();
        let native_widget = connection.create_native_widget_from_winit_window(&window).unwrap();
        let adapter = connection.create_low_power_adapter().unwrap();
        let mut device = connection.create_device(&adapter).unwrap();

        let context_attributes = ContextAttributes {
            version: SurfmanGLVersion::new(3, 0),
            flags: ContextAttributeFlags::ALPHA,
        };
        let context_descriptor = device.create_context_descriptor(&context_attributes).unwrap();

        let surface_type = SurfaceType::Widget { native_widget };
        let mut context = device.create_context(&context_descriptor).unwrap();
        let surface = device.create_surface(&context, SurfaceAccess::GPUOnly, surface_type)
                            .unwrap();
        device.bind_surface_to_context(&mut context, surface).unwrap();
        device.make_context_current(&context).unwrap();

        gl::load_with(|symbol_name| device.get_proc_address(&context, symbol_name));

        let resource_loader = FilesystemResourceLoader::locate();

        /*
        SDL_VIDEO.with(|sdl_video| {
            SDL_EVENT.with(|sdl_event| {
                let (window, gl_context, event_pump);

                let gl_attributes = sdl_video.gl_attr();
                gl_attributes.set_context_profile(GLProfile::Core);
                gl_attributes.set_context_version(3, 3);
                gl_attributes.set_depth_size(24);
                gl_attributes.set_stencil_size(8);

                window = sdl_video
                    .window(
                        "Pathfinder Demo",
                        DEFAULT_WINDOW_WIDTH,
                        DEFAULT_WINDOW_HEIGHT,
                    )
                    .opengl()
                    .resizable()
                    .allow_highdpi()
                    .build()
                    .unwrap();

                gl_context = window.gl_create_context().unwrap();
                gl::load_with(|name| sdl_video.gl_get_proc_address(name) as *const _);

                event_pump = SDL_CONTEXT.with(|sdl_context| sdl_context.event_pump().unwrap());

                let resource_loader = FilesystemResourceLoader::locate();

                let open_svg_message_type = unsafe { sdl_event.register_event().unwrap() };

                WindowImpl {
                    window,
                    event_pump,
                    gl_context,
                    resource_loader,
                    open_svg_message_type,
                    selected_file: None,
                }
            })
        })
        */

        WindowImpl {
            window,
            event_loop,
            connection,
            context,
            device,
            pending_events: VecDeque::new(),
            mouse_position: vec2i(0, 0),
            mouse_down: false,
            resource_loader,
            selected_file: None,
        }
    }

    /*
    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    fn new() -> WindowImpl {
        assert!(hint::set("SDL_RENDER_DRIVER", "metal"));

        SDL_VIDEO.with(|sdl_video| {
            SDL_EVENT.with(|sdl_event| {
                let window = sdl_video
                    .window(
                        "Pathfinder Demo",
                        DEFAULT_WINDOW_WIDTH,
                        DEFAULT_WINDOW_HEIGHT,
                    )
                    .opengl()
                    .resizable()
                    .allow_highdpi()
                    .build()
                    .unwrap();

                let canvas = window.into_canvas().present_vsync().build().unwrap();
                let metal_layer = unsafe {
                    SDL_RenderGetMetalLayer(canvas.raw()) as *mut CAMetalLayer
                };

                let event_pump = SDL_CONTEXT.with(|sdl_context| sdl_context.event_pump().unwrap());

                let resource_loader = FilesystemResourceLoader::locate();

                let open_svg_message_type = unsafe { sdl_event.register_event().unwrap() };

                WindowImpl {
                    event_loop,
                    canvas,
                    metal_layer,
                    resource_loader,
                    open_svg_message_type,
                    selected_file: None,
                }
            })
        })
    }
    */

    #[cfg(any(not(target_os = "macos"), feature = "pf-gl"))]
    fn window(&self) -> &WinitWindow { &self.window }
    #[cfg(all(target_os = "macos", not(feature = "pf-gl")))]
    fn window(&self) -> &WinitWindow { self.canvas.window() }

    fn size(&self) -> WindowSize {
        let window = self.window();
        let (monitor, size) = (window.get_current_monitor(), window.get_inner_size().unwrap());

        WindowSize {
            logical_size: vec2i(size.width as i32, size.height as i32),
            backing_scale_factor: monitor.get_hidpi_factor() as f32,
        }
    }

    fn get_event(&mut self) -> Event {
        if self.pending_events.is_empty() {
            let window = &self.window;
            let mouse_position = &mut self.mouse_position;
            let mouse_down = &mut self.mouse_down;
            let selected_file = &mut self.selected_file;
            let pending_events = &mut self.pending_events;
            self.event_loop.run_forever(|event| {
                match convert_winit_event(event,
                                          window,
                                          mouse_position,
                                          mouse_down,
                                          selected_file) {
                    Some(event) => {
                        pending_events.push_back(event);
                        ControlFlow::Break
                    }
                    None => ControlFlow::Continue,
                }
            });
        }

        self.pending_events.pop_front().expect("Where's the event?")
    }

    fn try_get_event(&mut self) -> Option<Event> {
        if self.pending_events.is_empty() {
            let window = &self.window;
            let mouse_position = &mut self.mouse_position;
            let mouse_down = &mut self.mouse_down;
            let selected_file = &mut self.selected_file;
            let pending_events = &mut self.pending_events;
            self.event_loop.poll_events(|event| {
                if let Some(event) = convert_winit_event(event,
                                                         window,
                                                         mouse_position,
                                                         mouse_down,
                                                         selected_file) {
                    pending_events.push_back(event);
                }
            });
        }
        self.pending_events.pop_front()
    }
}

fn convert_winit_event(winit_event: WinitEvent,
                       window: &WinitWindow,
                       mouse_position: &mut Vector2I,
                       mouse_down: &mut bool,
                       selected_file: &mut Option<PathBuf>)
                       -> Option<Event> {
    match winit_event {
        WinitEvent::Awakened => {
            Some(Event::OpenSVG(SVGPath::Path(selected_file.clone().unwrap())))
        }
        WinitEvent::WindowEvent { event: window_event, .. } => {
            match window_event {
                WindowEvent::MouseInput {
                    state: ElementState::Pressed,
                    button: MouseButton::Left,
                    ..
                } => {
                    *mouse_down = true;
                    Some(Event::MouseDown(*mouse_position))
                }
                WindowEvent::MouseInput {
                    state: ElementState::Released,
                    button: MouseButton::Left,
                    ..
                } => {
                    *mouse_down = false;
                    None
                }
                WindowEvent::CursorMoved { position, .. } => {
                    *mouse_position = vec2i(position.x as i32, position.y as i32);
                    if *mouse_down {
                        Some(Event::MouseDragged(*mouse_position))
                    } else {
                        Some(Event::MouseMoved(*mouse_position))
                    }
                }
                WindowEvent::KeyboardInput { input, .. } => {
                    input.virtual_keycode.and_then(|virtual_keycode| {
                        match virtual_keycode {
                            VirtualKeyCode::Escape => Some(Keycode::Escape),
                            VirtualKeyCode::Tab => Some(Keycode::Tab),
                            virtual_keycode => {
                                let vk = virtual_keycode as u32;
                                let vk_a = VirtualKeyCode::A as u32;
                                let vk_z = VirtualKeyCode::Z as u32;
                                if vk >= vk_a && vk <= vk_z {
                                    let character = ((vk - vk_a) + 'A' as u32) as u8;
                                    Some(Keycode::Alphanumeric(character))
                                } else {
                                    None
                                }
                            }
                        }
                    }).map(|keycode| {
                        match input.state {
                            ElementState::Pressed => Event::KeyDown(keycode),
                            ElementState::Released => Event::KeyUp(keycode),
                        }
                    })
                }
                WindowEvent::CloseRequested => Some(Event::Quit),
                WindowEvent::Resized(new_size) => {
                    let logical_size = vec2i(new_size.width as i32, new_size.height as i32);
                    let backing_scale_factor =
                        window.get_current_monitor().get_hidpi_factor() as f32;
                    Some(Event::WindowResized(WindowSize {
                        logical_size,
                        backing_scale_factor,
                    }))
                }
                _ => None,
            }
        }
        _ => None,
    }
}