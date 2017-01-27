/* Any copyright is dedicated to the Public Domain.
 * http://creativecommons.org/publicdomain/zero/1.0/ */

extern crate compute_shader;
extern crate euclid;
extern crate gl;
extern crate glfw;
extern crate memmap;
extern crate pathfinder;

use compute_shader::buffer;
use compute_shader::instance::Instance;
use compute_shader::texture::{ExternalTexture, Format, Texture};
use euclid::{Point2D, Rect, Size2D};
use gl::types::{GLchar, GLint, GLsizei, GLsizeiptr, GLuint, GLvoid};
use glfw::{Action, Context, Key, OpenGlProfileHint, WindowEvent, WindowHint, WindowMode};
use memmap::{Mmap, Protection};
use pathfinder::batch::BatchBuilder;
use pathfinder::charmap::CodepointRanges;
use pathfinder::coverage::CoverageBuffer;
use pathfinder::glyph_buffer::GlyphBufferBuilder;
use pathfinder::glyph_range::GlyphRanges;
use pathfinder::otf::Font;
use pathfinder::rasterizer::{Rasterizer, RasterizerOptions};
use pathfinder::shaper::{self, GlyphPos};
use std::env;
use std::mem;
use std::os::raw::c_void;

const ATLAS_SIZE: u32 = 1024;
const WIDTH: u32 = 512;
const HEIGHT: u32 = 384;
const UNITS_PER_EM: u32 = 2048;

const INITIAL_POINT_SIZE: f32 = 24.0;
const MIN_POINT_SIZE: f32 = 6.0;
const MAX_POINT_SIZE: f32 = 400.0;

static TEXT: &'static str = "Loremipsumdolorsitamet";

fn main() {
    let mut glfw = glfw::init(glfw::LOG_ERRORS).unwrap();
    glfw.window_hint(WindowHint::ContextVersion(3, 3));
    glfw.window_hint(WindowHint::OpenGlForwardCompat(true));
    glfw.window_hint(WindowHint::OpenGlProfile(OpenGlProfileHint::Core));
    let context = glfw.create_window(WIDTH, HEIGHT, "lorem-ipsum", WindowMode::Windowed);

    let (mut window, events) = context.expect("Couldn't create a window!");
    window.make_current();
    window.set_scroll_polling(true);
    window.set_size_polling(true);
    window.set_framebuffer_size_polling(true);

    gl::load_with(|symbol| window.get_proc_address(symbol) as *const c_void);

    let (width, height) = window.get_framebuffer_size();
    let mut device_pixel_size = Size2D::new(width as u32, height as u32);

    let mut chars: Vec<char> = TEXT.chars().collect();
    chars.sort();
    let codepoint_ranges = CodepointRanges::from_sorted_chars(&chars);

    let file = Mmap::open_path(env::args().nth(1).unwrap(), Protection::Read).unwrap();
    let (font, glyph_positions, glyph_ranges);
    unsafe {
        font = Font::new(file.as_slice()).unwrap();
        glyph_ranges = font.cmap
                           .glyph_ranges_for_codepoint_ranges(&codepoint_ranges.ranges)
                           .unwrap();
        glyph_positions = shaper::shape_text(&font, &glyph_ranges, TEXT)
    }

    let renderer = Renderer::new();
    let mut point_size = INITIAL_POINT_SIZE;
    let mut dirty = true;

    while !window.should_close() {
        if dirty {
            renderer.redraw(&font,
                            point_size,
                            &glyph_ranges,
                            &glyph_positions,
                            &device_pixel_size);
            window.swap_buffers();
            dirty = false
        }

        glfw.wait_events();
        for (_, event) in glfw::flush_messages(&events) {
            match event {
                WindowEvent::Key(Key::Escape, _, Action::Press, _) => {
                    window.set_should_close(true)
                }
                WindowEvent::Scroll(_, y) => {
                    point_size += y as f32;

                    if point_size < MIN_POINT_SIZE {
                        point_size = MIN_POINT_SIZE
                    } else if point_size > MAX_POINT_SIZE {
                        point_size = MAX_POINT_SIZE
                    }

                    dirty = true
                }
                WindowEvent::Size(_, _) | WindowEvent::FramebufferSize(_, _) => {
                    let (width, height) = window.get_framebuffer_size();
                    device_pixel_size = Size2D::new(width as u32, height as u32);
                    dirty = true
                }
                _ => {}
            }
        }
    }
}

struct Renderer {
    rasterizer: Rasterizer,

    program: GLuint,
    atlas_uniform: GLint,
    transform_uniform: GLint,
    translation_uniform: GLint,

    vertex_array: GLuint,
    vertex_buffer: GLuint,
    index_buffer: GLuint,

    atlas_size: Size2D<u32>,

    coverage_buffer: CoverageBuffer,
    compute_texture: Texture,
    gl_texture: GLuint,
}

