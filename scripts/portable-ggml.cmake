# A distributed x64 binary must run on CPUs other than the build host.
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" vyrra_processor)
if(vyrra_processor MATCHES "^(amd64|x86_64|x64)$")
    foreach(feature NATIVE SSE42 AVX AVX2 FMA F16C BMI2 AVX_VNNI AVX512
                    AVX512_VBMI AVX512_VNNI AVX512_BF16 AMX_TILE AMX_INT8 AMX_BF16)
        set(GGML_${feature} OFF CACHE BOOL "Build for the x86-64 baseline" FORCE)
    endforeach()
    message(STATUS "Vyrra: building ggml for the portable x86-64 baseline")
endif()
