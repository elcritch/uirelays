#include <assert.h>
#include <stdint.h>
#include "../src/uirelays/drivers/cairo_rgba.h"

int main(void) {
  uint32_t red = 0xff0000;
  cairo_surface_t *source = cairo_image_surface_create_for_data(
    (unsigned char *)&red, CAIRO_FORMAT_RGB24, 1, 1, 4);
  cairo_surface_t *target = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 6, 6);
  cairo_t *cr = cairo_create(target);
  cairo_set_source_rgb(cr, 0, 0, 0);
  cairo_paint(cr);

  uirelays_draw_cairo_rgba(cr, source, 1, 1, 1, 1, 4, 4);
  cairo_surface_flush(target);
  uint32_t *pixels = (uint32_t *)cairo_image_surface_get_data(target);
  int stride = cairo_image_surface_get_stride(target) / 4;
  for (int y = 0; y < 6; ++y) {
    for (int x = 0; x < 6; ++x) {
      uint32_t expected = x >= 1 && x < 5 && y >= 1 && y < 5 ? red : 0;
      assert((pixels[y*stride+x] & 0xffffff) == expected);
    }
  }

  /* Alpha mode preserves coverage while scaling, including source edges. */
  uint32_t alpha = 0x80800000;
  cairo_surface_t *translucent = cairo_image_surface_create_for_data(
    (unsigned char *)&alpha, CAIRO_FORMAT_ARGB32, 1, 1, 4);
  cairo_set_source_rgb(cr, 0, 0, 1);
  cairo_paint(cr);
  uirelays_draw_cairo_rgba(cr, translucent, 1, 1, 1, 1, 4, 4);
  cairo_surface_flush(target);
  for (int y = 0; y < 6; ++y)
    for (int x = 0; x < 6; ++x) {
      uint32_t expected = x >= 1 && x < 5 && y >= 1 && y < 5 ? 0x80007f : 0x0000ff;
      assert((pixels[y*stride+x] & 0xffffff) == expected);
    }
  assert(alpha == 0x80800000);
  cairo_surface_destroy(translucent);

  cairo_destroy(cr);
  cairo_surface_destroy(target);
  cairo_surface_destroy(source);
  return 0;
}
