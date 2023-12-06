-- Copyright (c) 2012 Martin Ridgers
-- Portions Copyright (c) 2020-2023 Christopher Antos
-- License: http://opensource.org/licenses/MIT

local to = ".build/"..(_ACTION or "nullaction")

if _ACTION == "gmake2" then
    error("Use `premake5 gmake` instead; gmake2 neglects to link resources.")
end

--------------------------------------------------------------------------------
local function get_git_info()
    local git_cmd = "git branch --verbose --no-color 2>nul"
    for line in io.popen(git_cmd):lines() do
        local _, _, name, commit = line:find("^%*.+%s+([^ )]+)%)%s+([a-f0-9]+)%s")
        if name and commit then
            return name, commit:sub(1, 6)
        end

        local _, _, name, commit = line:find("^%*%s+([^ ]+)%s+([a-f0-9]+)%s")
        if name and commit then
            return name, commit:sub(1, 6)
        end
    end

    return "NAME?", "COMMIT?"
end

--------------------------------------------------------------------------------
local function postbuild_copy(src, cfg)
    src = path.getabsolute(src)
    src = path.translate(src)

    local dest = to.."/bin/"..cfg
    dest = path.getabsolute(dest)
    dest = path.translate(dest)
    postbuildcommands("copy /y \""..src.."\" \""..dest.."\" 1>nul 2>nul")
end

--------------------------------------------------------------------------------
local function setup_cfg(cfg)
    filter {"configurations:" .. cfg}
        defines("CLINK_"..cfg:upper())
        targetdir(to.."/bin/"..cfg)
        objdir(to.."/obj/")

    filter { "configurations:" .. cfg, "platforms:x32" }
        targetsuffix("_x86")

    filter { "configurations:" .. cfg, "platforms:x64" }
        targetsuffix("_x64")

    filter { "configurations:" .. cfg, "platforms:arm64" }
        targetsuffix("_arm64")
end



--------------------------------------------------------------------------------
local function clink_project(name, input_kind)
    project(name)
    flags("fatalwarnings")
    language("c++")
    kind(input_kind)

    filter { "action:vs*" }
        buildoptions("-FI\""..path.getabsolute("clink/core/warning.h").."\"")

    filter {}
end

--------------------------------------------------------------------------------
local function clink_lib(name)
    clink_project(name, "staticlib")
end

--------------------------------------------------------------------------------
local function clink_dll(name)
    clink_project(name, "sharedlib")
end

--------------------------------------------------------------------------------
local function clink_exe(name)
    clink_project(name, "consoleapp")
end

--------------------------------------------------------------------------------
local function get_clink_version()
    local clink_version_file_name = "clink/app/src/version.h"
    local maj, min, pat
    local x
    for line in io.lines(clink_version_file_name) do
        x = line:match("CLINK_VERSION_MAJOR[ \t]+([0-9]+)")
        if x then maj = x end
        x = line:match("CLINK_VERSION_MINOR[ \t]+([0-9]+)")
        if x then min = x end
        x = line:match("CLINK_VERSION_PATCH[ \t]+([0-9]+)")
        if x then pat = x end
    end
    if not maj or not min or not pat then
        error("Unable to find version number in '"..clink_version_file_name.."'.")
    end
    return maj, min, pat
end

--------------------------------------------------------------------------------
-- MinGW's windres tool can't seem to handle string concatenation like rc does,
-- so I gave up and generate it here.
local function get_version_str_defs(commit)
    local maj, min, pat = get_clink_version()
    local str = '#define CLINK_VERSION_STR "'..maj..'.'..min..'.'..pat..'.'..commit..'"\n'
    local lstr = '#define CLINK_VERSION_LSTR L"'..maj..'.'..min..'.'..pat..'.'..commit..'"\n'
    return str..lstr
end

--------------------------------------------------------------------------------
local function write_clink_commit_file(commit)
    local clink_commit_file
    local clink_commit_file_name = ".build/clink_commit.h"
    local clink_commit_string = "#pragma once\n#define CLINK_COMMIT "..commit.."\n"..get_version_str_defs(commit)
    local old_commit_string = ""

    clink_commit_file = io.open(path.getabsolute(clink_commit_file_name), "r")
    if clink_commit_file then
        old_commit_string = clink_commit_file:read("*all")
        clink_commit_file:close()
    end

    if old_commit_string ~= clink_commit_string then
        clink_commit_file = io.open(path.getabsolute(clink_commit_file_name), "w")
        if not clink_commit_file then
            error("Unable to write '"..clink_commit_file_name.."'.")
        end
        clink_commit_file:write(clink_commit_string)
        clink_commit_file:close()
        print("Generated "..clink_commit_file_name.."...")
    end
