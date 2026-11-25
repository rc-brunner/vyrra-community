# Distributed binaries must work even when built on a newer CPU than the user's.
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" vyrra_processor)
if(vyrra_processor MATCHES "^(amd64|x86_64|x64)$")
    if(MSVC)
        # cmake-rs can replace Visual Studio's Release flags with CRT flags alone.
        # Restore Release optimization without changing the selected C/C++ runtime.
        foreach(lang C CXX)
            set(release_flags "CMAKE_${lang}_FLAGS_RELEASE")
            if(NOT "${${release_flags}}" MATCHES "(^|[ \t])[-/]O[12dxts]([ \t]|$)")
                set(${release_flags} "${${release_flags}} /O2 /DNDEBUG" CACHE STRING "MSVC Release flags" FORCE)
            endif()
        endforeach()
    endif()
    foreach(feature NATIVE SSE42 AVX AVX2 FMA F16C BMI2 AVX_VNNI AVX512
                    AVX512_VBMI AVX512_VNNI AVX512_BF16 AMX_TILE AMX_INT8 AMX_BF16)
        set(GGML_${feature} OFF CACHE BOOL "Build for the x86-64 baseline" FORCE)
    endforeach()
    set(GGML_LLAMAFILE ON CACHE BOOL "Enable the runtime-selected matrix kernel" FORCE)
    function(vyrra_configure_sgemm)
        get_target_property(cpu_root ggml-cpu SOURCE_DIR)
        set(kernel "${cpu_root}/ggml-cpu/llamafile/sgemm.cpp")
        if(MSVC)
            set(kernel_flags /arch:AVX2)
        else()
            set(kernel_flags -mavx2 -mfma -mf16c)
        endif()
        set_source_files_properties("${kernel}" TARGET_DIRECTORY ggml-cpu PROPERTIES
            COMPILE_OPTIONS "${kernel_flags}"
            COMPILE_DEFINITIONS "llamafile_sgemm=vyrra_avx2_sgemm")
        target_sources(ggml-cpu PRIVATE "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/dispatch-sgemm.cpp")
    endfunction()
    cmake_language(DEFER CALL vyrra_configure_sgemm)
    message(STATUS "Vyrra: portable x86-64 backend with a runtime-selected AVX2 matrix kernel")
endif()
