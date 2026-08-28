/*
 * COM entry points and registration for the virtual camera.
 *
 * Registration is what actually makes the phone appear in Zoom's
 * dropdown, and it is the only part of driverless mode that needs
 * administrator rights — once, at install time. Nothing here runs at
 * capture time.
 */

#include <windows.h>
#include <dshow.h>
#include <initguid.h>
#include <stdio.h>

#include "guids.h"
#include "vcam-filter.h"

static HMODULE g_module;
static LONG g_locks;

void vcam_module_lock(bool lock)
{
	if (lock)
		InterlockedIncrement(&g_locks);
	else
		InterlockedDecrement(&g_locks);
}

/* ------------------------------------------------------------------ */

class CClassFactory : public IClassFactory {
public:
	CClassFactory() : m_refs(1) {}
	virtual ~CClassFactory() {}

	STDMETHODIMP QueryInterface(REFIID riid, void **ppv) override
	{
		if (!ppv)
			return E_POINTER;
		if (IsEqualIID(riid, IID_IUnknown) ||
		    IsEqualIID(riid, IID_IClassFactory)) {
			*ppv = static_cast<IClassFactory *>(this);
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

	STDMETHODIMP CreateInstance(IUnknown *outer, REFIID riid,
				    void **ppv) override
	{
		if (!ppv)
			return E_POINTER;
		*ppv = nullptr;
		/* Aggregation is not supported, and saying so is required
		 * rather than optional. */
		if (outer)
			return CLASS_E_NOAGGREGATION;

		CLensLinkFilter *filter = new CLensLinkFilter();
		if (!filter)
			return E_OUTOFMEMORY;

		HRESULT hr = filter->QueryInterface(riid, ppv);
		filter->Release();
		return hr;
	}

	STDMETHODIMP LockServer(BOOL lock) override
	{
		vcam_module_lock(lock != FALSE);
		return S_OK;
	}

private:
	LONG m_refs;
};

/* ------------------------------------------------------------------ */

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **ppv)
{
	if (!ppv)
		return E_POINTER;
	*ppv = nullptr;

	if (!IsEqualCLSID(clsid, CLSID_LensLinkVCam))
		return CLASS_E_CLASSNOTAVAILABLE;

	CClassFactory *factory = new CClassFactory();
	if (!factory)
		return E_OUTOFMEMORY;

	HRESULT hr = factory->QueryInterface(riid, ppv);
	factory->Release();
	return hr;
}

STDAPI DllCanUnloadNow(void)
{
	return g_locks == 0 ? S_OK : S_FALSE;
}

/* ------------------------------------------------------------------ */
/* Registration */

static void guid_to_string(REFGUID guid, WCHAR *out, size_t count)
{
	swprintf_s(out, count,
		   L"{%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}",
		   guid.Data1, guid.Data2, guid.Data3, guid.Data4[0],
		   guid.Data4[1], guid.Data4[2], guid.Data4[3], guid.Data4[4],
		   guid.Data4[5], guid.Data4[6], guid.Data4[7]);
}

static LONG set_string_value(HKEY key, const WCHAR *name, const WCHAR *value)
{
	return RegSetValueExW(key, name, 0, REG_SZ, (const BYTE *)value,
			      (DWORD)((wcslen(value) + 1) * sizeof(WCHAR)));
}

/* HKCR\CLSID\{ours}\InprocServer32 — the plain COM half. */
static HRESULT register_clsid(void)
{
	WCHAR clsid_str[64];
	guid_to_string(CLSID_LensLinkVCam, clsid_str, 64);

	WCHAR path[MAX_PATH];
	if (!GetModuleFileNameW(g_module, path, MAX_PATH))
		return HRESULT_FROM_WIN32(GetLastError());

	WCHAR key_path[256];
	swprintf_s(key_path, 256, L"CLSID\\%s", clsid_str);

	HKEY key = nullptr;
	LONG rc = RegCreateKeyExW(HKEY_CLASSES_ROOT, key_path, 0, nullptr, 0,
				  KEY_WRITE, nullptr, &key, nullptr);
	if (rc != ERROR_SUCCESS)
		return HRESULT_FROM_WIN32(rc);
	set_string_value(key, nullptr, LENSLINK_VCAM_NAME);

	HKEY server = nullptr;
	rc = RegCreateKeyExW(key, L"InprocServer32", 0, nullptr, 0, KEY_WRITE,
			     nullptr, &server, nullptr);
	if (rc == ERROR_SUCCESS) {
		set_string_value(server, nullptr, path);
		/* "Both" lets the DLL load into whichever apartment the
		 * host app happens to use, which for camera apps is not
		 * predictable. */
		set_string_value(server, L"ThreadingModel", L"Both");
		RegCloseKey(server);
	}
	RegCloseKey(key);
	return rc == ERROR_SUCCESS ? S_OK : HRESULT_FROM_WIN32(rc);
}

static void unregister_clsid(void)
{
	WCHAR clsid_str[64];
	guid_to_string(CLSID_LensLinkVCam, clsid_str, 64);

	WCHAR key_path[256];
	swprintf_s(key_path, 256, L"CLSID\\%s\\InprocServer32", clsid_str);
	RegDeleteKeyW(HKEY_CLASSES_ROOT, key_path);

	swprintf_s(key_path, 256, L"CLSID\\%s", clsid_str);
	RegDeleteKeyW(HKEY_CLASSES_ROOT, key_path);
}

/*
 * The half that makes it a *camera*: an entry under the video input
 * device category, which is what every app enumerates.
 *
 * IFilterMapper2 rather than hand-written keys because it also
 * generates the binary FilterData blob describing our pin and media
 * types. Apps use that blob to list a camera's capabilities without
 * instantiating it; a hand-rolled one that is subtly wrong produces a
 * camera that appears in the list and then fails to open.
 */
static HRESULT register_filter(void)
{
	IFilterMapper2 *mapper = nullptr;
	HRESULT hr = CoCreateInstance(CLSID_FilterMapper2, nullptr,
				      CLSCTX_INPROC_SERVER, IID_IFilterMapper2,
				      (void **)&mapper);
	if (FAILED(hr))
		return hr;

	REGPINTYPES pin_types[8];
	int type_count = 0;
	/* One entry per distinct subtype; the mapper describes formats,
	 * not individual resolutions. */
	pin_types[type_count].clsMajorType = &MEDIATYPE_Video;
	pin_types[type_count].clsMinorType = &MEDIASUBTYPE_NV12;
	type_count++;
	pin_types[type_count].clsMajorType = &MEDIATYPE_Video;
	pin_types[type_count].clsMinorType = &MEDIASUBTYPE_YUY2;
	type_count++;

	REGFILTERPINS pin = {};
	pin.strName = const_cast<LPWSTR>(L"Capture");
	pin.bRendered = FALSE;
	pin.bOutput = TRUE;
	pin.bZero = FALSE;
	pin.bMany = FALSE;
	pin.clsConnectsToFilter = &CLSID_NULL;
	pin.strConnectsToPin = nullptr;
	pin.nMediaTypes = (UINT)type_count;
	pin.lpMediaType = pin_types;

	REGFILTER2 filter = {};
	filter.dwVersion = 1;
	/* MERIT_DO_NOT_USE keeps the graph builder from silently choosing
	 * this camera when an app asks for "any" video source. A user
	 * picking it by name still works, which is the only way anyone
	 * should end up on it. */
	filter.dwMerit = MERIT_DO_NOT_USE;
	filter.cPins = 1;
	filter.rgPins = &pin;

	hr = mapper->RegisterFilter(CLSID_LensLinkVCam, LENSLINK_VCAM_NAME,
				    nullptr, &CLSID_VideoInputDeviceCategory,
				    nullptr, &filter);
	mapper->Release();
	return hr;
}

static HRESULT unregister_filter(void)
{
	IFilterMapper2 *mapper = nullptr;
	HRESULT hr = CoCreateInstance(CLSID_FilterMapper2, nullptr,
				      CLSCTX_INPROC_SERVER, IID_IFilterMapper2,
				      (void **)&mapper);
	if (FAILED(hr))
		return hr;

	hr = mapper->UnregisterFilter(&CLSID_VideoInputDeviceCategory,
				      LENSLINK_VCAM_NAME, CLSID_LensLinkVCam);
	mapper->Release();
	return hr;
}

STDAPI DllRegisterServer(void)
{
	HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	bool initialised = SUCCEEDED(hr);

	hr = register_clsid();
	if (SUCCEEDED(hr))
		hr = register_filter();

	/* A half-registration is worse than none: it leaves a camera in
	 * the list that cannot be opened. */
	if (FAILED(hr)) {
		unregister_filter();
		unregister_clsid();
	}

	if (initialised)
		CoUninitialize();
	return hr;
}

STDAPI DllUnregisterServer(void)
{
	HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	bool initialised = SUCCEEDED(hr);

	unregister_filter();
	unregister_clsid();

	if (initialised)
		CoUninitialize();
	return S_OK;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH) {
		g_module = (HMODULE)instance;
		DisableThreadLibraryCalls(instance);
	}
	return TRUE;
}
