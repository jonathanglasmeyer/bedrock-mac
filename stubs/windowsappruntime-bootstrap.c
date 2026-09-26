/* Stub for Microsoft.WindowsAppRuntime.Bootstrap.dll: Wine has no MSIX package
 * graph, so the real bootstrapper fails with E_NOTIMPL and the game exits.
 * The Windows App SDK DLLs ship next to the game, so pretending success works
 * (see WineGDK issue #39).
 *
 * Built with:
 *   clang --target=x86_64-pc-windows-msvc -O2 -c windowsappruntime-bootstrap.c -o stub.obj
 *   lld -flavor link /dll /nodefaultlib /entry:_DllMainCRTStartup \
 *       /out:Microsoft.WindowsAppRuntime.Bootstrap.dll stub.obj
 */
typedef long HRESULT;
typedef unsigned int UINT32;
typedef struct { unsigned long long Version; } PACKAGE_VERSION;
__declspec(dllexport) HRESULT MddBootstrapInitialize(UINT32 v, const void *tag, PACKAGE_VERSION min) { return 0; }
__declspec(dllexport) HRESULT MddBootstrapInitialize2(UINT32 v, const void *tag, PACKAGE_VERSION min, int opts) { return 0; }
__declspec(dllexport) void MddBootstrapShutdown(void) {}
__declspec(dllexport) HRESULT MddBootstrapTestInitialize(const void *a, const void *b, const void *c, const void *d) { return 0; }
int __stdcall _DllMainCRTStartup(void *h, unsigned long r, void *p) { return 1; }
