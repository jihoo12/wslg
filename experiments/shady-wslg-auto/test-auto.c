// Compile against the patched shared wlroots, for example:
// cc -D_FILE_OFFSET_BITS=64 -DWLR_USE_UNSTABLE -Wl,--export-dynamic test-auto.c
//   $(pkg-config --cflags --libs wlroots-0.20) -o test-auto
// EGL display discovery is deliberately stubbed; this does not test GPU rendering.
#define _GNU_SOURCE
#include <assert.h>
#include <EGL/egl.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <wlr/backend/multi.h>
#include <wlr/backend/wayland.h>
#include <wlr/render/pixman.h>
#include <wlr/types/wlr_buffer.h>

static struct wlr_backend wayland = {.buffer_caps = WLR_BUFFER_CAP_SHM};
static struct wlr_backend multi = {.buffer_caps = WLR_BUFFER_CAP_SHM};
static struct wlr_backend other = {.buffer_caps = WLR_BUFFER_CAP_SHM};
static bool dxg = true, mixed, wslg_peer = true;
static int parent_drm = -1, d3d12_attempts, drm_attempts;

bool wlr_backend_is_wl(struct wlr_backend *backend) { return backend == &wayland; }
bool wlr_backend_is_multi(struct wlr_backend *backend) { return backend == &multi; }
int wlr_backend_get_drm_fd(struct wlr_backend *backend) {
	return backend == &wayland || backend == &multi ? parent_drm : -1;
}
void wlr_multi_for_each_backend(struct wlr_backend *backend,
		void (*callback)(struct wlr_backend *, void *), void *data) {
	assert(backend == &multi);
	callback(&wayland, data);
	if (mixed) {
		callback(&other, data);
	}
}
struct wl_display *wlr_wl_backend_get_remote_display(struct wlr_backend *backend) {
	assert(backend == &wayland);
	return NULL;
}
int wl_display_get_fd(struct wl_display *display) { (void)display; return 112; }
int getpeername(int fd, struct sockaddr *addr, socklen_t *len) {
	assert(fd == 112 && *len >= sizeof(struct sockaddr_un));
	struct sockaddr_un *peer = (struct sockaddr_un *)addr;
	peer->sun_family = AF_UNIX;
	strcpy(peer->sun_path, wslg_peer ? "/alias/wayland-0" : "/unrelated/wayland-1");
	*len = sizeof(*peer);
	return 0;
}
int stat(const char *path, struct stat *st) {
	memset(st, 0, sizeof(*st));
	if (strcmp(path, "/dev/dxg") == 0) {
		if (!dxg) {
			return -1;
		}
		st->st_mode = S_IFCHR;
		return 0;
	}
	if (strcmp(path, "/mnt/wslg/runtime-dir/wayland-0") == 0 ||
			strcmp(path, "/alias/wayland-0") == 0 ||
			strcmp(path, "/unrelated/wayland-1") == 0) {
		st->st_mode = S_IFSOCK;
		st->st_dev = 100;
		st->st_ino = strcmp(path, "/unrelated/wayland-1") == 0 ? 201 : 200;
		return 0;
	}
	return -1;
}
EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *native, const EGLAttrib *attributes) {
	(void)platform; (void)native; (void)attributes;
	d3d12_attempts++;
	return EGL_NO_DISPLAY;
}
struct wlr_renderer *wlr_gles2_renderer_create_with_drm_fd(int fd) {
	(void)fd;
	drm_attempts++;
	return NULL;
}

static void check(struct wlr_backend *backend, int attempts, bool expect_pixman) {
	d3d12_attempts = 0;
	struct wlr_renderer *renderer = wlr_renderer_autocreate(backend);
	if (d3d12_attempts != attempts) fprintf(stderr, "actual=%d expected=%d dxg=%d mixed=%d wslg=%d drm=%d mode=%s\n",
		d3d12_attempts, attempts, dxg, mixed, wslg_peer, parent_drm, getenv("WLR_RENDERER"));
	assert(d3d12_attempts == attempts);
	assert((renderer != NULL) == expect_pixman);
	if (renderer) {
		assert(wlr_renderer_is_pixman(renderer));
		wlr_renderer_destroy(renderer);
	}
}

int main(void) {
	const char *vars[] = { "WLR_RENDERER", "WLR_GLES2_D3D12_SHM",
		"WLR_RENDERER_FORCE_SOFTWARE", "WLR_RENDER_DRM_DEVICE",
		"LIBGL_ALWAYS_SOFTWARE", "WLR_BACKENDS" };
	for (size_t i = 0; i < sizeof(vars) / sizeof(vars[0]); i++) {
		unsetenv(vars[i]);
	}
	check(&multi, 1, true); // automatic WSLg + existing fallback if EGL fails
	check(&wayland, 1, true);
	check(&other, 0, true);
	mixed = true;
	check(&multi, 0, true);
	mixed = false;
	wayland.buffer_caps = 0;
	check(&multi, 0, true);
	wayland.buffer_caps = WLR_BUFFER_CAP_SHM;
	wslg_peer = false;
	check(&multi, 0, true);
	setenv("WLR_GLES2_D3D12_SHM", "1", 1);
	check(&multi, 1, true); // explicit opt-in for an unusual parent socket
	dxg = false;
	check(&multi, 0, true); // opt-in cannot bypass /dev/dxg
	dxg = true;
	wslg_peer = true;
	setenv("WLR_GLES2_D3D12_SHM", "0", 1);
	check(&multi, 0, true);
	unsetenv("WLR_GLES2_D3D12_SHM");
	setenv("WLR_RENDERER", "pixman", 1);
	check(&multi, 0, true);
	setenv("WLR_RENDERER", "gles2", 1);
	check(&multi, 1, false);
	drm_attempts = 0;
	parent_drm = 999;
	check(&multi, 0, false); // existing DRM path takes priority
	assert(drm_attempts == 1);
	parent_drm = -1;
	setenv("WLR_RENDER_DRM_DEVICE", "/dev/nonexistent-yoi-fixture", 1);
	check(&multi, 0, false);
	unsetenv("WLR_RENDER_DRM_DEVICE");
	setenv("LIBGL_ALWAYS_SOFTWARE", "true", 1);
	check(&multi, 0, false);
	unsetenv("LIBGL_ALWAYS_SOFTWARE");
	setenv("WLR_RENDERER_FORCE_SOFTWARE", "1", 1);
	check(&multi, 0, false);
	return 0;
}
