/*
 * A DirectShow capture source filter, hand-rolled.
 *
 * No strmbase: the DirectShow base classes ship as sample *source* that
 * has to be compiled per toolchain and dragged along, and what they
 * provide here is one output pin and a push thread. The COM plumbing
 * below is the part they would have hidden — reference counting, the
 * two enumerators, allocator negotiation and the pin connection dance.
 *
 * Shape:
 *
 *   Zoom (or any app)
 *     └── loads lenslink-vcam.dll into its own process
 *          └── CLensLinkFilter ── CLensLinkPin ──push──▶ the app
 *                                      │
 *                                      └── reads shared memory ◀── lenslink-bridge.exe
 *
 * The filter never talks to the phone. It reads whatever the bridge
 * last published, and emits a black frame when the bridge is not
 * running — which is exactly what a webcam with the lens cap on would
 * do, and better than failing to connect.
 */

#pragma once

#include <windows.h>
#include <dshow.h>

extern "C" {
#include "frame-shm.h"
}

/* Advertised formats. Deliberately short: every entry is a row in the
 * user's resolution dropdown, and a virtual camera offering a dozen
 * near-identical modes is worse than one offering three. */
struct vcam_format {
	int width;
	int height;
	const GUID *subtype;
};

extern const vcam_format g_formats[];
extern const int g_format_count;

/* 30 fps in 100 ns units — the DirectShow unit for frame duration. */
#define VCAM_DEFAULT_FRAME_TIME 333333

class CLensLinkFilter;

/*
 * The output pin: media-type negotiation, the allocator handshake, and
 * the thread that pushes samples downstream.
 *
 * Lifetime is the filter's — the pin is a member, and its reference
 * count delegates to the filter, which is the usual arrangement for a
 * pin that cannot outlive its owner.
 */
class CLensLinkPin : public IPin,
		     public IAMStreamConfig,
		     public IKsPropertySet,
		     public IQualityControl {
public:
	explicit CLensLinkPin(CLensLinkFilter *filter);
	/* Virtual because these are deleted through their own type but
	 * carry vtables; without it every compiler warns, rightly. */
	virtual ~CLensLinkPin();

	/* IUnknown — delegates its count to the filter. */
	STDMETHODIMP QueryInterface(REFIID riid, void **ppv) override;
	STDMETHODIMP_(ULONG) AddRef() override;
	STDMETHODIMP_(ULONG) Release() override;

	/* IPin */
	STDMETHODIMP Connect(IPin *receive, const AM_MEDIA_TYPE *mt) override;
	STDMETHODIMP ReceiveConnection(IPin *connector,
				       const AM_MEDIA_TYPE *mt) override;
	STDMETHODIMP Disconnect() override;
	STDMETHODIMP ConnectedTo(IPin **pin) override;
	STDMETHODIMP ConnectionMediaType(AM_MEDIA_TYPE *mt) override;
	STDMETHODIMP QueryPinInfo(PIN_INFO *info) override;
	STDMETHODIMP QueryDirection(PIN_DIRECTION *dir) override;
	STDMETHODIMP QueryId(LPWSTR *id) override;
	STDMETHODIMP QueryAccept(const AM_MEDIA_TYPE *mt) override;
	STDMETHODIMP EnumMediaTypes(IEnumMediaTypes **types) override;
	STDMETHODIMP QueryInternalConnections(IPin **pins,
					      ULONG *count) override;
	STDMETHODIMP EndOfStream() override;
	STDMETHODIMP BeginFlush() override;
	STDMETHODIMP EndFlush() override;
	STDMETHODIMP NewSegment(REFERENCE_TIME start, REFERENCE_TIME stop,
				double rate) override;

	/* IAMStreamConfig — the app's resolution picker. */
	STDMETHODIMP SetFormat(AM_MEDIA_TYPE *mt) override;
	STDMETHODIMP GetFormat(AM_MEDIA_TYPE **mt) override;
	STDMETHODIMP GetNumberOfCapabilities(int *count, int *size) override;
	STDMETHODIMP GetStreamCaps(int index, AM_MEDIA_TYPE **mt,
				   BYTE *caps) override;

	/* IKsPropertySet — how a graph asks "what kind of pin are you?".
	 * Answering PIN_CATEGORY_CAPTURE is what makes this a camera
	 * rather than an anonymous source. */
	STDMETHODIMP Set(REFGUID set, DWORD id, void *instance,
			 DWORD instance_len, void *data, DWORD data_len) override;
	STDMETHODIMP Get(REFGUID set, DWORD id, void *instance,
			 DWORD instance_len, void *data, DWORD data_len,
			 DWORD *returned) override;
	STDMETHODIMP QuerySupported(REFGUID set, DWORD id,
				    DWORD *support) override;

	/* IQualityControl — downstream congestion reports. Honoured by
	 * doing nothing: this is a live source with a fixed cadence and
	 * nothing to drop or slow down. */
	STDMETHODIMP Notify(IBaseFilter *self, Quality q) override;
	STDMETHODIMP SetSink(IQualityControl *sink) override;

	HRESULT StartStreaming();
	HRESULT StopStreaming();
	bool IsConnected() const { return m_connected != nullptr; }

private:
	static DWORD WINAPI ThreadProc(LPVOID param);
	void StreamLoop();
	HRESULT FillSample(IMediaSample *sample);
	HRESULT NegotiateAllocator(IMemInputPin *input);

	CLensLinkFilter *m_filter;
	IPin *m_connected;
	IMemInputPin *m_input;
	IMemAllocator *m_allocator;
	IQualityControl *m_quality_sink;

	AM_MEDIA_TYPE m_mt;      /* the negotiated type */
	bool m_mt_valid;
	int m_format_index;      /* into g_formats; -1 = not chosen */
	REFERENCE_TIME m_frame_time;

	HANDLE m_thread;
	HANDLE m_stop_event;

	struct llshm *m_shm;
	BYTE *m_scratch;         /* NV12 staging when the app wants YUY2 */
	size_t m_scratch_size;

	CRITICAL_SECTION m_lock;
};

