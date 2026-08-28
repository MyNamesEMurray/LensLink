#include <initguid.h>

#include "guids.h"
#include "vcam-filter.h"

#include <stdio.h>
#include <string.h>

/* Advertised modes. 720p first: it is the default a video-call app
 * should land on, and the one a phone can hold at 30 fps indefinitely
 * without heat-throttling. NV12 is the phone's native output (no
 * conversion at all); YUY2 is there because plenty of apps still ask
 * for it and refusing would make us invisible to them. */
const vcam_format g_formats[] = {
	{1280, 720, &MEDIASUBTYPE_NV12},
	{1280, 720, &MEDIASUBTYPE_YUY2},
	{1920, 1080, &MEDIASUBTYPE_NV12},
	{1920, 1080, &MEDIASUBTYPE_YUY2},
	{640, 480, &MEDIASUBTYPE_NV12},
	{640, 480, &MEDIASUBTYPE_YUY2},
};
const int g_format_count = (int)(sizeof(g_formats) / sizeof(g_formats[0]));

static long image_bytes(const vcam_format &f)
{
	/* NV12 is 12 bits per pixel, YUY2 16. */
	if (IsEqualGUID(*f.subtype, MEDIASUBTYPE_NV12))
		return (long)f.width * f.height * 3 / 2;
	return (long)f.width * f.height * 2;
}

void vcam_free_media_type(AM_MEDIA_TYPE *mt)
{
	if (!mt)
		return;
	if (mt->cbFormat && mt->pbFormat) {
		CoTaskMemFree(mt->pbFormat);
		mt->pbFormat = nullptr;
		mt->cbFormat = 0;
	}
	if (mt->pUnk) {
		mt->pUnk->Release();
		mt->pUnk = nullptr;
	}
}

static void delete_media_type(AM_MEDIA_TYPE *mt)
{
	if (!mt)
		return;
	vcam_free_media_type(mt);
	CoTaskMemFree(mt);
}

AM_MEDIA_TYPE *vcam_create_media_type(int index, REFERENCE_TIME frame_time)
{
	if (index < 0 || index >= g_format_count)
		return nullptr;

	const vcam_format &f = g_formats[index];

	AM_MEDIA_TYPE *mt = (AM_MEDIA_TYPE *)CoTaskMemAlloc(sizeof(*mt));
	if (!mt)
		return nullptr;
	ZeroMemory(mt, sizeof(*mt));

	VIDEOINFOHEADER *vih =
		(VIDEOINFOHEADER *)CoTaskMemAlloc(sizeof(VIDEOINFOHEADER));
	if (!vih) {
		CoTaskMemFree(mt);
		return nullptr;
	}
	ZeroMemory(vih, sizeof(*vih));

	vih->AvgTimePerFrame = frame_time;
	vih->dwBitRate = (DWORD)(image_bytes(f) * 8 *
				 (10000000.0 / (double)frame_time));

	vih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	vih->bmiHeader.biWidth = f.width;
	/* Positive height: NV12 and YUY2 are top-down formats, and a
	 * negative height here is how you get an upside-down webcam. */
	vih->bmiHeader.biHeight = f.height;
	vih->bmiHeader.biPlanes = 1;
	vih->bmiHeader.biBitCount =
		IsEqualGUID(*f.subtype, MEDIASUBTYPE_NV12) ? 12 : 16;
	vih->bmiHeader.biCompression = f.subtype->Data1;
	vih->bmiHeader.biSizeImage = (DWORD)image_bytes(f);

	mt->majortype = MEDIATYPE_Video;
	mt->subtype = *f.subtype;
	mt->formattype = FORMAT_VideoInfo;
	mt->bFixedSizeSamples = TRUE;
	mt->bTemporalCompression = FALSE;
	mt->lSampleSize = (ULONG)image_bytes(f);
	mt->cbFormat = sizeof(VIDEOINFOHEADER);
	mt->pbFormat = (BYTE *)vih;

	return mt;
}

/* Which advertised mode a proposed type corresponds to, or -1. */
static int match_format(const AM_MEDIA_TYPE *mt)
{
	if (!mt || !IsEqualGUID(mt->majortype, MEDIATYPE_Video))
		return -1;
	if (!IsEqualGUID(mt->formattype, FORMAT_VideoInfo) || !mt->pbFormat)
		return -1;
	if (mt->cbFormat < sizeof(VIDEOINFOHEADER))
		return -1;

	const VIDEOINFOHEADER *vih = (const VIDEOINFOHEADER *)mt->pbFormat;
	for (int i = 0; i < g_format_count; i++) {
		if (!IsEqualGUID(mt->subtype, *g_formats[i].subtype))
			continue;
		if (vih->bmiHeader.biWidth != g_formats[i].width)
			continue;
		long height = vih->bmiHeader.biHeight;
		if (height < 0)
			height = -height;
		if (height != g_formats[i].height)
			continue;
		return i;
	}
	return -1;
}

