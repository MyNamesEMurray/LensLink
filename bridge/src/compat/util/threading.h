/*
 * Threading, shimmed for the standalone bridge.
 *
 * On POSIX this is plain pthreads. On Windows the plugin links OBS's
 * bundled w32-pthreads; the bridge has no OBS to borrow that from, so
 * the subset the reused sources need maps onto Win32 directly.
 *
 * The mutex is an SRWLOCK rather than a CRITICAL_SECTION specifically
 * because web-control.c static-initializes its registry mutex with
 * PTHREAD_MUTEX_INITIALIZER: SRWLOCK_INIT is an all-zero struct and is
 * valid to use without a run-time init call, which a zeroed
 * CRITICAL_SECTION is not. Neither is recursive, matching a default
 * pthread mutex.
 */

#pragma once

#ifndef _WIN32

#include <pthread.h>

#else

#include <windows.h>

typedef HANDLE pthread_t;
typedef SRWLOCK pthread_mutex_t;
typedef void pthread_attr_t;
typedef void pthread_mutexattr_t;

#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
		   void *(*start)(void *), void *arg);
int pthread_join(pthread_t thread, void **retval);
int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr);
int pthread_mutex_destroy(pthread_mutex_t *m);
int pthread_mutex_lock(pthread_mutex_t *m);
int pthread_mutex_unlock(pthread_mutex_t *m);

#endif