class CLensLinkFilter : public IBaseFilter, public IAMFilterMiscFlags {
public:
	CLensLinkFilter();
	virtual ~CLensLinkFilter();

	STDMETHODIMP QueryInterface(REFIID riid, void **ppv) override;
	STDMETHODIMP_(ULONG) AddRef() override;
	STDMETHODIMP_(ULONG) Release() override;

	/* IPersist / IMediaFilter / IBaseFilter */
	STDMETHODIMP GetClassID(CLSID *clsid) override;
	STDMETHODIMP Stop() override;
	STDMETHODIMP Pause() override;
	STDMETHODIMP Run(REFERENCE_TIME start) override;
	STDMETHODIMP GetState(DWORD msecs, FILTER_STATE *state) override;
	STDMETHODIMP SetSyncSource(IReferenceClock *clock) override;
	STDMETHODIMP GetSyncSource(IReferenceClock **clock) override;
	STDMETHODIMP EnumPins(IEnumPins **enum_pins) override;
	STDMETHODIMP FindPin(LPCWSTR id, IPin **pin) override;
	STDMETHODIMP QueryFilterInfo(FILTER_INFO *info) override;
	STDMETHODIMP JoinFilterGraph(IFilterGraph *graph, LPCWSTR name) override;
	STDMETHODIMP QueryVendorInfo(LPWSTR *vendor) override;

	/* IAMFilterMiscFlags: declaring ourselves a source is what stops
	 * a graph from trying to find something upstream of us. */
	STDMETHODIMP_(ULONG) GetMiscFlags() override;

	CLensLinkPin *Pin() { return m_pin; }
	FILTER_STATE State() const { return m_state; }
	IReferenceClock *Clock() { return m_clock; }

	/* Shared by the pin's IUnknown, which delegates here. */
	ULONG InternalAddRef();
	ULONG InternalRelease();
	HRESULT InternalQueryInterface(REFIID riid, void **ppv);

private:
	LONG m_refs;
	CLensLinkPin *m_pin;
	FILTER_STATE m_state;
	IReferenceClock *m_clock;
	IFilterGraph *m_graph;
	WCHAR m_name[128];
	CRITICAL_SECTION m_lock;
};

/* Media-type helpers, shared with dllmain.cpp's registration. */
void vcam_free_media_type(AM_MEDIA_TYPE *mt);
AM_MEDIA_TYPE *vcam_create_media_type(int format_index,
				      REFERENCE_TIME frame_time);