/* ------------------------------------------------------------------ */
/* Enumerators. Both are trivial and both are mandatory — a graph that
 * cannot enumerate a filter's pins cannot connect it. */

class CEnumPins : public IEnumPins {
public:
	CEnumPins(IPin *pin, ULONG position)
		: m_refs(1), m_pin(pin), m_position(position)
	{
		m_pin->AddRef();
	}
	virtual ~CEnumPins() { m_pin->Release(); }

	STDMETHODIMP QueryInterface(REFIID riid, void **ppv) override
	{
		if (!ppv)
			return E_POINTER;
		if (IsEqualIID(riid, IID_IUnknown) ||
		    IsEqualIID(riid, IID_IEnumPins)) {
			*ppv = static_cast<IEnumPins *>(this);
			AddRef();
			return S_OK;
		}
		*ppv = nullptr;
		return E_NOINTERFACE;
	}
	STDMETHODIMP_(ULONG) AddRef() override
	{
		return (ULONG)InterlockedIncrement(&m_refs);
	}
	STDMETHODIMP_(ULONG) Release() override
	{
		LONG refs = InterlockedDecrement(&m_refs);
		if (!refs)
			delete this;
		return (ULONG)refs;
	}

	STDMETHODIMP Next(ULONG count, IPin **pins, ULONG *fetched) override
	{
		if (!pins)
			return E_POINTER;
		ULONG n = 0;
		if (count > 0 && m_position == 0) {
			m_pin->AddRef();
			pins[0] = m_pin;
			n = 1;
			m_position = 1;
		}
		if (fetched)
			*fetched = n;
		/* S_FALSE means "fewer than asked for", which is how a
		 * caller knows it reached the end. */
		return n == count ? S_OK : S_FALSE;
	}
	STDMETHODIMP Skip(ULONG count) override
	{
		m_position += count;
		return m_position > 1 ? S_FALSE : S_OK;
	}
	STDMETHODIMP Reset() override
	{
		m_position = 0;
		return S_OK;
	}
	STDMETHODIMP Clone(IEnumPins **out) override
	{
		if (!out)
			return E_POINTER;
		*out = new CEnumPins(m_pin, m_position);
		return *out ? S_OK : E_OUTOFMEMORY;
	}

private:
	LONG m_refs;
	IPin *m_pin;
	ULONG m_position;
};

class CEnumMediaTypes : public IEnumMediaTypes {
public:
	explicit CEnumMediaTypes(int position, REFERENCE_TIME frame_time)
		: m_refs(1), m_position(position), m_frame_time(frame_time)
	{
	}
	virtual ~CEnumMediaTypes() {}

	STDMETHODIMP QueryInterface(REFIID riid, void **ppv) override
	{
		if (!ppv)
			return E_POINTER;
		if (IsEqualIID(riid, IID_IUnknown) ||
		    IsEqualIID(riid, IID_IEnumMediaTypes)) {
			*ppv = static_cast<IEnumMediaTypes *>(this);
			AddRef();
			return S_OK;
		}
		*ppv = nullptr;
		return E_NOINTERFACE;
	}
	STDMETHODIMP_(ULONG) AddRef() override
	{
		return (ULONG)InterlockedIncrement(&m_refs);
	}
	STDMETHODIMP_(ULONG) Release() override
	{
		LONG refs = InterlockedDecrement(&m_refs);
		if (!refs)
			delete this;
		return (ULONG)refs;
	}

	STDMETHODIMP Next(ULONG count, AM_MEDIA_TYPE **types,
			  ULONG *fetched) override
	{
		if (!types)
			return E_POINTER;
		ULONG n = 0;
		while (n < count && m_position < g_format_count) {
			AM_MEDIA_TYPE *mt =
				vcam_create_media_type(m_position,
						       m_frame_time);
			if (!mt)
				break;
			types[n++] = mt;
			m_position++;
		}
		if (fetched)
			*fetched = n;
		return n == count ? S_OK : S_FALSE;
	}
	STDMETHODIMP Skip(ULONG count) override
	{
		m_position += (int)count;
		return m_position > g_format_count ? S_FALSE : S_OK;
	}
	STDMETHODIMP Reset() override
	{
		m_position = 0;
		return S_OK;
	}
	STDMETHODIMP Clone(IEnumMediaTypes **out) override
	{
		if (!out)
			return E_POINTER;
		*out = new CEnumMediaTypes(m_position, m_frame_time);
		return *out ? S_OK : E_OUTOFMEMORY;
	}

private:
	LONG m_refs;
	int m_position;
	REFERENCE_TIME m_frame_time;
};

/* ------------------------------------------------------------------ */
/* Pin */

