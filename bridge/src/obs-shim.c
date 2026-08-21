/*
 * Implementations behind src/compat/ — the libobs surface the reused
 * plugin sources call. See src/compat/obs-module.h for why this exists.
 */

/* pthread_setname_np on glibc. */
#ifndef _WIN32
#define _GNU_SOURCE
#endif

#include <obs-module.h>
#include <util/dstr.h>
#include <util/threading.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#include <process.h>
#else
#include <unistd.h>
#endif

/* ------------------------------------------------------------------ */
/* Memory. libobs aborts on allocation failure and its callers rely on
 * that (none of them null-check); do the same rather than returning
 * NULL into code that will dereference it. */

static void *oom(void)
{
	fputs("[lenslink] out of memory\n", stderr);
	abort();
}

void *bmalloc(size_t size)
{
	void *p = malloc(size ? size : 1);
	return p ? p : oom();
}

void *bzalloc(size_t size)
{
	void *p = calloc(1, size ? size : 1);
	return p ? p : oom();
}

void *brealloc(void *ptr, size_t size)
{
	void *p = realloc(ptr, size ? size : 1);
	return p ? p : oom();
}

void bfree(void *ptr)
{
	free(ptr);
}

char *bstrdup(const char *str)
{
	if (!str)
		return NULL;
	size_t len = strlen(str) + 1;
	char *copy = bmalloc(len);
	memcpy(copy, str, len);
	return copy;
}

/* ------------------------------------------------------------------ */
/* Logging. */

static FILE *g_log_file;
static pthread_mutex_t g_log_mutex = PTHREAD_MUTEX_INITIALIZER;
static int g_log_min_level = LOG_INFO;

void lenslink_log_open(const char *path)
{
	pthread_mutex_lock(&g_log_mutex);
	if (g_log_file)
		fclose(g_log_file);
	g_log_file = path ? fopen(path, "w") : NULL;
	pthread_mutex_unlock(&g_log_mutex);
}

void lenslink_log_close(void)
{
	pthread_mutex_lock(&g_log_mutex);
	if (g_log_file) {
		fclose(g_log_file);
		g_log_file = NULL;
	}
	pthread_mutex_unlock(&g_log_mutex);
}

void lenslink_log_set_level(int min_level)
{
	g_log_min_level = min_level;
}

static const char *level_name(int level)
{
	switch (level) {
	case LOG_ERROR:
		return "error";
	case LOG_WARNING:
		return "warning";
	case LOG_DEBUG:
		return "debug";
	default:
		return "info";
	}
}

void blog(int log_level, const char *format, ...)
{
	if (log_level > g_log_min_level)
		return;

	char line[1024];
	va_list args;
	va_start(args, format);
	vsnprintf(line, sizeof(line), format, args);
	va_end(args);

	time_t now = time(NULL);
	struct tm tm_buf;
#ifdef _WIN32
	localtime_s(&tm_buf, &now);
#else
	localtime_r(&now, &tm_buf);
#endif
	char stamp[32];
	strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm_buf);

	pthread_mutex_lock(&g_log_mutex);
	fprintf(stderr, "%s %-7s %s\n", stamp, level_name(log_level), line);
	if (g_log_file) {
		fprintf(g_log_file, "%s %-7s %s\n", stamp,
			level_name(log_level), line);
		fflush(g_log_file);
	}
	pthread_mutex_unlock(&g_log_mutex);
}

/* ------------------------------------------------------------------ */
/* Platform. */

uint64_t os_gettime_ns(void)
{
#ifdef _WIN32
	static LARGE_INTEGER freq;
	if (!freq.QuadPart)
		QueryPerformanceFrequency(&freq);
	LARGE_INTEGER count;
	QueryPerformanceCounter(&count);
	/* Split to keep the multiply from overflowing on long uptimes. */
	return (uint64_t)(count.QuadPart / freq.QuadPart) * 1000000000ULL +
	       (uint64_t)(count.QuadPart % freq.QuadPart) * 1000000000ULL /
		       (uint64_t)freq.QuadPart;
#else
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
#endif
}

void os_sleep_ms(uint32_t duration)
{
#ifdef _WIN32
	Sleep(duration);
#else
	struct timespec ts;
	ts.tv_sec = duration / 1000;
	ts.tv_nsec = (long)(duration % 1000) * 1000000L;
	nanosleep(&ts, NULL);
#endif
}

