// dcomp_csp.cpp: a DirectComposition shim for CSP/WebView2 on Wine

#define WIN32_LEAN_AND_MEAN
#define INITGUID
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dcomp.h>

#include <vector>
#include <cstdio>

/* MinGW's dcomp.h is incomplete, so all IIDs are hardcoded. */
static const GUID MY_IID_IDCompositionVisual =
    {0x4d93059d,0x097b,0x4651,{0x9a,0x60,0xf0,0xf2,0x51,0x16,0xe2,0xf3}};
static const GUID MY_IID_IDCompositionVisual2 =
    {0xe8de1639,0x4331,0x4b26,{0xbc,0x5f,0x6a,0x32,0x1d,0x34,0x7a,0x85}};
static const GUID MY_IID_IDCompositionTarget =
    {0xeacdd04c,0x117e,0x4e17,{0x88,0xf4,0xd1,0xb1,0x2b,0x0e,0x3d,0x89}};
static const GUID MY_IID_IDCompositionDevice2 =
    {0x75f6468d,0x1b8e,0x447c,{0x9b,0xc6,0x75,0xfe,0xa8,0x0b,0x5b,0x25}};
static const GUID MY_IID_IDCompositionDesktopDevice =
    {0x5f4633fe,0x1e08,0x4cb8,{0x8c,0x75,0xce,0x24,0x33,0x3f,0x56,0x02}};
static const GUID MY_IID_IDCompositionSurface =
    {0xbb8a4953,0x2c99,0x4f5a,{0x96,0xf5,0x48,0x19,0x02,0x7f,0xa3,0xac}};
static const GUID MY_IID_ID3D11Device =
    {0xdb6f6ddb,0xac77,0x4e88,{0x82,0x53,0x81,0x9d,0xf9,0xbb,0xf1,0x40}};
static const GUID MY_IID_IDXGIDevice =
    {0x54ec77fa,0x1377,0x44e6,{0x8c,0x32,0x88,0xfd,0x5f,0x44,0xc8,0x4c}};
static const GUID MY_IID_IDXGIFactory2 =
    {0x50c83a1c,0xe072,0x4c48,{0x87,0xb0,0x36,0x30,0xfa,0x36,0xa6,0xd0}};
static const GUID MY_IID_ID3D11Texture2D =
    {0x6f15aaf2,0xd208,0x4e89,{0x9a,0xb4,0x48,0x95,0x35,0xd3,0x4f,0x9c}};
static const GUID MY_IID_IDXGISurface =
    {0xcafcb56c,0x6ac3,0x4889,{0xbf,0x47,0x9e,0x23,0xbb,0xd2,0x60,0xec}};
static const GUID MY_IID_IDXGISwapChain1 =
    {0x790a45f7,0x0d42,0x4876,{0x98,0x3a,0x0a,0x55,0xcf,0xe6,0xf4,0xaa}};
static const GUID MY_IID_IDXGIAdapter =
    {0x2411e7e1,0x12ac,0x4ccf,{0xbd,0x14,0x97,0x98,0xe8,0x53,0x4d,0xc0}};
static const GUID MY_IID_IDXGISwapChain =
    {0x310d36a0,0xd2e7,0x4c0a,{0xaa,0x04,0x6a,0x9d,0x23,0xb8,0x88,0x6a}};

/* Debug log */
static FILE *gLog = nullptr;

static void log_open()
{
    if (!gLog) gLog = fopen("C:\\dcomp-csp.log", "a");
}