CLensLinkPin::CLensLinkPin(CLensLinkFilter *filter)
	: m_filter(filter), m_connected(nullptr), m_input(nullptr),
	  m_allocator(nullptr), m_quality_sink(nullptr), m_mt_valid(false),
	  m_format_index(-1), m_frame_time(VCAM_DEFAULT_FRAME_TIME),
	  m_thread(nullptr), m_stop_event(nullptr), m_shm(nullptr),
	  m_scratch(nullptr), m_scratch_size(0)
{
	ZeroMemory(&m_mt, sizeof(m_mt));
	InitializeCriticalSection(&m_lock);
}

CLensLinkPin::~CLensLinkPin()
{
	StopStreaming();
	Disconnect();
	vcam_free_media_type(&m_mt);
	if (m_scratch)
		free(m_scratch);
	DeleteCriticalSection(&m_lock);
}

STDMETHODIMP CLensLinkPin::QueryInterface(REFIID riid, void **ppv)
{
	if (!ppv)
		return E_POINTER;

	if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IPin))
		*ppv = static_cast<IPin *>(this);
	else if (IsEqualIID(riid, IID_IAMStreamConfig))
		*ppv = static_cast<IAMStreamConfig *>(this);
	else if (IsEqualIID(riid, IID_IKsPropertySet))
		*ppv = static_cast<IKsPropertySet *>(this);
	else if (IsEqualIID(riid, IID_IQualityControl))
		*ppv = static_cast<IQualityControl *>(this);
	else {
		*ppv = nullptr;
		return E_NOINTERFACE;
	}

	AddRef();
	return S_OK;
}

STDMETHODIMP_(ULONG) CLensLinkPin::AddRef()
{
	return m_filter->InternalAddRef();
}

STDMETHODIMP_(ULONG) CLensLinkPin::Release()
{
	return m_filter->InternalRelease();
}

STDMETHODIMP CLensLinkPin::Connect(IPin *receive, const AM_MEDIA_TYPE *mt)
{
	if (!receive)
		return E_POINTER;
	if (m_filter->State() != State_Stopped)
		return VFW_E_NOT_STOPPED;

	EnterCriticalSection(&m_lock);
	if (m_connected) {
		LeaveCriticalSection(&m_lock);
		return VFW_E_ALREADY_CONNECTED;
	}
	LeaveCriticalSection(&m_lock);

	/* A fully specified type from the caller wins; otherwise walk our
	 * own list in preference order and offer each until one is
	 * accepted. */
	HRESULT hr = VFW_E_NO_ACCEPTABLE_TYPES;
	for (int i = -1; i < g_format_count; i++) {
		AM_MEDIA_TYPE *candidate = nullptr;

		if (i < 0) {
			if (!mt || match_format(mt) < 0)
				continue;
			candidate = vcam_create_media_type(match_format(mt),
							   m_frame_time);
		} else {
			if (mt && match_format(mt) >= 0)
				break; /* the caller's type already failed */
			candidate = vcam_create_media_type(i, m_frame_time);
		}
		if (!candidate)
			continue;

		if (receive->QueryAccept(candidate) != S_OK) {
			delete_media_type(candidate);
			continue;
		}

		hr = receive->ReceiveConnection(this, candidate);
		if (FAILED(hr)) {
			delete_media_type(candidate);
			continue;
		}

		IMemInputPin *input = nullptr;
		hr = receive->QueryInterface(IID_IMemInputPin, (void **)&input);
		if (FAILED(hr)) {
			receive->Disconnect();
			delete_media_type(candidate);
			continue;
		}

		hr = NegotiateAllocator(input);
		if (FAILED(hr)) {
			input->Release();
			receive->Disconnect();
			delete_media_type(candidate);
			continue;
		}

		EnterCriticalSection(&m_lock);
		vcam_free_media_type(&m_mt);
		m_mt = *candidate;
		m_mt_valid = true;
		m_format_index = match_format(candidate);
		m_connected = receive;
		m_connected->AddRef();
		m_input = input;
		LeaveCriticalSection(&m_lock);

		/* The type's heap members are ours now; free only the
		 * struct the enumerator allocated around them. */
		CoTaskMemFree(candidate);

		/* Tell the bridge what to scale to, so the first frame
		 * after a connection is already the right size. */
		if (!m_shm)
			m_shm = llshm_open_read();
		if (m_shm && m_format_index >= 0)
			llshm_set_wanted_format(
				m_shm, (uint32_t)g_formats[m_format_index].width,
				(uint32_t)g_formats[m_format_index].height,
				(uint32_t)(10000000 / m_frame_time));
		return S_OK;
	}

	return hr;
}

