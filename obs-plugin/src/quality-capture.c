#include <obs-module.h>
#include <util/platform.h>
#include <util/threading.h>

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "quality-capture.h"

#define QC_MAX_FILE_BYTES (8ULL * 1024 * 1024 * 1024)
#define QC_MAX_NAME 100

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_armed;
static bool g_done;
static char g_dir[1024];
static char g_error[160];
static char g_name[256];
static FILE *g_file;
static uint64_t g_written;
static uint64_t g_total;
static int g_files;

static bool safe_name(const char *name)
{
	size_t n = strlen(name);
	if (n == 0 || n > QC_MAX_NAME || name[0] == '.')
		return false;
	for (size_t i = 0; i < n; i++) {
		char c = name[i];
		bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			  (c >= '0' && c <= '9') || c == '.' || c == '-' ||
			  c == '_';
		if (!ok)
			return false;
	}
	return true;
}

static void close_file(void)
{
	if (g_file) {
		fclose(g_file);
		g_file = NULL;
	}
	g_name[0] = 0;
	g_written = 0;
	g_total = 0;
}

static void fail(const char *why)
{
	close_file();
	g_armed = false;
	snprintf(g_error, sizeof(g_error), "%s", why);
	blog(LOG_WARNING, "[lenslink][quality] %s", why);
}

bool lenslink_quality_arm(const char *id)
{
	char clean[48];
	size_t n = 0;
	for (const char *c = id; *c && n + 1 < sizeof(clean); c++) {
		bool ok = (*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') ||
			  (*c >= '0' && *c <= '9') || *c == '-' || *c == '_';
		if (ok)
			clean[n++] = *c;
	}
	clean[n] = 0;
	if (!n)
		return false;

	char rel[80];
	snprintf(rel, sizeof(rel), "quality/%s", clean);
	char *dir = obs_module_config_path(rel);
	if (!dir)
		return false;

	pthread_mutex_lock(&g_mutex);
	close_file();
	bool ok = os_mkdirs(dir) != MKDIR_ERROR;
	if (ok) {
		snprintf(g_dir, sizeof(g_dir), "%s", dir);
		g_armed = true;
		g_done = false;
		g_files = 0;
		g_error[0] = 0;
		blog(LOG_INFO, "[lenslink][quality] receiving into %s", g_dir);
	}
	pthread_mutex_unlock(&g_mutex);
	bfree(dir);
	return ok;
}

static uint64_t read_u64(const uint8_t *p)
{
	uint64_t v = 0;
	for (int i = 0; i < 8; i++)
		v = (v << 8) | p[i];
	return v;
}

void lenslink_quality_chunk(const uint8_t *payload, size_t len)
{
	if (len < 1)
		return;
	size_t name_len = payload[0];
	if (len < 1 + name_len + 16)
		return;

	char name[256];
	memcpy(name, payload + 1, name_len);
	name[name_len] = 0;
	uint64_t offset = read_u64(payload + 1 + name_len);
	uint64_t total = read_u64(payload + 1 + name_len + 8);
	const uint8_t *data = payload + 1 + name_len + 16;
	size_t data_len = len - (1 + name_len + 16);

	pthread_mutex_lock(&g_mutex);
	if (!g_armed) {
		pthread_mutex_unlock(&g_mutex);
		return;
	}
	if (!safe_name(name)) {
		fail("rejected a file with an unsafe name");
		pthread_mutex_unlock(&g_mutex);
		return;
	}
	if (total > QC_MAX_FILE_BYTES || offset > total ||
	    data_len > total - offset) {
		fail("rejected a file chunk outside its declared size");
		pthread_mutex_unlock(&g_mutex);
		return;
	}

	if (offset == 0) {
		close_file();
		char path[1300];
		snprintf(path, sizeof(path), "%s/%s", g_dir, name);
		g_file = os_fopen(path, "wb");
		if (!g_file) {
			fail("could not create a file in the capture folder");
			pthread_mutex_unlock(&g_mutex);
			return;
		}
		snprintf(g_name, sizeof(g_name), "%s", name);
		g_total = total;
		g_written = 0;
	} else if (!g_file || strcmp(name, g_name) != 0 ||
		   offset != g_written || total != g_total) {
		fail("file chunks arrived out of order");
		pthread_mutex_unlock(&g_mutex);
		return;
	}

	if (data_len && fwrite(data, 1, data_len, g_file) != data_len) {
		fail("write failed (disk full?)");
		pthread_mutex_unlock(&g_mutex);
		return;
	}
	g_written += data_len;

	if (g_written == g_total) {
		bool manifest = strcmp(g_name, "manifest.json") == 0;
		close_file();
		g_files++;
		if (manifest) {
			g_done = true;
			g_armed = false;
			blog(LOG_INFO,
			     "[lenslink][quality] capture complete: %d files in %s",
			     g_files, g_dir);
		}
	}
	pthread_mutex_unlock(&g_mutex);
}

static void json_escape(const char *in, char *out, size_t size)
{
	size_t o = 0;
	for (; *in && o + 2 < size; in++) {
		if (*in == '"' || *in == '\\')
			out[o++] = '\\';
		out[o++] = (unsigned char)*in < 0x20 ? ' ' : *in;
	}
	out[o] = 0;
}

void lenslink_quality_status_json(char *out, size_t size)
{
	char dir[2100], err[340], name[220];
	pthread_mutex_lock(&g_mutex);
	json_escape(g_dir, dir, sizeof(dir));
	json_escape(g_error, err, sizeof(err));
	json_escape(g_name, name, sizeof(name));
	snprintf(out, size,
		 "{\"armed\":%s,\"done\":%s,\"dir\":\"%s\",\"files\":%d,"
		 "\"file\":\"%s\",\"bytes\":%" PRIu64 ",\"total\":%" PRIu64
		 ",\"error\":\"%s\"}",
		 g_armed ? "true" : "false", g_done ? "true" : "false", dir,
		 g_files, name, g_written, g_total, err);
	pthread_mutex_unlock(&g_mutex);
}

void lenslink_quality_shutdown(void)
{
	pthread_mutex_lock(&g_mutex);
	close_file();
	g_armed = false;
	pthread_mutex_unlock(&g_mutex);
}