impl Renderer {
    fn new() -> Renderer {
        let instance = Instance::new().unwrap();
        let device = instance.create_device().unwrap();
        let queue = device.create_queue().unwrap();

        let rasterizer_options = RasterizerOptions::from_env().unwrap();
        let rasterizer = Rasterizer::new(&instance, device, queue, rasterizer_options).unwrap();

        let (program, position_attribute, tex_coord_attribute, atlas_uniform);
        let (transform_uniform, translation_uniform);
        let (mut vertex_array, mut vertex_buffer, mut index_buffer) = (0, 0, 0);
        unsafe {
            let vertex_shader = gl::CreateShader(gl::VERTEX_SHADER);
            let fragment_shader = gl::CreateShader(gl::FRAGMENT_SHADER);
            gl::ShaderSource(vertex_shader,
                             1,
                             &(VERTEX_SHADER.as_ptr() as *const u8 as *const GLchar),
                             &(VERTEX_SHADER.len() as GLint));
            gl::ShaderSource(fragment_shader,
                             1,
                             &(FRAGMENT_SHADER.as_ptr() as *const u8 as *const GLchar),
                             &(FRAGMENT_SHADER.len() as GLint));
            gl::CompileShader(vertex_shader);
            gl::CompileShader(fragment_shader);

            program = gl::CreateProgram();
            gl::AttachShader(program, vertex_shader);
            gl::AttachShader(program, fragment_shader);
            gl::LinkProgram(program);
            gl::UseProgram(program);

            position_attribute = gl::GetAttribLocation(program,
                                                       "aPosition\0".as_ptr() as *const GLchar);
            tex_coord_attribute = gl::GetAttribLocation(program,
                                                        "aTexCoord\0".as_ptr() as *const GLchar);
            atlas_uniform = gl::GetUniformLocation(program, "uAtlas\0".as_ptr() as *const GLchar);
            transform_uniform = gl::GetUniformLocation(program,
                                                       "uTransform\0".as_ptr() as *const GLchar);
            translation_uniform =
                gl::GetUniformLocation(program, "uTranslation\0".as_ptr() as *const GLchar);

            gl::GenVertexArrays(1, &mut vertex_array);
            gl::BindVertexArray(vertex_array);

            gl::GenBuffers(1, &mut vertex_buffer);
            gl::GenBuffers(1, &mut index_buffer);

            gl::BindBuffer(gl::ELEMENT_ARRAY_BUFFER, index_buffer);
            gl::BindBuffer(gl::ARRAY_BUFFER, vertex_buffer);

            gl::VertexAttribPointer(position_attribute as GLuint,
                                    2,
                                    gl::UNSIGNED_INT,
                                    gl::FALSE,
                                    mem::size_of::<Vertex>() as GLsizei,
                                    0 as *const GLvoid);
            gl::VertexAttribPointer(tex_coord_attribute as GLuint,
                                    2,
                                    gl::UNSIGNED_INT,
                                    gl::FALSE,
                                    mem::size_of::<Vertex>() as GLsizei,
                                    (mem::size_of::<f32>() * 2) as *const GLvoid);
            gl::EnableVertexAttribArray(position_attribute as GLuint);
            gl::EnableVertexAttribArray(tex_coord_attribute as GLuint);
        }

        // FIXME(pcwalton)
        let atlas_size = Size2D::new(ATLAS_SIZE, ATLAS_SIZE);

        let coverage_buffer = CoverageBuffer::new(&rasterizer.device, &atlas_size).unwrap();

        let compute_texture = rasterizer.device.create_texture(Format::R8,
                                                               buffer::Protection::WriteOnly,
                                                               &atlas_size).unwrap();

        let mut gl_texture = 0;
        unsafe {
            gl::GenTextures(1, &mut gl_texture);
            compute_texture.bind_to(&ExternalTexture::Gl(gl_texture)).unwrap();

            gl::BindTexture(gl::TEXTURE_RECTANGLE, gl_texture);
            gl::TexParameteri(gl::TEXTURE_RECTANGLE, gl::TEXTURE_MIN_FILTER, gl::LINEAR as GLint);
            gl::TexParameteri(gl::TEXTURE_RECTANGLE, gl::TEXTURE_MAG_FILTER, gl::LINEAR as GLint);
            gl::TexParameteri(gl::TEXTURE_RECTANGLE,
                              gl::TEXTURE_WRAP_S,
                              gl::CLAMP_TO_EDGE as GLint);
            gl::TexParameteri(gl::TEXTURE_RECTANGLE,
                              gl::TEXTURE_WRAP_T,
                              gl::CLAMP_TO_EDGE as GLint);
        }

        Renderer {
            rasterizer: rasterizer,

            program: program,
            atlas_uniform: atlas_uniform,
            transform_uniform: transform_uniform,
            translation_uniform: translation_uniform,

            vertex_array: vertex_array,
            vertex_buffer: vertex_buffer,
            index_buffer: index_buffer,

            atlas_size: atlas_size,

            coverage_buffer: coverage_buffer,
            compute_texture: compute_texture,
            gl_texture: gl_texture,
        }
    }