end

--------------------------------------------------------------------------------
local function write_clink_manifest_file()
    local manifest_file = ".build/clink_manifest.xml"
    local manifest_file_name = ".build/clink_manifest.xml"
    local maj, min, pat = get_clink_version()

    local manifest_string =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'..
        '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" xmlns:asmv3="urn:schemas-microsoft-com:asm.v3" manifestVersion="1.0">'..
        '<assemblyIdentity version="'..maj..'.'..min..'.'..pat..'.0" processorArchitecture="*" name="Microsoft.Source Depot.SDVDiff" type="win32"/>'..
        '<description>Clink</description>'..
        '<asmv3:application><asmv3:windowsSettings>'..
            --'<dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">True</dpiAware>'..
            --'<dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2, PerMonitor</dpiAwareness>'..
            '<heapType xmlns="http://schemas.microsoft.com/SMI/2020/WindowsSettings">SegmentHeap</heapType>'..
        '</asmv3:windowsSettings></asmv3:application>'..
        '<dependency><dependentAssembly>'..
            '<assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>'..
        '</dependentAssembly></dependency>'..
        '<compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application>'..
            '<supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>'.. -- Windows 10
            '<supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>'.. -- Windows 8.1
            '<supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}"/>'.. -- Windows 8
            '<supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"/>'.. -- Windows 7
            '<supportedOS Id="{e2011457-1546-43c5-a5fe-008deee3d3f0}"/>'.. -- Windows Vista
        '</application></compatibility></assembly>'

    local old_manifest_string = ""
    manifest_file = io.open(path.getabsolute(manifest_file_name), "r")
    if manifest_file then
        old_manifest_string = manifest_file:read("*all")
        manifest_file:close()
    end

    if old_manifest_string ~= manifest_string then
        manifest_file = io.open(path.getabsolute(manifest_file_name), "w")
        if not manifest_file then
            error("Unable to write '"..manifest_file_name.."'.")
        end
        manifest_file:write(manifest_string);
        manifest_file:close()
        print("Generated "..manifest_file_name.."...")
    end
end

--------------------------------------------------------------------------------
if _ACTION then
    local workspace = (_ACTION:find("^vs") or _ACTION:find("^gmake"))
    local docs = (_ACTION == "docs")
    if workspace or docs then
        clink_git_name, clink_git_commit = get_git_info()
        write_clink_commit_file(clink_git_commit)
    end
    if workspace then
        write_clink_manifest_file()
    end
end



--------------------------------------------------------------------------------
workspace("clink")
    configurations {"debug", "release", "final"}
    platforms {"x32", "x64", "arm64"}
    location(to)

    characterset("MBCS")
    flags("NoManifest")
    staticruntime("on")
    symbols("on")
    exceptionhandling("off")
    defines("HAVE_CONFIG_H")
    defines("HANDLE_MULTIBYTE")

    setup_cfg("final")
    setup_cfg("release")
    setup_cfg("debug")

    filter { "configurations:debug" }
        defines("CLINK_BUILD_ROOT=\""..path.getabsolute(to).."\"")
        rtti("on")
        optimize("off")
        defines("DEBUG")
        defines("_DEBUG")

    filter { "configurations:release" }
        defines("CLINK_BUILD_ROOT=\""..path.getabsolute(to).."\"")
        --rtti("off")
        rtti("on")
        optimize("full")
        defines("NDEBUG")

    filter { "configurations:final" }
        --rtti("off")
        rtti("on")
        optimize("full")
        omitframepointer("on")
        flags("NoBufferSecurityCheck")
        defines("NDEBUG")

    filter { "configurations:final", "action:vs*" }
        flags("LinkTimeOptimization")

    filter { "action:vs*" }
        defines("_HAS_EXCEPTIONS=0")
        defines("_CRT_SECURE_NO_WARNINGS")
        defines("_CRT_NONSTDC_NO_WARNINGS")

    filter { "action:gmake" }
        defines("__MSVCRT_VERSION__=0x0601")
        defines("_WIN32_WINNT=0x0601")
        defines("WINVER=0x0601")
        defines("_POSIX=1")             -- so vsnprintf returns needed size
        buildoptions("-Wno-error=missing-field-initializers")
        buildoptions("-ffunction-sections")
        buildoptions("-fdata-sections")
        makesettings { "CC=gcc" }

    filter { "*" }
        includedirs(".build")           -- for clink_commit.h

