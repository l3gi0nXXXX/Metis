#ifndef DLL_EXPORT_H
#define DLL_EXPORT_H

#if defined(_WIN32) || defined(__CYGWIN__)
  #if defined(BUILDING_DLL)
    #define DLL_EXPORT __declspec(dllexport)
  #elif defined(BUILDING_STATIC)
    #define DLL_EXPORT
  #else
    #define DLL_EXPORT __declspec(dllimport)
  #endif
#else
  #define DLL_EXPORT
#endif

#endif // DLL_EXPORT_H