    fn redraw(&self,
              font: &Font,
              point_size: f32,
              glyph_ranges: &GlyphRanges,
              glyph_positions: &[GlyphPos],
              device_pixel_size: &Size2D<u32>) {
        // FIXME(pcwalton)
        let shelf_height = (point_size * 2.0).ceil() as u32;

        let mut glyph_buffer_builder = GlyphBufferBuilder::new();
        let mut batch_builder = BatchBuilder::new(device_pixel_size.width, shelf_height);

        for (glyph_index, glyph_id) in glyph_ranges.iter().enumerate() {
            glyph_buffer_builder.add_glyph(&font, glyph_id).unwrap();
            batch_builder.add_glyph(&glyph_buffer_builder, glyph_index as u32, point_size).unwrap()
        }

        let glyph_buffer = glyph_buffer_builder.finish().unwrap();
        let batch = batch_builder.finish(&glyph_buffer_builder).unwrap();

        self.rasterizer.draw_atlas(&Rect::new(Point2D::new(0, 0), self.atlas_size),
                                   shelf_height,
                                   &glyph_buffer,
                                   &batch,
                                   &self.coverage_buffer,
                                   &self.compute_texture).unwrap();

        self.rasterizer.queue.flush().unwrap();

        unsafe {
            gl::UseProgram(self.program);
            gl::BindVertexArray(self.vertex_array);
            gl::BindBuffer(gl::ARRAY_BUFFER, self.vertex_buffer);
            gl::BindBuffer(gl::ELEMENT_ARRAY_BUFFER, self.index_buffer);

            let (mut vertices, mut indices) = (vec![], vec![]);
            let mut left_pos = 0;
            for position in glyph_positions {
                let glyph_index = batch_builder.glyph_index_for(position.glyph_id).unwrap();
                let uv_rect = batch_builder.atlas_rect(glyph_index);
                let (uv_bl, uv_tr) = (uv_rect.origin, uv_rect.bottom_right());
                let right_pos = left_pos + uv_rect.size.width;
                let bottom_pos = uv_rect.size.height;

                let first_index = vertices.len() as u16;

                vertices.push(Vertex::new(left_pos,  0,          uv_bl.x, uv_tr.y));
                vertices.push(Vertex::new(right_pos, 0,          uv_tr.x, uv_tr.y));
                vertices.push(Vertex::new(right_pos, bottom_pos, uv_tr.x, uv_bl.y));
                vertices.push(Vertex::new(left_pos,  bottom_pos, uv_bl.x, uv_bl.y));

                indices.extend([0, 1, 3, 1, 2, 3].iter().map(|index| first_index + index));

                left_pos += ((position.advance as f32 * point_size) /
                             (UNITS_PER_EM as f32)).ceil() as u32
            }

            gl::BufferData(gl::ARRAY_BUFFER,
                           (vertices.len() * mem::size_of::<Vertex>()) as GLsizeiptr,
                           vertices.as_ptr() as *const GLvoid,
                           gl::STATIC_DRAW);
            gl::BufferData(gl::ELEMENT_ARRAY_BUFFER,
                           (indices.len() * mem::size_of::<u16>()) as GLsizeiptr,
                           indices.as_ptr() as *const GLvoid,
                           gl::STATIC_DRAW);

            gl::ActiveTexture(gl::TEXTURE0);
            gl::BindTexture(gl::TEXTURE_RECTANGLE, self.gl_texture);
            gl::Uniform1i(self.atlas_uniform, 0);

            let matrix = [
                2.0 / device_pixel_size.width as f32, 0.0,
                0.0, 2.0 / device_pixel_size.height as f32,
            ];
            gl::UniformMatrix2fv(self.transform_uniform, 1, gl::FALSE, matrix.as_ptr());

            gl::Uniform2f(self.translation_uniform,
                          -1.0,
                          1.0 - point_size * 2.0 / (device_pixel_size.height as f32));

            gl::Viewport(0,
                         0,
                         device_pixel_size.width as GLint,
                         device_pixel_size.height as GLint);
            gl::ClearColor(1.0, 1.0, 1.0, 1.0);
            gl::Clear(gl::COLOR_BUFFER_BIT);

            gl::DrawElements(gl::TRIANGLES,
                             indices.len() as GLsizei,
                             gl::UNSIGNED_SHORT,
                             0 as *const GLvoid);
        }
    }
}

#[derive(Clone, Copy, Debug)]
#[repr(C)]
struct Vertex {
    x: u32,
    y: u32,
    u: u32,
    v: u32,
}

impl Vertex {
    fn new(x: u32, y: u32, u: u32, v: u32) -> Vertex {
        Vertex {
            x: x,
            y: y,
            u: u,
            v: v,
        }
    }
}

static VERTEX_SHADER: &'static str = "\
#version 330

uniform mat2 uTransform;
uniform vec2 uTranslation;

in vec2 aPosition;
in vec2 aTexCoord;

out vec2 vTexCoord;

void main() {
    vTexCoord = aTexCoord;
    gl_Position = vec4(uTransform * aPosition + uTranslation, 0.0f, 1.0f);
}
";

static FRAGMENT_SHADER: &'static str = "\
#version 330

uniform sampler2DRect uAtlas;

in vec2 vTexCoord;

out vec4 oFragColor;

void main() {
    float value = 1.0f - texture(uAtlas, vTexCoord).r;
    oFragColor = vec4(value, value, value, 1.0f);
}
";