--------------------------------------------------------------------------------
project("readline")
    language("c")
    kind("staticlib")
    defines("BUILD_READLINE")
    includedirs("readline")
    includedirs("readline/compat")
    includedirs("wildmatch/wildmatch")
    files("readline/readline/*.c")
    files("readline/readline/*.h")
    files("readline/compat/*.c")
    files("readline/compat/*.h")

    excludes("readline/readline/emacs_keymap.c")    -- #included by readline/keymaps.c
    excludes("readline/readline/vi_keymap.c")       -- #included by readline/keymaps.c
    excludes("readline/readline/support/wcwidth.c") -- superseded by clink/terminal/src/wcwidth.cpp

--------------------------------------------------------------------------------
project("getopt")
    language("c")
    kind("staticlib")
    files("getopt/*")

--------------------------------------------------------------------------------
project("wildmatch")
    language("c")
    kind("staticlib")
    files("wildmatch/wildmatch/*.c")
    files("wildmatch/wildmatch/*.h")

--------------------------------------------------------------------------------
project("lua")
    language("c")
    kind("staticlib")
    defines("BUILD_LUA")
    files("lua/src/*.c")
    files("lua/src/*.h")
    excludes("lua/src/lua.c")
    excludes("lua/src/luac.c")

--------------------------------------------------------------------------------
project("luac")
    language("c")
    kind("consoleapp")
    links("lua")
    files("lua/src/luac.c")

--------------------------------------------------------------------------------
project("lua52")
    language("c")
    kind("consoleapp")
    defines("BUILD_LUA")
    links("clink_lib")
    links("clink_core") -- Link after clink_lib to solve order issue with linear_allocator.*.
    links("lua")
    files("lua/src/lua.c")

--------------------------------------------------------------------------------
project("detours")
    kind("staticlib")
    files("detours/*.cpp")
    removefiles("detours/disolarm.cpp")
    removefiles("detours/disolarm64.cpp")
    removefiles("detours/disolia64.cpp")
    removefiles("detours/uimports.cpp")     -- is included by creatwth.cpp

    filter { "configurations:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")
        buildoptions("-Wno-multichar")
        buildoptions("-Wno-pointer-arith")