#define LOG(fmt, ...) do { log_open(); if (gLog) { \
    fprintf(gLog, "[dcomp] " fmt "\n", ##__VA_ARGS__); fflush(gLog); } } while(0)

/* Forward declarations */
struct FakeDevice;
struct FakeTarget;
struct FakeVisual;
struct FakeSurface;
struct FakeCompositionSwapChain;

static ID3D11Device    *g_d3dDev  = nullptr;
static IDXGIFactory2   *g_factory = nullptr;

/* FakeCompositionSwapChain : IDXGISwapChain1 , backs CreateSwapChainForComposition, no HWND, just a texture */
struct FakeCompositionSwapChain final : IDXGISwapChain1
{
    volatile LONG        ref = 1;
    ID3D11Device        *dev;
    ID3D11Texture2D     *tex    = nullptr;
    DXGI_SWAP_CHAIN_DESC1 desc1 = {};
    FakeCompositionSwapChain(ID3D11Device *d, const DXGI_SWAP_CHAIN_DESC1 *pd)
        : dev(d) { dev->AddRef(); desc1 = *pd; create_tex(); }

    ~FakeCompositionSwapChain() { if (tex) tex->Release(); dev->Release(); }

    void create_tex()
    {
        if (tex) { tex->Release(); tex = nullptr; }
        UINT w = desc1.Width  ? desc1.Width  : 1;
        UINT h = desc1.Height ? desc1.Height : 1;
        D3D11_TEXTURE2D_DESC td = {};
        td.Width = w; td.Height = h;
        td.MipLevels = 1; td.ArraySize = 1;
        td.Format    = desc1.Format ? desc1.Format : DXGI_FORMAT_B8G8R8A8_UNORM;
        td.SampleDesc.Count = 1;
        td.Usage     = D3D11_USAGE_DEFAULT;
        td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
        HRESULT hr = dev->CreateTexture2D(&td, nullptr, &tex);
        LOG("FakeCompositionSwapChain create_tex %ux%u -> %08lx", w, h, hr);
    }

    /* IUnknown */
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override
    {
        if (IsEqualIID(riid, IID_IUnknown)
         || IsEqualIID(riid, MY_IID_IDXGISwapChain)
         || IsEqualIID(riid, MY_IID_IDXGISwapChain1))
        { *ppv = static_cast<IDXGISwapChain1*>(this); AddRef(); return S_OK; }
        if (tex) {
            HRESULT hr = tex->QueryInterface(riid, ppv);
            if (SUCCEEDED(hr)) return hr;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override
    { ULONG r = InterlockedDecrement(&ref); if (r==0) delete this; return r; }

    /* IDXGIObject */
    HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID,UINT,const void*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID,const IUnknown*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID,UINT*,void*) override { return DXGI_ERROR_NOT_FOUND; }
    HRESULT STDMETHODCALLTYPE GetParent(REFIID,void**ppv) override { *ppv=nullptr; return E_FAIL; }

    /* IDXGIDeviceSubObject */
    HRESULT STDMETHODCALLTYPE GetDevice(REFIID riid, void **ppv) override
    { return dev->QueryInterface(riid, ppv); }

    /* IDXGISwapChain */
    HRESULT STDMETHODCALLTYPE Present(UINT,UINT) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetBuffer(UINT buf, REFIID riid, void **ppSurface) override
    {
        if (!tex || buf != 0) { *ppSurface = nullptr; return DXGI_ERROR_INVALID_CALL; }
        return tex->QueryInterface(riid, ppSurface);
    }
    HRESULT STDMETHODCALLTYPE SetFullscreenState(BOOL,IDXGIOutput*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetFullscreenState(BOOL *pF,IDXGIOutput**ppOut) override
    { if(pF)*pF=FALSE; if(ppOut)*ppOut=nullptr; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetDesc(DXGI_SWAP_CHAIN_DESC *pd) override
    {
        if (!pd) return E_INVALIDARG;
        ZeroMemory(pd, sizeof(*pd));
        pd->BufferDesc.Width  = desc1.Width;
        pd->BufferDesc.Height = desc1.Height;
        pd->BufferDesc.Format = desc1.Format;
        pd->SampleDesc        = desc1.SampleDesc;
        pd->BufferUsage       = desc1.BufferUsage;
        pd->BufferCount       = desc1.BufferCount;
        pd->Windowed          = TRUE;
        pd->SwapEffect        = desc1.SwapEffect;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE ResizeBuffers(UINT,UINT w,UINT h,DXGI_FORMAT f,UINT) override
    {
        if (w) desc1.Width  = w;
        if (h) desc1.Height = h;
        if (f != DXGI_FORMAT_UNKNOWN) desc1.Format = f;
        create_tex(); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE ResizeTarget(const DXGI_MODE_DESC*)     override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetContainingOutput(IDXGIOutput**ppOut) override { *ppOut=nullptr; return E_FAIL; }
    HRESULT STDMETHODCALLTYPE GetFrameStatistics(DXGI_FRAME_STATISTICS*ps) override
    { if(ps) ZeroMemory(ps,sizeof(*ps)); return S_OK; }
    HRESULT STDMETHODCALLTYPE GetLastPresentCount(UINT*p) override { if(p)*p=0; return S_OK; }

    /* IDXGISwapChain1 */
    HRESULT STDMETHODCALLTYPE GetDesc1(DXGI_SWAP_CHAIN_DESC1 *pd) override
    { if(!pd) return E_INVALIDARG; *pd = desc1; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetFullscreenDesc(DXGI_SWAP_CHAIN_FULLSCREEN_DESC*pd) override
    { if(pd) ZeroMemory(pd,sizeof(*pd)); return S_OK; }
    HRESULT STDMETHODCALLTYPE GetHwnd(HWND *ph) override { if(ph)*ph=nullptr; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetCoreWindow(REFIID,void**ppv) override { *ppv=nullptr; return E_FAIL; }
    HRESULT STDMETHODCALLTYPE Present1(UINT si,UINT f,const DXGI_PRESENT_PARAMETERS*) override
    { return Present(si,f); }
    BOOL STDMETHODCALLTYPE IsTemporaryMonoSupported() override { return FALSE; }
    HRESULT STDMETHODCALLTYPE GetRestrictToOutput(IDXGIOutput**ppOut) override { *ppOut=nullptr; return E_FAIL; }
    HRESULT STDMETHODCALLTYPE SetBackgroundColor(const DXGI_RGBA*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetBackgroundColor(DXGI_RGBA*pc) override
    { if(pc) ZeroMemory(pc,sizeof(*pc)); return S_OK; }
    HRESULT STDMETHODCALLTYPE SetRotation(DXGI_MODE_ROTATION) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetRotation(DXGI_MODE_ROTATION*pr) override
    { if(pr)*pr=DXGI_MODE_ROTATION_IDENTITY; return S_OK; }
};

/* Vtable hooks for IDXGIFactory2:
 * [24] CreateSwapChainForComposition -> DXVK returns E_NOTIMPL; we return a FakeCompositionSwapChain.
 * [15] CreateSwapChainForHwnd        -> passthrough with logging.
 * [10] CreateSwapChain               -> passthrough with logging. */

/* --- CreateSwapChainForComposition hook --- */
typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateSwapChainForComposition)(
    IDXGIFactory2*, IUnknown*, const DXGI_SWAP_CHAIN_DESC1*,
    IDXGIOutput*, IDXGISwapChain1**);

static PFN_CreateSwapChainForComposition g_origCSFC = nullptr;
static bool g_hooked = false;

static HRESULT STDMETHODCALLTYPE hooked_CreateSwapChainForComposition(
    IDXGIFactory2 *This, IUnknown *pDevice,
    const DXGI_SWAP_CHAIN_DESC1 *pDesc, IDXGIOutput *,
    IDXGISwapChain1 **ppSwapChain)
{
    LOG("CreateSwapChainForComposition %ux%u fmt=%d",
        pDesc ? pDesc->Width : 0, pDesc ? pDesc->Height : 0,
        pDesc ? pDesc->Format : 0);

    if (!pDesc || !ppSwapChain) return E_INVALIDARG;

    ID3D11Device *d3d = nullptr;
    if (pDevice) pDevice->QueryInterface(MY_IID_ID3D11Device, (void**)&d3d);
    if (!d3d)    { d3d = g_d3dDev; if (d3d) d3d->AddRef(); }
    if (!d3d)    { *ppSwapChain = nullptr; return E_FAIL; }

    *ppSwapChain = new FakeCompositionSwapChain(d3d, pDesc);
    d3d->Release();
    LOG("  -> FakeCompositionSwapChain %p", *ppSwapChain);
    return S_OK;
}

/* CreateSwapChainForHwnd hook: passthrough with logging */
typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateSwapChainForHwnd)(
    IDXGIFactory2*, IUnknown*, HWND, const DXGI_SWAP_CHAIN_DESC1*,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC*, IDXGIOutput*, IDXGISwapChain1**);

static PFN_CreateSwapChainForHwnd g_origCSFH = nullptr;

static HRESULT STDMETHODCALLTYPE hooked_CreateSwapChainForHwnd(
    IDXGIFactory2 *This, IUnknown *pDevice, HWND hWnd,
    const DXGI_SWAP_CHAIN_DESC1 *pDesc,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC *pFSD,
    IDXGIOutput *pOut, IDXGISwapChain1 **ppSwapChain)
{
    LOG("CreateSwapChainForHwnd hwnd=%p %ux%u", hWnd,
        pDesc ? pDesc->Width : 0, pDesc ? pDesc->Height : 0);
    return g_origCSFH(This, pDevice, hWnd, pDesc, pFSD, pOut, ppSwapChain);
}

/* CreateSwapChain hook (legacy DXGI 1.0): passthrough with logging */
typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateSwapChain)(
    IDXGIFactory*, IUnknown*, DXGI_SWAP_CHAIN_DESC*, IDXGISwapChain**);

static PFN_CreateSwapChain g_origCS = nullptr;

static HRESULT STDMETHODCALLTYPE hooked_CreateSwapChain(
    IDXGIFactory *This, IUnknown *pDevice,
    DXGI_SWAP_CHAIN_DESC *pDesc, IDXGISwapChain **ppSwapChain)
{
    HWND hWnd = pDesc ? pDesc->OutputWindow : nullptr;
    LOG("CreateSwapChain hwnd=%p %ux%u", hWnd,
        pDesc ? pDesc->BufferDesc.Width : 0, pDesc ? pDesc->BufferDesc.Height : 0);
    return g_origCS(This, pDevice, pDesc, ppSwapChain);
}

static void install_hook(IDXGIFactory2 *factory)
{
    if (g_hooked || !factory) return;
    void **vtbl = *(void***)factory;
    DWORD old = 0;

    /* Hook CreateSwapChain (vtbl[10]) , legacy DXGI 1.0 */
    if (VirtualProtect(&vtbl[10], sizeof(void*), PAGE_READWRITE, &old)) {
        g_origCS = (PFN_CreateSwapChain)vtbl[10];
        vtbl[10] = (void*)hooked_CreateSwapChain;
        VirtualProtect(&vtbl[10], sizeof(void*), old, &old);
    } else {
        LOG("hook: VirtualProtect[10] failed %lu", GetLastError());
    }

    /* Hook CreateSwapChainForComposition (vtbl[24]) */
    if (VirtualProtect(&vtbl[24], sizeof(void*), PAGE_READWRITE, &old)) {
        g_origCSFC = (PFN_CreateSwapChainForComposition)vtbl[24];
        vtbl[24]   = (void*)hooked_CreateSwapChainForComposition;
        VirtualProtect(&vtbl[24], sizeof(void*), old, &old);
    } else {
        LOG("hook: VirtualProtect[24] failed %lu", GetLastError()); return;
    }

    /* Hook CreateSwapChainForHwnd (vtbl[15]) */
    if (VirtualProtect(&vtbl[15], sizeof(void*), PAGE_READWRITE, &old)) {
        g_origCSFH = (PFN_CreateSwapChainForHwnd)vtbl[15];
        vtbl[15]   = (void*)hooked_CreateSwapChainForHwnd;
        VirtualProtect(&vtbl[15], sizeof(void*), old, &old);
    } else {
        LOG("hook: VirtualProtect[15] failed %lu", GetLastError());
    }

    g_hooked = true;
    LOG("hooks installed: vtbl[10]=CreateSwapChain vtbl[15]=CreateSwapChainForHwnd vtbl[24]=CreateSwapChainForComposition");
}

/* FakeVisual : IDCompositionVisual2 */
struct FakeVisual final : IDCompositionVisual2
{
    volatile LONG ref = 1;
    IUnknown   *content  = nullptr;
    std::vector<FakeVisual *> children;

    FakeVisual() = default;
    ~FakeVisual()
    {
        if (content) content->Release();
        for (auto *c : children) c->Release();
    }

    /* IUnknown */
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override
    {
        LOG("Visual::QI %08lx-%04x-%04x-%02x%02x",
            riid.Data1, riid.Data2, riid.Data3, riid.Data4[0], riid.Data4[1]);
        if (IsEqualIID(riid, IID_IUnknown)
         || IsEqualIID(riid, MY_IID_IDCompositionVisual)
         || IsEqualIID(riid, MY_IID_IDCompositionVisual2))
        {
            *ppv = static_cast<IDCompositionVisual2 *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override
    {
        ULONG r = InterlockedDecrement(&ref);
        if (r == 0) delete this;
        return r;
    }
    /* IDCompositionVisual: MinGW overload order differs from MSVC, but all stubs return S_OK so the mismatch is harmless */
    HRESULT STDMETHODCALLTYPE SetOffsetX(IDCompositionAnimation *)      override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetOffsetX(float)                         override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetOffsetY(IDCompositionAnimation *)      override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetOffsetY(float)                         override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetTransform(IDCompositionTransform *)    override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetTransform(const D2D_MATRIX_3X2_F &)   override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetTransformParent(IDCompositionVisual *) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetEffect(IDCompositionEffect *)          override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetBitmapInterpolationMode(DCOMPOSITION_BITMAP_INTERPOLATION_MODE) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetBorderMode(DCOMPOSITION_BORDER_MODE)  override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetClip(IDCompositionClip *)              override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetClip(const D2D_RECT_F &)              override { return S_OK; }

    HRESULT STDMETHODCALLTYPE SetContent(IUnknown *c) override
    {
        LOG("Visual::SetContent(%p)", c);
        if (content) content->Release();
        content = c;
        if (c) c->AddRef();
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE AddVisual(IDCompositionVisual *child, BOOL above,
                                        IDCompositionVisual * /*ref*/) override
    {
        if (!child) return E_INVALIDARG;
        auto *fv = static_cast<FakeVisual *>(child);
        fv->AddRef();
        if (above) children.push_back(fv);
        else       children.insert(children.begin(), fv);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE RemoveVisual(IDCompositionVisual *child) override
    {
        for (auto it = children.begin(); it != children.end(); ++it)
            if (*it == child) { (*it)->Release(); children.erase(it); break; }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE RemoveAllVisuals() override
    {
        for (auto *c : children) c->Release();
        children.clear();
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetCompositeMode(DCOMPOSITION_COMPOSITE_MODE) override { return S_OK; }

    /* IDCompositionVisual2 */
    HRESULT STDMETHODCALLTYPE SetOpacityMode(DCOMPOSITION_OPACITY_MODE)           override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SetBackFaceVisibility(DCOMPOSITION_BACKFACE_VISIBILITY) override { return S_OK; }
};

/* FakeTarget : IDCompositionTarget */
struct FakeTarget final : IDCompositionTarget
{
    volatile LONG ref = 1;
    HWND               hwnd      = nullptr;
    DWORD              exstyle   = 0;
    bool               inPopupTree = false;
    ID3D11Device      *d3dDev    = nullptr;
    FakeVisual        *root      = nullptr;
    ID3D11Texture2D   *stagingTex = nullptr;
    UINT               stagingW  = 0, stagingH = 0;
    BYTE              *gdiBuf    = nullptr;   /* contiguous BGRA row buffer */

    FakeTarget(HWND h)
        : hwnd(h), exstyle(h ? GetWindowLong(h, GWL_EXSTYLE) : 0)
    {
        /* Walk the parent chain: if any ancestor has WS_EX_NOREDIRECTIONBITMAP
           OR is the E583090D outer-popup class (wine 10.x doesn't propagate NRB
           down into child windows), this target belongs to a popup subtree. */
        for (HWND w = h; w; w = GetParent(w)) {
            if (GetWindowLong(w, GWL_EXSTYLE) & WS_EX_NOREDIRECTIONBITMAP) {
                inPopupTree = true;
                break;
            }
            char wcls[256] = {};
            GetClassNameA(w, wcls, sizeof(wcls));
            if (strstr(wcls, "E583090D")) {
                inPopupTree = true;
                break;
            }
        }
        LOG("FakeTarget hwnd=%p inPopupTree=%d ex=%08lx", h, (int)inPopupTree, exstyle);
    }
    ~FakeTarget()
    {
        if (root)       root->Release();
        if (stagingTex) stagingTex->Release();
        if (d3dDev)     d3dDev->Release();
        free(gdiBuf);
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override
    {
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, MY_IID_IDCompositionTarget)) {
            *ppv = static_cast<IDCompositionTarget *>(this);
            AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override
    {
        ULONG r = InterlockedDecrement(&ref);
        if (r == 0) delete this;
        return r;
    }

    HRESULT STDMETHODCALLTYPE SetRoot(IDCompositionVisual *visual) override
    {
        LOG("Target::SetRoot(%p)", visual);
        if (root) root->Release();
        root = static_cast<FakeVisual *>(visual);
        if (root) root->AddRef();
        return S_OK;
    }

    /* GDI-based blit: GPU texture → staging → Map → BitBlt to HWND DC.
       This bypasses DXGI swap-chain-for-HWND entirely, avoiding the issue
       where wine's compositor overwrites the Vulkan surface with the GDI
       window surface (showing black).  GDI goes through wine's own path
       and therefore sticks. */
    bool commit_texture(ID3D11Texture2D *src)
    {
        if (!src || !hwnd) return false;
        if (!d3dDev) src->GetDevice(&d3dDev);
        if (!d3dDev) return false;

        D3D11_TEXTURE2D_DESC sd = {};
        src->GetDesc(&sd);
        UINT w = sd.Width, h = sd.Height;
        if (w == 0 || h == 0) return false;

        /* (Re-)create staging texture when size changes */
        if (!stagingTex || stagingW != w || stagingH != h) {
            if (stagingTex) { stagingTex->Release(); stagingTex = nullptr; }
            free(gdiBuf); gdiBuf = nullptr;

            D3D11_TEXTURE2D_DESC td = {};
            td.Width  = w; td.Height = h;
            td.MipLevels = 1; td.ArraySize = 1;
            td.Format    = DXGI_FORMAT_B8G8R8A8_UNORM;
            td.SampleDesc.Count = 1;
            td.Usage          = D3D11_USAGE_STAGING;
            td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            if (FAILED(d3dDev->CreateTexture2D(&td, nullptr, &stagingTex)))
                return false;
            gdiBuf = (BYTE *)malloc(w * h * 4);
            if (!gdiBuf) return false;
            stagingW = w; stagingH = h;
            LOG("staging tex %ux%u for hwnd=%p", w, h, hwnd);
        }

        /* GPU copy src → staging, then read back */
        ID3D11DeviceContext *ctx = nullptr;
        d3dDev->GetImmediateContext(&ctx);
        ctx->CopyResource(stagingTex, src);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        HRESULT hr = ctx->Map(stagingTex, 0, D3D11_MAP_READ, 0, &mapped);
        ctx->Release();
        if (FAILED(hr)) return false;

        /* Compact rows if GPU pitch differs from width*4 */
        UINT rowBytes = w * 4;
        if (mapped.RowPitch == rowBytes) {
            memcpy(gdiBuf, mapped.pData, rowBytes * h);
        } else {
            const BYTE *s = (const BYTE *)mapped.pData;
            BYTE       *d = gdiBuf;
            for (UINT y = 0; y < h; ++y, s += mapped.RowPitch, d += rowBytes)
                memcpy(d, s, rowBytes);
        }

        ID3D11DeviceContext *ctx2 = nullptr;
        d3dDev->GetImmediateContext(&ctx2);
        ctx2->Unmap(stagingTex, 0);
        ctx2->Release();

        /* GDI blit to HWND */
        HDC hdc = GetDC(hwnd);
        if (!hdc) return false;

        BITMAPINFO bmi = {};
        bmi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth       = (LONG)w;
        bmi.bmiHeader.biHeight      = -(LONG)h;   /* top-down */
        bmi.bmiHeader.biPlanes      = 1;
        bmi.bmiHeader.biBitCount    = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        SetDIBitsToDevice(hdc, 0, 0, w, h,
                          0, 0, 0, h,
                          gdiBuf, &bmi, DIB_RGB_COLORS);
        ReleaseDC(hwnd, hdc);
        return true;
    }

    /* Walk visual tree, present first content found */
    bool commit_visual(FakeVisual *v)
    {
        if (!v) return false;

        if (v->content) {
            IUnknown *c = v->content;

            /* Case 1: IDXGISwapChain1 (FakeCompositionSwapChain from WebView2) */
            {
                IDXGISwapChain1 *sc = nullptr;
                if (SUCCEEDED(c->QueryInterface(MY_IID_IDXGISwapChain1, (void **)&sc))) {
                    ID3D11Texture2D *buf = nullptr;
                    bool ok = false;
                    if (SUCCEEDED(sc->GetBuffer(0, MY_IID_ID3D11Texture2D, (void**)&buf)))
                    { ok = commit_texture(buf); buf->Release(); }
                    sc->Release();
                    if (ok) return true;
                }
            }

            /* Case 2: IDXGISurface → texture */
            {
                IDXGISurface *surf = nullptr;
                if (SUCCEEDED(c->QueryInterface(MY_IID_IDXGISurface, (void **)&surf))) {
                    ID3D11Texture2D *tex = nullptr;
                    bool ok = false;
                    if (SUCCEEDED(surf->QueryInterface(MY_IID_ID3D11Texture2D, (void **)&tex)))
                    { ok = commit_texture(tex); tex->Release(); }
                    surf->Release();
                    if (ok) return true;
                }
            }

            /* Case 3: direct ID3D11Texture2D */
            {
                ID3D11Texture2D *tex = nullptr;
                if (SUCCEEDED(c->QueryInterface(MY_IID_ID3D11Texture2D, (void **)&tex)))
                { bool ok = commit_texture(tex); tex->Release(); if (ok) return true; }
            }
        }

        for (auto *child : v->children)
            if (commit_visual(child)) return true;

        return false;
    }
};

/* FakeSurface : IDCompositionSurface */
struct FakeSurface final : IDCompositionSurface
{
    volatile LONG ref = 1;
    ID3D11Device      *d3dDev = nullptr;
    ID3D11Texture2D   *tex    = nullptr;
    UINT               width, height;
    DXGI_FORMAT        format;

    FakeSurface(ID3D11Device *dev, UINT w, UINT h, DXGI_FORMAT fmt)
        : d3dDev(dev), width(w), height(h), format(fmt)
    { dev->AddRef(); }

    ~FakeSurface()
    {
        if (tex)    tex->Release();
        if (d3dDev) d3dDev->Release();
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override
    {
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, MY_IID_IDCompositionSurface)) {
            *ppv = static_cast<IDCompositionSurface *>(this); AddRef(); return S_OK;
        }
        if (tex) {
            HRESULT hr = tex->QueryInterface(riid, ppv);
            if (SUCCEEDED(hr)) return hr;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override
    { ULONG r = InterlockedDecrement(&ref); if (r == 0) delete this; return r; }

    HRESULT ensure_texture()
    {
        if (tex) return S_OK;
        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = width; desc.Height = height;
        desc.MipLevels = 1; desc.ArraySize = 1;
        desc.Format = format; desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
        return d3dDev->CreateTexture2D(&desc, nullptr, &tex);
    }

    HRESULT STDMETHODCALLTYPE BeginDraw(const RECT *, REFIID iid, void **obj, POINT *off) override
    {
        LOG("Surface::BeginDraw %ux%u", width, height);
        HRESULT hr = ensure_texture();
        if (FAILED(hr)) return hr;
        if (off) { off->x = 0; off->y = 0; }
        return tex->QueryInterface(iid, obj);
    }
    HRESULT STDMETHODCALLTYPE EndDraw()     override { return S_OK; }
    HRESULT STDMETHODCALLTYPE SuspendDraw() override { return S_OK; }
    HRESULT STDMETHODCALLTYPE ResumeDraw()  override { return S_OK; }
    HRESULT STDMETHODCALLTYPE Scroll(const RECT *, const RECT *, int, int) override { return S_OK; }
};

/* FakeDevice : IDCompositionDesktopDevice */
struct FakeDevice final : IDCompositionDesktopDevice
{
    volatile LONG ref = 1;
    IDXGIDevice               *dxgiDev = nullptr;
    ID3D11Device              *d3dDev  = nullptr;
    IDXGIFactory2             *factory = nullptr;
    std::vector<FakeTarget *>  targets;

    ~FakeDevice()
    {
        for (auto *t : targets) t->Release();
        if (factory) factory->Release();
        if (d3dDev)  d3dDev->Release();
        if (dxgiDev) dxgiDev->Release();
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override
    {
        LOG("Device::QI %08lx-%04x-%04x-%02x%02x...",
            riid.Data1, riid.Data2, riid.Data3, riid.Data4[0], riid.Data4[1]);
        if (IsEqualIID(riid, IID_IUnknown)
         || IsEqualIID(riid, MY_IID_IDCompositionDevice2)
         || IsEqualIID(riid, MY_IID_IDCompositionDesktopDevice))
        {
            *ppv = static_cast<IDCompositionDesktopDevice *>(this);
            AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&ref); }
    ULONG STDMETHODCALLTYPE Release() override
    { ULONG r = InterlockedDecrement(&ref); if (r == 0) delete this; return r; }

    /* IDCompositionDevice2 */
    HRESULT STDMETHODCALLTYPE Commit() override
    {
        LOG("Device::Commit (%zu targets)", targets.size());

        static int isPaint = -1;
        if (isPaint < 0) {
            char exe[MAX_PATH] = {};
            GetModuleFileNameA(nullptr, exe, sizeof(exe));
            isPaint = (strstr(exe, "CLIPStudioPaint") != nullptr) ? 1 : 0;
            LOG("process: %s -> isPaint=%d", exe, isPaint);
        }

        /* In Paint: only commit targets in a popup/dialog subtree
           (window or ancestor has WS_EX_NOREDIRECTIONBITMAP).
           Canvas backdrop targets have no such ancestor, so skipping them
           keeps the D3D canvas visible. Popup trees need the overlay so
           wine sets up an OpenGL context that lets Chrome_WidgetWin_1 render on top.
           In Studio: commit all targets. */
        for (auto *t : targets) {
            if (isPaint && !t->inPopupTree) continue;
            t->commit_visual(t->root);
        }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE WaitForCommitCompletion()                         override { return S_OK; }
    HRESULT STDMETHODCALLTYPE GetFrameStatistics(DCOMPOSITION_FRAME_STATISTICS *s) override
    { if (s) ZeroMemory(s, sizeof(*s)); return S_OK; }

    HRESULT STDMETHODCALLTYPE CreateVisual(IDCompositionVisual2 **v) override
    { LOG("CreateVisual"); *v = new FakeVisual(); return S_OK; }

    HRESULT STDMETHODCALLTYPE CreateSurfaceFactory(IUnknown *, IDCompositionSurfaceFactory **sf) override
    { *sf = nullptr; return E_NOTIMPL; }

    HRESULT STDMETHODCALLTYPE CreateSurface(UINT w, UINT h, DXGI_FORMAT fmt,
                                             DXGI_ALPHA_MODE, IDCompositionSurface **s) override
    { LOG("CreateSurface %ux%u", w, h); *s = new FakeSurface(d3dDev, w, h, fmt); return S_OK; }

    HRESULT STDMETHODCALLTYPE CreateVirtualSurface(UINT, UINT, DXGI_FORMAT, DXGI_ALPHA_MODE,
                                                    IDCompositionVirtualSurface **s) override
    { *s = nullptr; return E_NOTIMPL; }

#define STUB_CREATE(T) \
    HRESULT STDMETHODCALLTYPE Create##T(IDComposition##T **p) override { *p = nullptr; return E_NOTIMPL; }
    STUB_CREATE(TranslateTransform)
    STUB_CREATE(ScaleTransform)
    STUB_CREATE(RotateTransform)
    STUB_CREATE(SkewTransform)
    STUB_CREATE(MatrixTransform)
    STUB_CREATE(TranslateTransform3D)
    STUB_CREATE(ScaleTransform3D)
    STUB_CREATE(RotateTransform3D)
    STUB_CREATE(MatrixTransform3D)
    STUB_CREATE(EffectGroup)
    STUB_CREATE(RectangleClip)
    STUB_CREATE(Animation)
#undef STUB_CREATE

    HRESULT STDMETHODCALLTYPE CreateTransformGroup(IDCompositionTransform **, UINT,
                                                    IDCompositionTransform **o) override
    { *o = nullptr; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE CreateTransform3DGroup(IDCompositionTransform3D **, UINT,
                                                      IDCompositionTransform3D **o) override
    { *o = nullptr; return E_NOTIMPL; }

    /* IDCompositionDesktopDevice */
    HRESULT STDMETHODCALLTYPE CreateTargetForHwnd(HWND hwnd, BOOL,
                                                   IDCompositionTarget **target) override
    {
        {
            char cls[128] = {}; GetClassNameA(hwnd, cls, sizeof(cls));
            HWND parent = GetParent(hwnd);
            DWORD style = GetWindowLong(hwnd, GWL_STYLE);
            DWORD exstyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            RECT rc = {}; GetClientRect(hwnd, &rc);
            char parentCls[256] = {};
            DWORD parentStyle = 0, parentEx = 0;
            if (parent) {
                GetClassNameA(parent, parentCls, sizeof(parentCls));
                parentStyle = GetWindowLong(parent, GWL_STYLE);
                parentEx = GetWindowLong(parent, GWL_EXSTYLE);
            }
            LOG("CreateTargetForHwnd hwnd=%p class='%s' parent=%p style=%08lx ex=%08lx %ldx%ld",
                hwnd, cls, parent, style, exstyle,
                rc.right - rc.left, rc.bottom - rc.top);
            LOG("  parent class='%s' style=%08lx ex=%08lx", parentCls, parentStyle, parentEx);
        }

        auto *t = new FakeTarget(hwnd);
        targets.push_back(t);
        t->AddRef(); /* for list */

        *target = static_cast<IDCompositionTarget *>(t);
        t->AddRef(); /* for caller */
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE CreateSurfaceFromHandle(HANDLE, IUnknown **s) override
    { if (s) *s = nullptr; return E_NOTIMPL; }

    HRESULT STDMETHODCALLTYPE CreateSurfaceFromHwnd(HWND, IUnknown **s) override
    { if (s) *s = nullptr; return E_NOTIMPL; }
};

/* Exported entry points */
extern "C" {

HRESULT WINAPI DCompositionCreateDevice2(IUnknown *renderingDevice, REFIID iid, void **ppDevice)
{
    LOG("DCompositionCreateDevice2 iid=%08lx", iid.Data1);

    if (!renderingDevice || !ppDevice) return E_INVALIDARG;

    if (!IsEqualIID(iid, MY_IID_IDCompositionDesktopDevice)
     && !IsEqualIID(iid, MY_IID_IDCompositionDevice2)
     && !IsEqualIID(iid, IID_IUnknown))
    {
        LOG("  unsupported IID"); *ppDevice = nullptr; return E_NOINTERFACE;
    }

    auto *dev = new FakeDevice();

    /* Get ID3D11Device */
    HRESULT hr = renderingDevice->QueryInterface(MY_IID_ID3D11Device, (void **)&dev->d3dDev);
    if (FAILED(hr)) {
        IDXGIDevice *dxgi = nullptr;
        hr = renderingDevice->QueryInterface(MY_IID_IDXGIDevice, (void **)&dxgi);
        if (SUCCEEDED(hr)) {
            hr = dxgi->QueryInterface(MY_IID_ID3D11Device, (void **)&dev->d3dDev);
            dxgi->Release();
        }
    }
    if (FAILED(hr) || !dev->d3dDev) {
        LOG("  no ID3D11Device: %08lx", hr);
        delete dev; return hr;
    }

    /* Get IDXGIDevice and IDXGIFactory2 */
    dev->d3dDev->QueryInterface(MY_IID_IDXGIDevice, (void **)&dev->dxgiDev);
    if (dev->dxgiDev) {
        IDXGIAdapter *adapter = nullptr;
        if (SUCCEEDED(dev->dxgiDev->GetAdapter(&adapter))) {
            adapter->GetParent(MY_IID_IDXGIFactory2, (void **)&dev->factory);
            adapter->Release();
        }
    }
    if (!dev->factory) {
        LOG("  no IDXGIFactory2"); delete dev; return E_FAIL;
    }

    /* Store globals for the hook and lazy swap-chain creation */
    if (!g_d3dDev)  { g_d3dDev  = dev->d3dDev;  g_d3dDev->AddRef(); }
    if (!g_factory) { g_factory = dev->factory; g_factory->AddRef(); }
    install_hook(dev->factory);

    LOG("  OK d3dDev=%p factory=%p", dev->d3dDev, dev->factory);
    *ppDevice = static_cast<IDCompositionDesktopDevice *>(dev);
    return S_OK;
}

HRESULT WINAPI DCompositionCreateDevice(IDXGIDevice *dxgiDevice, REFIID iid, void **ppDevice)
{
    return DCompositionCreateDevice2((IUnknown *)dxgiDevice, iid, ppDevice);
}

HRESULT WINAPI DCompositionCreateDevice3(IUnknown *renderingDevice, REFIID iid, void **ppDevice)
{
    return DCompositionCreateDevice2(renderingDevice, iid, ppDevice);
}

HRESULT WINAPI DCompositionCreateSurfaceHandle(DWORD, SECURITY_ATTRIBUTES *, HANDLE *h)
{
    if (h) *h = nullptr; return E_NOTIMPL;
}

static DWORD WINAPI deferred_hook_thread(LPVOID)
{
    /* Wait for DLLs to finish loading before hooking (avoids loader deadlock from DllMain) */
    Sleep(150);
    IDXGIFactory2 *fac = nullptr;
    HRESULT hr = CreateDXGIFactory(MY_IID_IDXGIFactory2, (void**)&fac);
    LOG("deferred hook: CreateDXGIFactory -> %08lx fac=%p", hr, fac);
    if (SUCCEEDED(hr) && fac) {
        install_hook(fac);
        fac->Release();
    }
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) {
        /* Hook DXGI from a thread to avoid touching the loader lock */
        HANDLE t = CreateThread(nullptr, 0, deferred_hook_thread, nullptr, 0, nullptr);
        if (t) CloseHandle(t);
    }
    return TRUE;
}

} /* extern "C" */
