package example

import "core:fmt"
import "core:c"
import "core:time"
import "core:c/libc"

import SDL "vendor:sdl2"

import bgfx ".."

main :: proc() {
  window_size := [2]i32{ 640, 480 }

  window := SDL.CreateWindow("Odin SDL2 Demo", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, window_size.x, window_size.y, {.OPENGL})
	if window == nil {
		fmt.eprintln("Failed to create window")
		return
	}
	defer SDL.DestroyWindow(window)

  set_backbuffer_size :: proc(window_x : u32, window_y : u32) {
    bgfx.reset(window_x, window_y, { vsync = true })
    bgfx.set_view_rect(0, 0, 0, u16(window_x), u16(window_y))
  }

  // Init BGFX
  settings : bgfx.Init
  {
    bgfx.init_ctor(&settings)
    settings.callback = new(bgfx.CallbackInterface)
    settings.callback.vtbl = new(bgfx.CallbackVTable)
    settings.callback.fatal = proc "c" (this : ^bgfx.CallbackInterface, file_path : cstring, line : u16, code : bgfx.Fatal, str : cstring) {}
    settings.callback.trace_vargs = proc "c" (this : ^bgfx.CallbackInterface, file_path : cstring, line : u16, format : cstring, _arg_list : ^c.va_list) {
      libc.vprintf(format, _arg_list)
    }
    settings.callback.profiler_begin = proc "c" (this : ^bgfx.CallbackInterface, name : cstring, abgr : bgfx.Color, file_path : cstring, line : u16) {}
    settings.callback.profiler_begin_literal = proc "c" (this : ^bgfx.CallbackInterface, name : cstring, abgr : bgfx.Color, file_path : cstring, line : u16) {}
    settings.callback.profiler_end = proc "c" (this : ^bgfx.CallbackInterface) {}
    settings.callback.cache_read_size = proc "c" (this : ^bgfx.CallbackInterface, id : u64) -> (num_bytes : u32) { return 0 }
    settings.callback.cache_read = proc "c" (this : ^bgfx.CallbackInterface, id : u64, data : rawptr, size : u32) -> (was_read : bool) { return false }
    settings.callback.cache_write = proc "c" (this : ^bgfx.CallbackInterface, id : u64, data : /*const*/ rawptr, size : u32) {}
    settings.callback.screen_shot = proc "c" (this : ^bgfx.CallbackInterface, file_path : cstring, width : u32, height : u32, pitch : u32, data : /*const*/ rawptr, size : u32, yflip : bool) {}
    settings.callback.capture_begin = proc "c" (this : ^bgfx.CallbackInterface, width : u32, height : u32, pitch : u32, format : bgfx.TextureFormat, yflip : bool) {}
    settings.callback.capture_end = proc "c" (this : ^bgfx.CallbackInterface) {}
    settings.callback.capture_frame = proc "c" (this : ^bgfx.CallbackInterface, data : /*const*/ rawptr, size : u32) {}
    add_platform_data(window, &settings.platform_data)
    if !bgfx.init(&settings) 
    {
      fmt.eprintln("Cant inint bgfx!")
    }
    set_backbuffer_size(u32(window_size.x), u32(window_size.y))
    bgfx.set_view_clear(0, { .Color, .Depth }, 0x110022FF)
    bgfx.set_debug({ .Text })
  }
  defer bgfx.shutdown()
  defer free(settings.callback)
  defer free(settings.callback.vtbl)

  // Init Graphics
  message_buffer : [32]u8
  message := cstring("Hello from bgfx!")
  vert_buffer : bgfx.VertexBufferHandle
  index_buffer : bgfx.IndexBufferHandle
  program := bgfx.ProgramHandle.Invalid
  {
    // Triangles
    Vert :: struct {
      pos : [2]f32,
      color : [3]u8,
    }
    vertex_layout : bgfx.VertexLayout
    bgfx.vertex_layout_begin(&vertex_layout)
    bgfx.vertex_layout_add(&vertex_layout, .Position, 2, .Float)
    bgfx.vertex_layout_add(&vertex_layout, .Color_0, 3, .Uint8, normalized = true)
    bgfx.vertex_layout_end(&vertex_layout)

    @(static)
    verts : [6]Vert
    verts = {
      { { -0.5,  -0.4  }, { 0xFF, 0x00, 0x00 } },
      { {  0.5,  -0.4  }, { 0x00, 0x00, 0xFF } },
      { {  0.0,   0.7  }, { 0x00, 0xFF, 0x00 } },

      { {  0.3,   0.3  }, { 0x00, 0xFF, 0xFF } },
      { { -0.3,   0.3  }, { 0xFF, 0xFF, 0x00 } },
      { {  0.0,  -0.55 }, { 0xFF, 0x00, 0xFF } },
    }

    @(static)
    indices : [6]u16
    indices = {
      0, 1, 2,
      3, 4, 5,
    }

    vert_buffer = bgfx.create_vertex_buffer(bgfx.make_ref(&verts[0], size_of(verts)), &vertex_layout)
    index_buffer = bgfx.create_index_buffer(bgfx.make_ref(&indices[0], size_of(indices)))

    // Shaders
    all_vs := #partial [bgfx.RendererType][]u8{
      .Direct_3D_11 = #load("shaders/unlit_vert_dx11.bin"),
      .Direct_3D_12 = #load("shaders/unlit_vert_dx12.bin"),
      .Metal = #load("shaders/unlit_vert_metal.bin"),
      .OpenGL = #load("shaders/unlit_vert_opengl.bin"),
      .OpenGL_ES = #load("shaders/unlit_vert_opengles.bin"),
      .Vulkan = #load("shaders/unlit_vert_vulkan.bin"),
    }

    all_fs := #partial [bgfx.RendererType][]u8{
      .Direct_3D_11 = #load("shaders/unlit_frag_dx11.bin"),
      .Direct_3D_12 = #load("shaders/unlit_frag_dx12.bin"),
      .Metal = #load("shaders/unlit_frag_metal.bin"),
      .OpenGL = #load("shaders/unlit_frag_opengl.bin"),
      .OpenGL_ES = #load("shaders/unlit_frag_opengles.bin"),
      .Vulkan = #load("shaders/unlit_frag_vulkan.bin"),
    }

    render_type := bgfx.get_renderer_type()
    vs_bin := all_vs[render_type]
    fs_bin := all_fs[render_type]
    if len(vs_bin) > 0 && len(fs_bin) > 0 {
      vs := bgfx.create_shader(bgfx.make_ref(raw_data(vs_bin), u32(len(vs_bin))))
      fs := bgfx.create_shader(bgfx.make_ref(raw_data(fs_bin), u32(len(fs_bin))))
      program = bgfx.create_program_vert_frag(vs, fs, destroy_shaders = true)
    } else {
      fmt.bprintf(message_buffer[:len(message_buffer)-1], "No shaders for: %s", bgfx.get_renderer_name(render_type))
      message = cstring(&message_buffer[0])
    }
  }
  defer bgfx.destroy(vert_buffer)
  defer bgfx.destroy(index_buffer)
  defer bgfx.destroy(program)

  // Main Loop
  last_window_size := window_size
  // high precision timer
	start_tick := time.tick_now()
  loop: for {
		duration := time.tick_since(start_tick)
		t := f32(time.duration_seconds(duration))
		
		// event polling
		event: SDL.Event
		for SDL.PollEvent(&event) {
			// #partial switch tells the compiler not to error if every case is not present
			#partial switch event.type {
			case .KEYDOWN:
				#partial switch event.key.keysym.sym {
				case .ESCAPE:
					// labelled control flow
					break loop
				}
			case .QUIT:
				// labelled control flow
				break loop
			}
		}

    // Handle Window Resize
    defer last_window_size = window_size
    SDL.GetWindowSize(window, &window_size.x, &window_size.y)
    if last_window_size != window_size {
      set_backbuffer_size(u32(window_size.x), u32(window_size.y))
    }

    // Debug Text
    bgfx.dbg_text_clear()
    console_size := [2]u16{ u16(window_size.x/8), u16(window_size.y/16) }
    bgfx.dbg_text_printf((console_size.x-u16(len(message)))/2, console_size.y-4, { fg = .B_Black }, message)

    // Draw
    if program != .Invalid {
      renderer := bgfx.get_renderer_name(bgfx.get_renderer_type())
      bgfx.dbg_text_printf((console_size.x-u16(len(renderer)))/2, 2, { fg = .B_White }, renderer)

      bgfx.set_vertex_buffer(0, vert_buffer)
      bgfx.set_index_buffer(index_buffer)
      bgfx.set_state({
        write_r = true,
        write_g = true,
        write_b = true,
      })
      bgfx.submit(0, program)
    } else  {
      bgfx.touch(0)
    }

    // Swap
    bgfx.frame()
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////