--------------------------------------------------------------------------------
clink_lib("clink_lib")
    includedirs("clink/lib/include/lib")
    includedirs("clink/core/include")
    includedirs("clink/terminal/include")
    includedirs("readline")
    includedirs("readline/compat")
    includedirs("wildmatch")
    files("clink/lib/src/**")
    files("clink/lib/include/**")

    includedirs("clink/lib/src")
    filter { "action:vs*" }
        pchheader("pch.h")
        pchsource("clink/lib/src/pch.cpp")

    filter { "action:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_lib("clink_lua")
    includedirs("clink/lua/include/lua")
    includedirs("clink/core/include")
    includedirs("clink/lib/include")
    includedirs("clink/process/include")
    includedirs("clink/terminal/include")
    includedirs("lua/src")
    includedirs("readline")
    includedirs("readline/compat")
    includedirs("wildmatch")
    files("clink/lua/src/**")
    files("clink/lua/include/**")
    files("clink/lua/scripts/**")
    excludes("clink/lua/src/lua_editor_tester.cpp")

    includedirs("clink/lua/src")
    filter { "action:vs*" }
        pchheader("pch.h")
        pchsource("clink/lua/src/pch.cpp")

    filter { "action:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_lib("clink_core")
    includedirs("clink/core/include/core")
    files("clink/core/src/**")
    files("clink/core/include/**")

    includedirs("clink/core/src")
    filter { "action:vs*" }
        pchheader("pch.h")
        pchsource("clink/core/src/pch.cpp")

    filter { "action:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_lib("clink_terminal")
    includedirs("clink/terminal/include/terminal")
    includedirs("clink/core/include")
    includedirs("clink/process/include")
    files("clink/terminal/src/**")
    files("clink/terminal/include/**")

    includedirs("clink/terminal/src")
    filter { "action:vs*" }
        exceptionhandling("on")         -- for std::wregex
        pchheader("pch.h")
        pchsource("clink/terminal/src/pch.cpp")

    filter { "action:gmake" }
        buildoptions("-fexceptions")    -- for std::wregex
        buildoptions("-fpermissive")
        buildoptions("-Wno-multichar")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_lib("clink_process")
    includedirs("clink/core/include")
    includedirs("clink/process/include/process")
    files("clink/process/src/**")
    files("clink/process/include/**")

    includedirs("clink/process/src")
    filter { "action:vs*" }
        flags { "NoRuntimeChecks" } -- required for 32 bit by the inject lambda in process::remote_call
        pchheader("pch.h")
        pchsource("clink/process/src/pch.cpp")
        inlining("auto") -- required by the inject lambda in process::remote_call
        editAndContinue("off") -- required by the inject lambda in process::remote_call
        omitframepointer("off") -- required by the inject lambda in process::remote_call
        exceptionhandling("off") -- required by the inject lambda in process::remote_call
        -- <SupportJustMyCode>false</SupportJustMyCode> -- required by the inject lambda in process::remote_call

    filter { "configurations:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_lib("clink_app_common")
    includedirs("clink/app/src")
    includedirs("clink/core/include")
    includedirs("clink/lib/include")
    includedirs("clink/lua/include")
    includedirs("clink/process/include")
    includedirs("clink/terminal/include")
    includedirs("detours")
    includedirs("getopt")
    includedirs("lua/src")
    includedirs("readline")
    includedirs("readline/compat")
    files("clink/app/src/**")
    files("clink/app/scripts/**")
    excludes("clink/app/src/dll/main.cpp")
    excludes("clink/app/src/loader/main.cpp")

    filter { "action:vs*" }
        pchheader("pch.h")
        pchsource("clink/app/src/pch.cpp")

    filter { "action:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_dll("clink_app_dll")
    targetname("clink_dll")
    links("clink_app_common")
    links("clink_lib")
    links("clink_core") -- Link after clink_lib to solve order issue with linear_allocator.*.
    links("clink_lua")
    links("clink_process")
    links("clink_terminal")
    links("detours")
    links("getopt")
    links("wildmatch")
    links("lua")
    links("readline")
    links("version")
    links("shlwapi")
    links("rpcrt4")
    files("clink/app/src/dll/main.cpp")
    files("clink/app/src/version.rc")
    files("clink/app/src/manifest.rc")

    filter { "action:vs*" }
        links("dbghelp")

    filter { "action:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")
        links("gdi32")
        links("ole32")

--------------------------------------------------------------------------------
clink_exe("clink_app_exe")
    targetname("clink")
    flags("OmitDefaultLibrary")
    links("clink_app_dll")
    files("clink/app/src/loader/main.cpp")
    files("clink/app/src/version.rc")
    files("clink/app/src/manifest.rc")

    filter { "configurations:final" }
        postbuild_copy("CHANGES", "final")
        postbuild_copy("LICENSE", "final")
        postbuild_copy("clink/app/src/loader/clink.bat", "final")
        postbuild_copy("clink/app/src/loader/clink.lua", "final")

    filter { "configurations:release" }
        postbuild_copy("clink/app/src/loader/clink.bat", "release")
        postbuild_copy("clink/app/src/loader/clink.lua", "release")

    filter { "configurations:debug" }
        postbuild_copy("clink/app/src/loader/clink.bat", "debug")
        postbuild_copy("clink/app/src/loader/clink.lua", "debug")

    filter { "configurations:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")

--------------------------------------------------------------------------------
clink_exe("clink_test")
    links("clink_app_common")
    links("clink_core")
    links("clink_lib")
    links("clink_lua")
    links("clink_process")
    links("clink_terminal")
    links("detours")
    links("wildmatch")
    links("lua")
    links("readline")
    links("shlwapi")
    links("rpcrt4")
    includedirs("clink/test/src")
    includedirs("clink/app/src")
    includedirs("clink/core/include")
    includedirs("clink/lib/include")
    includedirs("clink/lib/include/lib")
    includedirs("clink/lib/src")
    includedirs("clink/lua/include")
    includedirs("clink/process/include")
    includedirs("clink/terminal/include")
    includedirs("wildmatch/wildmatch")
    includedirs("lua/src")
    includedirs("readline")
    includedirs("readline/compat")
    files("clink/app/test/*.cpp")
    files("clink/core/test/*.cpp")
    files("clink/lua/test/*.cpp")
    files("clink/lib/test/*.cpp")
    files("clink/process/test/*.cpp")
    files("clink/terminal/test/*.cpp")
    files("clink/test/**")
    files("wildmatch/tests/*.cpp")

    exceptionhandling("on")

    filter { "action:vs*" }
        pchheader("pch.h")
        pchsource("clink/test/src/pch.cpp")

    filter { "action:gmake" }
        buildoptions("-fpermissive")
        buildoptions("-std=c++17")
        links("gdi32")
        links("ole32")
        linkgroups("on")

--------------------------------------------------------------------------------
require "vstudio"
local function add_tag(tag, value, project_name)
    premake.override(premake.vstudio.vc2010.elements, "clCompile",
    function(oldfn, cfg)
        local calls = oldfn(cfg)
        if project_name == nil or cfg.project.name == project_name then
            table.insert(calls, function(cfg)
                premake.vstudio.vc2010.element(tag, nil, value)
            end)
        end
        return calls
    end)
end

add_tag("SupportJustMyCode", "false", "clink_process")

--------------------------------------------------------------------------------
dofile("docs/premake5.lua")
dofile("installer/premake5.lua")
dofile("embed.lua")