HRESULT CLensLinkPin::NegotiateAllocator(IMemInputPin *input)
{
	ALLOCATOR_PROPERTIES request = {};
	ALLOCATOR_PROPERTIES actual = {};

	int index = m_format_index >= 0 ? m_format_index : 0;
	request.cBuffers = 2;
	request.cbBuffer = (long)image_bytes(g_formats[index]);
	request.cbAlign = 1;
	request.cbPrefix = 0;

	/* Downstream's requirements are advisory; only alignment and
	 * prefix actually have to be honoured. */
	ALLOCATOR_PROPERTIES downstream = {};
	if (SUCCEEDED(input->GetAllocatorRequirements(&downstream))) {
		if (downstream.cbAlign > 0)
			request.cbAlign = downstream.cbAlign;
		if (downstream.cbPrefix > 0)
			request.cbPrefix = downstream.cbPrefix;
		if (downstream.cBuffers > request.cBuffers)
			request.cBuffers = downstream.cBuffers;
	}

	IMemAllocator *allocator = nullptr;
	HRESULT hr = input->GetAllocator(&allocator);
	if (FAILED(hr)) {
		hr = CoCreateInstance(CLSID_MemoryAllocator, nullptr,
				      CLSCTX_INPROC_SERVER, IID_IMemAllocator,
				      (void **)&allocator);
		if (FAILED(hr))
			return hr;
	}

	hr = allocator->SetProperties(&request, &actual);
	if (FAILED(hr) || actual.cbBuffer < request.cbBuffer) {
		allocator->Release();
		return FAILED(hr) ? hr : E_FAIL;
	}

	hr = input->NotifyAllocator(allocator, FALSE);
	if (FAILED(hr)) {
		allocator->Release();
		return hr;
	}

	if (m_allocator)
		m_allocator->Release();
	m_allocator = allocator;
	return S_OK;
}

STDMETHODIMP CLensLinkPin::ReceiveConnection(IPin *, const AM_MEDIA_TYPE *)
{
	/* Output pins are connected *to*, never connected *into*. */
	return E_UNEXPECTED;
}

STDMETHODIMP CLensLinkPin::Disconnect()
{
	if (m_filter->State() != State_Stopped)
		return VFW_E_NOT_STOPPED;

	StopStreaming();

	EnterCriticalSection(&m_lock);
	if (m_allocator) {
		m_allocator->Decommit();
		m_allocator->Release();
		m_allocator = nullptr;
	}
	if (m_input) {
		m_input->Release();
		m_input = nullptr;
	}
	if (m_connected) {
		m_connected->Release();
		m_connected = nullptr;
	}
	if (m_shm) {
		llshm_close(m_shm);
		m_shm = nullptr;
	}
	m_mt_valid = false;
	LeaveCriticalSection(&m_lock);

	return S_OK;
}

STDMETHODIMP CLensLinkPin::ConnectedTo(IPin **pin)
{
	if (!pin)
		return E_POINTER;
	EnterCriticalSection(&m_lock);
	*pin = m_connected;
	if (*pin)
		(*pin)->AddRef();
	LeaveCriticalSection(&m_lock);
	return *pin ? S_OK : VFW_E_NOT_CONNECTED;
}

STDMETHODIMP CLensLinkPin::ConnectionMediaType(AM_MEDIA_TYPE *mt)
{
	if (!mt)
		return E_POINTER;

	EnterCriticalSection(&m_lock);
	if (!m_mt_valid) {
		LeaveCriticalSection(&m_lock);
		ZeroMemory(mt, sizeof(*mt));
		return VFW_E_NOT_CONNECTED;
	}
	*mt = m_mt;
	if (m_mt.cbFormat) {
		mt->pbFormat = (BYTE *)CoTaskMemAlloc(m_mt.cbFormat);
		if (!mt->pbFormat) {
			LeaveCriticalSection(&m_lock);
			return E_OUTOFMEMORY;
		}
		CopyMemory(mt->pbFormat, m_mt.pbFormat, m_mt.cbFormat);
	}
	if (mt->pUnk)
		mt->pUnk->AddRef();
	LeaveCriticalSection(&m_lock);
	return S_OK;
}

STDMETHODIMP CLensLinkPin::QueryPinInfo(PIN_INFO *info)
{
	if (!info)
		return E_POINTER;
	info->pFilter = static_cast<IBaseFilter *>(m_filter);
	info->pFilter->AddRef();
	info->dir = PINDIR_OUTPUT;
	wcscpy_s(info->achName, MAX_PIN_NAME, L"Capture");
	return S_OK;
}

STDMETHODIMP CLensLinkPin::QueryDirection(PIN_DIRECTION *dir)
{
	if (!dir)
		return E_POINTER;
	*dir = PINDIR_OUTPUT;
	return S_OK;
}

STDMETHODIMP CLensLinkPin::QueryId(LPWSTR *id)
{
	if (!id)
		return E_POINTER;
	const WCHAR name[] = L"Capture";
	*id = (LPWSTR)CoTaskMemAlloc(sizeof(name));
	if (!*id)
		return E_OUTOFMEMORY;
	CopyMemory(*id, name, sizeof(name));
	return S_OK;
}