when ODIN_OS == .Windows {

  // Windows
  add_platform_data :: proc(window : ^SDL.Window, platform_data : ^bgfx.PlatformData) {
    info : SDL.SysWMinfo;
		SDL.GetWindowWMInfo(window, &info);
    platform_data.nwh = info.info.win.window
  }

} else when ODIN_OS == .Linux {

  USE_WAYLAND :: false

  when USE_WAYLAND {

    // Linux + Wayland
    add_platform_data :: proc(window : ^SDL.Window, platform_data : ^bgfx.PlatformData) {
      info : SDL.SysWMinfo;
		  SDL.GetWindowWMInfo(window, &info);
      platform_data.ndt = info.info.wl.display
      platform_data.nwh = info.info.wl.egl_window
      platform_data.type = .Wayland
    }

  } else {

    // Linux + X11
    add_platform_data :: proc(window : ^SDL.Window, platform_data : ^bgfx.PlatformData) {
      info : SDL.SysWMinfo;
		  SDL.GetWindowWMInfo(window, &info);
      platform_data.ndt = info.info.x11.display
      platform_data.nwh = info.info.x11.window
      platform_data.type = .Default
    }

  }

} else when ODIN_OS == .Darwin {
  add_platform_data :: proc(window : ^SDL.Window, platform_data : ^bgfx.PlatformData) {
    info : SDL.SysWMinfo;
		SDL.GetWindowWMInfo(window, &info);
    platform_data.nwh = info.info.cocoa.window
  }

} else {

  #panic("Unsupported OS!")

}