void os_set_thread_name(const char *name)
{
#if defined(_WIN32)
	/* SetThreadDescription is Windows 10 1607+; resolved at runtime so
	 * the binary still starts on anything older. */
	typedef HRESULT(WINAPI * set_desc_t)(HANDLE, PCWSTR);
	static set_desc_t set_desc;
	static bool looked_up;
	if (!looked_up) {
		HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
		if (k32)
			set_desc = (set_desc_t)(void *)GetProcAddress(
				k32, "SetThreadDescription");
		looked_up = true;
	}
	if (!set_desc)
		return;
	WCHAR wide[64];
	int n = MultiByteToWideChar(CP_UTF8, 0, name, -1, wide, 64);
	if (n > 0)
		set_desc(GetCurrentThread(), wide);
#elif defined(__APPLE__)
	pthread_setname_np(name);
#else
	/* Linux caps thread names at 16 bytes including the terminator. */
	char short_name[16];
	snprintf(short_name, sizeof(short_name), "%s", name);
	pthread_setname_np(pthread_self(), short_name);
#endif
}

int astrcmpi(const char *str1, const char *str2)
{
	if (!str1)
		return str2 ? -1 : 0;
	if (!str2)
		return 1;
	while (*str1 && *str2) {
		int c1 = tolower((unsigned char)*str1);
		int c2 = tolower((unsigned char)*str2);
		if (c1 != c2)
			return c1 - c2;
		str1++;
		str2++;
	}
	return tolower((unsigned char)*str1) - tolower((unsigned char)*str2);
}

/* ------------------------------------------------------------------ */
/* Video-format stubs. Reached only through h264-decoder.c's
 * obs_source_output_video path, which the bridge never takes (it always
 * installs a frame sink). Present so that branch links. */

bool video_format_get_parameters_for_format(enum video_colorspace color_space,
					    enum video_range_type range,
					    enum video_format format,
					    float matrix[16], float min_range[3],
					    float max_range[3])
{
	(void)color_space;
	(void)range;
	(void)format;
	if (matrix)
		memset(matrix, 0, sizeof(float) * 16);
	if (min_range)
		memset(min_range, 0, sizeof(float) * 3);
	if (max_range)
		memset(max_range, 0, sizeof(float) * 3);
	return false;
}

void obs_source_output_video(obs_source_t *source,
			     const struct obs_source_frame *frame)
{
	(void)source;
	(void)frame;
}

/* Benchmark hook (pipeline-bench.h). The bridge does not ship the
 * benchmark CSV writer — that is an OBS-settings feature — but
 * h264-decoder.c references the symbol. */
void lenslink_bench_frame(uint64_t cost_ns, size_t bytes_copied, int width,
			  int height)
{
	(void)cost_ns;
	(void)bytes_copied;
	(void)width;
	(void)height;
}

/* ------------------------------------------------------------------ */
/* Win32 pthread subset. */

#ifdef _WIN32

struct thread_start {
	void *(*fn)(void *);
	void *arg;
};

static unsigned __stdcall thread_trampoline(void *param)
{
	struct thread_start start = *(struct thread_start *)param;
	bfree(param);
	start.fn(start.arg);
	return 0;
}

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
		   void *(*start)(void *), void *arg)
{
	(void)attr;
	struct thread_start *payload = bmalloc(sizeof(*payload));
	payload->fn = start;
	payload->arg = arg;
	uintptr_t handle =
		_beginthreadex(NULL, 0, thread_trampoline, payload, 0, NULL);
	if (!handle) {
		bfree(payload);
		return -1;
	}
	*thread = (HANDLE)handle;
	return 0;
}

int pthread_join(pthread_t thread, void **retval)
{
	if (retval)
		*retval = NULL;
	WaitForSingleObject(thread, INFINITE);
	CloseHandle(thread);
	return 0;
}

int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr)
{
	(void)attr;
	InitializeSRWLock(m);
	return 0;
}

int pthread_mutex_destroy(pthread_mutex_t *m)
{
	(void)m;
	return 0;
}

int pthread_mutex_lock(pthread_mutex_t *m)
{
	AcquireSRWLockExclusive(m);
	return 0;
}

int pthread_mutex_unlock(pthread_mutex_t *m)
{
	ReleaseSRWLockExclusive(m);
	return 0;
}

#endif