STDMETHODIMP CLensLinkPin::QueryAccept(const AM_MEDIA_TYPE *mt)
{
	return match_format(mt) >= 0 ? S_OK : S_FALSE;
}

STDMETHODIMP CLensLinkPin::EnumMediaTypes(IEnumMediaTypes **types)
{
	if (!types)
		return E_POINTER;
	*types = new CEnumMediaTypes(0, m_frame_time);
	return *types ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP CLensLinkPin::QueryInternalConnections(IPin **, ULONG *count)
{
	if (count)
		*count = 0;
	return E_NOTIMPL;
}

/* A live source never ends, flushes or segments. */
STDMETHODIMP CLensLinkPin::EndOfStream()
{
	return E_UNEXPECTED;
}
STDMETHODIMP CLensLinkPin::BeginFlush()
{
	return E_UNEXPECTED;
}
STDMETHODIMP CLensLinkPin::EndFlush()
{
	return E_UNEXPECTED;
}
STDMETHODIMP CLensLinkPin::NewSegment(REFERENCE_TIME, REFERENCE_TIME, double)
{
	return S_OK;
}

/* ------------------------------------------------------------------ */
/* IAMStreamConfig */

STDMETHODIMP CLensLinkPin::SetFormat(AM_MEDIA_TYPE *mt)
{
	if (!mt)
		return E_POINTER;
	if (m_filter->State() != State_Stopped)
		return VFW_E_NOT_STOPPED;

	int index = match_format(mt);
	if (index < 0)
		return E_INVALIDARG;

	EnterCriticalSection(&m_lock);
	m_format_index = index;
	if (mt->cbFormat >= sizeof(VIDEOINFOHEADER) && mt->pbFormat) {
		REFERENCE_TIME frame_time =
			((VIDEOINFOHEADER *)mt->pbFormat)->AvgTimePerFrame;
		/* Clamp to 1-120 fps: a zero or absurd value here would
		 * otherwise divide by zero or spin the push thread. */
		if (frame_time >= 83333 && frame_time <= 10000000)
			m_frame_time = frame_time;
	}
	LeaveCriticalSection(&m_lock);

	if (m_shm)
		llshm_set_wanted_format(m_shm,
					(uint32_t)g_formats[index].width,
					(uint32_t)g_formats[index].height,
					(uint32_t)(10000000 / m_frame_time));
	return S_OK;
}

STDMETHODIMP CLensLinkPin::GetFormat(AM_MEDIA_TYPE **mt)
{
	if (!mt)
		return E_POINTER;
	int index = m_format_index >= 0 ? m_format_index : 0;
	*mt = vcam_create_media_type(index, m_frame_time);
	return *mt ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP CLensLinkPin::GetNumberOfCapabilities(int *count, int *size)
{
	if (!count || !size)
		return E_POINTER;
	*count = g_format_count;
	*size = sizeof(VIDEO_STREAM_CONFIG_CAPS);
	return S_OK;
}

STDMETHODIMP CLensLinkPin::GetStreamCaps(int index, AM_MEDIA_TYPE **mt,
					 BYTE *caps)
{
	if (!mt || !caps)
		return E_POINTER;
	if (index < 0 || index >= g_format_count)
		return S_FALSE;

	*mt = vcam_create_media_type(index, m_frame_time);
	if (!*mt)
		return E_OUTOFMEMORY;

	const vcam_format &f = g_formats[index];
	VIDEO_STREAM_CONFIG_CAPS *c = (VIDEO_STREAM_CONFIG_CAPS *)caps;
	ZeroMemory(c, sizeof(*c));
	c->guid = FORMAT_VideoInfo;
	c->VideoStandard = AnalogVideo_None;
	c->InputSize.cx = f.width;
	c->InputSize.cy = f.height;
	c->MinCroppingSize.cx = f.width;
	c->MinCroppingSize.cy = f.height;
	c->MaxCroppingSize.cx = f.width;
	c->MaxCroppingSize.cy = f.height;
	c->CropGranularityX = 1;
	c->CropGranularityY = 1;
	c->MinOutputSize.cx = f.width;
	c->MinOutputSize.cy = f.height;
	c->MaxOutputSize.cx = f.width;
	c->MaxOutputSize.cy = f.height;
	c->OutputGranularityX = 1;
	c->OutputGranularityY = 1;
	/* 1-60 fps, expressed as frame durations (larger = slower). */
	c->MinFrameInterval = 166666;
	c->MaxFrameInterval = 10000000;
	c->MinBitsPerSecond =
		(LONG)(image_bytes(f) * 8);
	c->MaxBitsPerSecond = (LONG)(image_bytes(f) * 8 * 60);
	return S_OK;
}

/* ------------------------------------------------------------------ */
/* IKsPropertySet: only the pin category, which is the one every graph
 * asks for. */

STDMETHODIMP CLensLinkPin::Set(REFGUID, DWORD, void *, DWORD, void *, DWORD)
{
	return E_NOTIMPL;
}

STDMETHODIMP CLensLinkPin::Get(REFGUID set, DWORD id, void *, DWORD,
			       void *data, DWORD data_len, DWORD *returned)
{
	if (!IsEqualGUID(set, AMPROPSETID_Pin))
		return E_PROP_SET_UNSUPPORTED;
	if (id != AMPROPERTY_PIN_CATEGORY)
		return E_PROP_ID_UNSUPPORTED;

	if (returned)
		*returned = sizeof(GUID);
	if (!data)
		return S_OK; /* a size query */
	if (data_len < sizeof(GUID))
		return E_UNEXPECTED;

	*(GUID *)data = PIN_CATEGORY_CAPTURE;
	return S_OK;
}

STDMETHODIMP CLensLinkPin::QuerySupported(REFGUID set, DWORD id,
					  DWORD *support)
{
	if (!IsEqualGUID(set, AMPROPSETID_Pin))
		return E_PROP_SET_UNSUPPORTED;
	if (id != AMPROPERTY_PIN_CATEGORY)
		return E_PROP_ID_UNSUPPORTED;
	if (support)
		*support = KSPROPERTY_SUPPORT_GET;
	return S_OK;
}

STDMETHODIMP CLensLinkPin::Notify(IBaseFilter *, Quality)
{
	/* Nothing to do: a live source at a fixed cadence has no queue to
	 * shorten and no earlier frame to skip to. */
	return S_OK;
}

STDMETHODIMP CLensLinkPin::SetSink(IQualityControl *sink)
{
	m_quality_sink = sink;
	return S_OK;
}

/* ------------------------------------------------------------------ */
/* Streaming */

HRESULT CLensLinkPin::StartStreaming()
{
	EnterCriticalSection(&m_lock);
	bool ready = m_connected && m_input && m_allocator && !m_thread;
	LeaveCriticalSection(&m_lock);
	if (!ready)
		return m_thread ? S_OK : VFW_E_NOT_CONNECTED;

	if (!m_shm)
		m_shm = llshm_open_read();

	HRESULT hr = m_allocator->Commit();
	if (FAILED(hr))
		return hr;

	m_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	if (!m_stop_event)
		return E_OUTOFMEMORY;

	m_thread = CreateThread(nullptr, 0, ThreadProc, this, 0, nullptr);
	if (!m_thread) {
		CloseHandle(m_stop_event);
		m_stop_event = nullptr;
		return E_FAIL;
	}
	return S_OK;
}

HRESULT CLensLinkPin::StopStreaming()
{
	if (m_stop_event)
		SetEvent(m_stop_event);

	if (m_thread) {
		/* The loop checks the event once per frame, so this waits
		 * at most one frame interval. The bound is there so a
		 * wedged downstream Receive() cannot hang the app's shutdown
		 * forever. */
		WaitForSingleObject(m_thread, 3000);
		CloseHandle(m_thread);
		m_thread = nullptr;
	}
	if (m_stop_event) {
		CloseHandle(m_stop_event);
		m_stop_event = nullptr;
	}
	if (m_allocator)
		m_allocator->Decommit();
	return S_OK;
}

DWORD WINAPI CLensLinkPin::ThreadProc(LPVOID param)
{
	/* The push thread makes COM calls downstream, so it needs its own
	 * apartment. MTA: the graph's own streaming threads are MTA and a
	 * source pushing from an STA would marshal every sample. */
	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	((CLensLinkPin *)param)->StreamLoop();
	CoUninitialize();
	return 0;
}

void CLensLinkPin::StreamLoop()
{
	REFERENCE_TIME frame = m_frame_time;
	REFERENCE_TIME position = 0;
	LONGLONG next_tick_ms = (LONGLONG)GetTickCount64();

	while (WaitForSingleObject(m_stop_event, 0) != WAIT_OBJECT_0) {
		IMediaSample *sample = nullptr;
		HRESULT hr = m_allocator->GetBuffer(&sample, nullptr, nullptr,
						    0);
		if (FAILED(hr) || !sample) {
			/* Decommitted underneath us, or the downstream pool
			 * is exhausted: neither is fatal, and retrying beats
			 * tearing the connection down. */
			Sleep(5);
			continue;
		}

		if (FAILED(FillSample(sample))) {
			sample->Release();
			Sleep(5);
			continue;
		}

		REFERENCE_TIME start = position;
		REFERENCE_TIME stop = position + frame;
		sample->SetTime(&start, &stop);
		sample->SetSyncPoint(TRUE);
		position = stop;

		hr = m_input->Receive(sample);
		sample->Release();
		if (FAILED(hr))
			break; /* downstream is gone or refusing; stop */

		if (m_shm)
			llshm_reader_heartbeat(m_shm);

		/* Pace against an absolute schedule rather than sleeping a
		 * fixed interval, so the per-frame work does not make the
		 * camera gradually run slow. */
		next_tick_ms += frame / 10000;
		LONGLONG now_ms = (LONGLONG)GetTickCount64();
		LONGLONG wait = next_tick_ms - now_ms;
		if (wait > 0) {
			if (WaitForSingleObject(m_stop_event, (DWORD)wait) ==
			    WAIT_OBJECT_0)
				break;
		} else if (wait < -1000) {
			/* Fell far behind (the machine slept, or the app
			 * blocked in Receive for a second). Re-anchor
			 * instead of sprinting to catch up. */
			next_tick_ms = now_ms;
		}
	}
}

HRESULT CLensLinkPin::FillSample(IMediaSample *sample)
{
	BYTE *out = nullptr;
	HRESULT hr = sample->GetPointer(&out);
	if (FAILED(hr) || !out)
		return E_FAIL;

	int index = m_format_index >= 0 ? m_format_index : 0;
	const vcam_format &f = g_formats[index];
	const uint32_t width = (uint32_t)f.width;
	const uint32_t height = (uint32_t)f.height;
	const bool want_nv12 = IsEqualGUID(*f.subtype, MEDIASUBTYPE_NV12);
	const size_t nv12_size = (size_t)width * height * 3 / 2;
	const long out_size = image_bytes(f);

	if (sample->GetSize() < out_size)
		return E_FAIL;

	/* NV12 goes straight into the sample; YUY2 needs a staging buffer
	 * to convert from. */
	BYTE *nv12 = out;
	if (!want_nv12) {
		if (m_scratch_size < nv12_size) {
			free(m_scratch);
			m_scratch = (BYTE *)malloc(nv12_size);
			m_scratch_size = m_scratch ? nv12_size : 0;
			if (!m_scratch)
				return E_OUTOFMEMORY;
		}
		nv12 = m_scratch;
	}

	uint32_t got_w = 0, got_h = 0;
	uint64_t pts = 0;
	bool have = m_shm && llshm_read(m_shm, nv12, nv12_size, &got_w, &got_h,
				       &pts) &&
		    got_w == width && got_h == height;

	if (!have) {
		/* No bridge, a stale one, or a size we did not ask for:
		 * show black rather than stale or garbled video. The app
		 * stays connected, so starting the bridge mid-call fixes
		 * itself with no reselection. */
		memset(nv12, 16, (size_t)width * height);
		memset(nv12 + (size_t)width * height, 128,
		       (size_t)width * height / 2);

		/* Re-attach cheaply in case the bridge started after us. */
		if (!m_shm)
			m_shm = llshm_open_read();
	}

	if (!want_nv12) {
		/* NV12 -> YUY2. Chroma is duplicated down the two rows of
		 * each 2x2 block, which is what the vertical subsampling
		 * difference between the formats means. */
		const BYTE *y_plane = nv12;
		const BYTE *uv_plane = nv12 + (size_t)width * height;
		for (uint32_t row = 0; row < height; row++) {
			const BYTE *y = y_plane + (size_t)row * width;
			const BYTE *uv = uv_plane + (size_t)(row / 2) * width;
			BYTE *dst = out + (size_t)row * width * 2;
			for (uint32_t x = 0; x < width; x += 2) {
				dst[x * 2 + 0] = y[x];
				dst[x * 2 + 1] = uv[x];
				dst[x * 2 + 2] = y[x + 1];
				dst[x * 2 + 3] = uv[x + 1];
			}
		}
	}

	sample->SetActualDataLength(out_size);
	return S_OK;
}

/* ------------------------------------------------------------------ */
/* Filter */

CLensLinkFilter::CLensLinkFilter()
	: m_refs(1), m_pin(nullptr), m_state(State_Stopped), m_clock(nullptr),
	  m_graph(nullptr)
{
	InitializeCriticalSection(&m_lock);
	m_name[0] = 0;
	m_pin = new CLensLinkPin(this);
}

CLensLinkFilter::~CLensLinkFilter()
{
	delete m_pin;
	if (m_clock)
		m_clock->Release();
	DeleteCriticalSection(&m_lock);
}

ULONG CLensLinkFilter::InternalAddRef()
{
	return (ULONG)InterlockedIncrement(&m_refs);
}

ULONG CLensLinkFilter::InternalRelease()
{
	LONG refs = InterlockedDecrement(&m_refs);
	if (!refs)
		delete this;
	return (ULONG)refs;
}

HRESULT CLensLinkFilter::InternalQueryInterface(REFIID riid, void **ppv)
{
	if (!ppv)
		return E_POINTER;

	if (IsEqualIID(riid, IID_IUnknown) ||
	    IsEqualIID(riid, IID_IPersist) ||
	    IsEqualIID(riid, IID_IMediaFilter) ||
	    IsEqualIID(riid, IID_IBaseFilter))
		*ppv = static_cast<IBaseFilter *>(this);
	else if (IsEqualIID(riid, IID_IAMFilterMiscFlags))
		*ppv = static_cast<IAMFilterMiscFlags *>(this);
	else {
		*ppv = nullptr;
		return E_NOINTERFACE;
	}

	InternalAddRef();
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::QueryInterface(REFIID riid, void **ppv)
{
	return InternalQueryInterface(riid, ppv);
}

STDMETHODIMP_(ULONG) CLensLinkFilter::AddRef()
{
	return InternalAddRef();
}

STDMETHODIMP_(ULONG) CLensLinkFilter::Release()
{
	return InternalRelease();
}

STDMETHODIMP CLensLinkFilter::GetClassID(CLSID *clsid)
{
	if (!clsid)
		return E_POINTER;
	*clsid = CLSID_LensLinkVCam;
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::Stop()
{
	EnterCriticalSection(&m_lock);
	if (m_state != State_Stopped) {
		m_pin->StopStreaming();
		m_state = State_Stopped;
	}
	LeaveCriticalSection(&m_lock);
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::Pause()
{
	EnterCriticalSection(&m_lock);
	/* A live source produces nothing while paused; GetState says so
	 * with VFW_S_CANT_CUE, which is how a graph knows not to wait for
	 * a preview frame that will never arrive. */
	if (m_state == State_Running)
		m_pin->StopStreaming();
	m_state = State_Paused;
	LeaveCriticalSection(&m_lock);
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::Run(REFERENCE_TIME)
{
	EnterCriticalSection(&m_lock);
	HRESULT hr = S_OK;
	if (m_state != State_Running) {
		hr = m_pin->StartStreaming();
		if (SUCCEEDED(hr))
			m_state = State_Running;
	}
	LeaveCriticalSection(&m_lock);
	return hr;
}

STDMETHODIMP CLensLinkFilter::GetState(DWORD, FILTER_STATE *state)
{
	if (!state)
		return E_POINTER;
	*state = m_state;
	return m_state == State_Paused ? VFW_S_CANT_CUE : S_OK;
}

STDMETHODIMP CLensLinkFilter::SetSyncSource(IReferenceClock *clock)
{
	EnterCriticalSection(&m_lock);
	if (clock)
		clock->AddRef();
	if (m_clock)
		m_clock->Release();
	m_clock = clock;
	LeaveCriticalSection(&m_lock);
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::GetSyncSource(IReferenceClock **clock)
{
	if (!clock)
		return E_POINTER;
	EnterCriticalSection(&m_lock);
	*clock = m_clock;
	if (*clock)
		(*clock)->AddRef();
	LeaveCriticalSection(&m_lock);
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::EnumPins(IEnumPins **enum_pins)
{
	if (!enum_pins)
		return E_POINTER;
	*enum_pins = new CEnumPins(static_cast<IPin *>(m_pin), 0);
	return *enum_pins ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP CLensLinkFilter::FindPin(LPCWSTR id, IPin **pin)
{
	if (!pin)
		return E_POINTER;
	if (!id || wcscmp(id, L"Capture") != 0) {
		*pin = nullptr;
		return VFW_E_NOT_FOUND;
	}
	*pin = static_cast<IPin *>(m_pin);
	(*pin)->AddRef();
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::QueryFilterInfo(FILTER_INFO *info)
{
	if (!info)
		return E_POINTER;
	wcscpy_s(info->achName, MAX_FILTER_NAME, m_name[0]
						 ? m_name
						 : LENSLINK_VCAM_NAME);
	info->pGraph = m_graph;
	if (info->pGraph)
		info->pGraph->AddRef();
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::JoinFilterGraph(IFilterGraph *graph,
					      LPCWSTR name)
{
	/* Deliberately a weak reference: the graph owns the filter, so
	 * holding a count on the graph here would be a cycle neither side
	 * could break. This is what every DirectShow filter does. */
	m_graph = graph;
	if (name)
		wcscpy_s(m_name, 128, name);
	else
		m_name[0] = 0;
	return S_OK;
}

STDMETHODIMP CLensLinkFilter::QueryVendorInfo(LPWSTR *vendor)
{
	if (!vendor)
		return E_POINTER;
	*vendor = nullptr;
	return E_NOTIMPL;
}

STDMETHODIMP_(ULONG) CLensLinkFilter::GetMiscFlags()
{
	return AM_FILTER_MISC_FLAGS_IS_SOURCE;
}
