#include "napi/native_api.h"
#include "flclash_core.h"
#include <hilog/log.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sstream>
#include <unistd.h>
#include <vector>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xF1C1
#define LOG_TAG "LexiClashNAPI"

static std::string g_homeDir = "";
static int g_coreVersion = 1;

static std::string ReadStdString(napi_env env, napi_value input) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, input, nullptr, 0, &length) != napi_ok) {
        return "";
    }
    std::vector<char> buffer(length + 1);
    if (napi_get_value_string_utf8(env, input, buffer.data(), buffer.size(), &length) != napi_ok) {
        return "";
    }
    return std::string(buffer.data(), length);
}

static char* ReadCString(napi_env env, napi_value value) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a string");
        return nullptr;
    }
    char* result = static_cast<char*>(std::malloc(size + 1));
    if (result == nullptr) {
        napi_throw_error(env, nullptr, "Out of memory");
        return nullptr;
    }
    if (napi_get_value_string_utf8(env, value, result, size + 1, &size) != napi_ok) {
        std::free(result);
        napi_throw_type_error(env, nullptr, "Invalid string");
        return nullptr;
    }
    return result;
}

static napi_value ReturnCoreString(napi_env env, char* value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value ? value : "", NAPI_AUTO_LENGTH, &result);
    if (value != nullptr) {
        FlClashFree(value);
    }
    return result;
}

static std::string ExtractJsonField(const std::string& json, const std::string& key) {
    const std::string quoted = "\"" + key + "\":";
    const size_t pos = json.find(quoted);
    if (pos == std::string::npos) {
        return "";
    }
    size_t idx = pos + quoted.size();
    while (idx < json.size() && (json[idx] == ' ' || json[idx] == '\t')) {
        ++idx;
    }
    if (idx >= json.size()) {
        return "";
    }
    if (json[idx] == '"') {
        const size_t start = idx + 1;
        size_t end = start;
        while (end < json.size() && json[end] != '"') {
            if (json[end] == '\\' && end + 1 < json.size()) {
                end += 2;
            } else {
                ++end;
            }
        }
        return json.substr(start, end - start);
    }
    const size_t start = idx;
    while (idx < json.size() && json[idx] != ',' && json[idx] != '}' && json[idx] != ' ') {
        ++idx;
    }
    return json.substr(start, idx - start);
}

static std::string MapCoreMethodName(const std::string& method) {
    if (method == "core.init") return "initClash";
    if (method == "core.initialized") return "getIsInit";
    if (method == "core.gc") return "forceGc";
    if (method == "core.memory") return "getMemory";
    if (method == "config.setup") return "setupConfig";
    if (method == "config.update") return "updateConfig";
    if (method == "config.validate") return "validateConfig";
    if (method == "config.read") return "getConfig";
    if (method == "proxy.list") return "getProxies";
    if (method == "proxy.select") return "changeProxy";
    if (method == "proxy.testDelay") return "asyncTestDelay";
    if (method == "provider.list") return "getExternalProviders";
    if (method == "provider.update") return "updateExternalProvider";
    if (method == "geo.update") return "updateGeoData";
    if (method == "traffic.current") return "getTraffic";
    if (method == "traffic.total") return "getTotalTraffic";
    if (method == "traffic.reset") return "resetTraffic";
    if (method == "connection.list") return "getConnections";
    if (method == "connection.close") return "closeConnection";
    if (method == "connection.closeAll") return "closeConnections";
    if (method == "connection.reset") return "resetConnections";
    if (method == "listener.start") return "startListener";
    if (method == "listener.stop") return "stopListener";
    if (method == "log.start") return "startLog";
    if (method == "log.stop") return "stopLog";
    return method;
}

static napi_value ErrorResponse(napi_env env, const std::string& id, const char* message) {
    const std::string response = "{\"id\":\"" + id + "\",\"result\":null,\"error\":\"" + message + "\"}";
    napi_value result = nullptr;
    napi_create_string_utf8(env, response.c_str(), response.size(), &result);
    return result;
}

// Legacy compatibility exports backed by linked libflclash_core.so
static napi_value NativeInitCore(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t version = 26;
    if (argc >= 2) {
        napi_get_value_int32(env, args[1], &version);
    }

    g_homeDir = argc >= 1 ? ReadStdString(env, args[0]) : "";
    g_coreVersion = version;

    std::ostringstream oss;
    oss << "{\"id\":0,\"result\":{\"initialized\":true,\"engine\":\"mihomo-openharmony\",\"version\":"
        << g_coreVersion << "},\"error\":null}";
    napi_value result = nullptr;
    const std::string out = oss.str();
    napi_create_string_utf8(env, out.c_str(), out.size(), &result);
    return result;
}

static napi_value NativeInvokeMethod(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const std::string payload = argc >= 1 ? ReadStdString(env, args[0]) : "";
    std::string id = ExtractJsonField(payload, "id");
    if (id.empty()) {
        id = "0";
    }
    const std::string method = ExtractJsonField(payload, "method");
    if (method.empty()) {
        return ErrorResponse(env, id, "INVALID_METHOD_CALL");
    }

    const std::string mappedMethod = MapCoreMethodName(method);
    std::string forwarded = payload;
    if (mappedMethod != method) {
        const std::string needle = "\"method\":\"" + method + "\"";
        const size_t pos = forwarded.find(needle);
        if (pos != std::string::npos) {
            forwarded.replace(pos, needle.size(), "\"method\":\"" + mappedMethod + "\"");
        }
    }

    std::vector<char> mutableInput(forwarded.begin(), forwarded.end());
    mutableInput.push_back('\0');
    char* rawResp = FlClashInvoke(mutableInput.data());
    if (rawResp == nullptr) {
        return ErrorResponse(env, id, "CORE_EMPTY_RESPONSE");
    }

    std::string respStr(rawResp);
    FlClashFree(rawResp);

    // Preserve caller request id if Go generated an internal ohos-* id.
    const std::string goId = ExtractJsonField(respStr, "id");
    if (!goId.empty() && goId != id) {
        const std::string goIdPair = "\"id\":\"" + goId + "\"";
        const size_t idPos = respStr.find(goIdPair);
        if (idPos != std::string::npos) {
            respStr.replace(idPos, goIdPair.size(), "\"id\":\"" + id + "\"");
        }
    }

    napi_value result = nullptr;
    napi_create_string_utf8(env, respStr.c_str(), respStr.size(), &result);
    return result;
}

static napi_value NativeIsGoCoreLoaded(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value NativeGetCoreVersion(napi_env env, napi_callback_info info) {
    const std::string ver = "mihomo / Clash.Meta (OpenHarmony arm64)";
    napi_value result = nullptr;
    napi_create_string_utf8(env, ver.c_str(), ver.size(), &result);
    return result;
}

// OHClash C N-API exports directly bound to libflclash_core.so
static napi_value Launch(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "launch(homeDir, secret) requires two arguments");
        return nullptr;
    }
    char* home = ReadCString(env, args[0]);
    if (home == nullptr) {
        return nullptr;
    }
    char* secret = ReadCString(env, args[1]);
    if (secret == nullptr) {
        std::free(home);
        return nullptr;
    }
    char* error = FlClashLaunch(home, secret);
    std::free(home);
    std::free(secret);
    return ReturnCoreString(env, error);
}

static napi_value StartTun(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    int32_t fd = -1;
    if (argc != 1 || napi_get_value_int32(env, arg, &fd) != napi_ok || fd < 0) {
        napi_throw_type_error(env, nullptr, "startTun requires a valid file descriptor");
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_boolean(env, FlClashStartTun(fd) == 1, &result);
    return result;
}

static napi_value GetTunError(napi_env env, napi_callback_info info) {
    return ReturnCoreString(env, FlClashGetTunError());
}

enum CoreWorkKind {
    WORK_TUN = 0,
    WORK_LAUNCH = 1,
    WORK_INSPECT = 2,
    WORK_DELAY = 3,
    WORK_STOP = 4,
    WORK_PROXY_LAUNCH = 5
};

struct CoreWork {
    napi_async_work work;
    napi_deferred deferred;
    char* home;
    char* secret;
    char* error;
    int32_t fd;
    int started;
    int kind;
    unsigned long long epoch;
};

static void ExecuteCoreWork(napi_env env, void* data) {
    CoreWork* request = static_cast<CoreWork*>(data);
    if (request->kind == WORK_STOP) {
        FlClashStopAtEpoch(request->epoch);
    } else if (request->kind == WORK_DELAY) {
        request->error = FlClashTestProfileDelay(request->home, request->secret);
    } else if (request->kind == WORK_INSPECT) {
        request->error = FlClashInspectProfile(request->home);
    } else if (request->kind == WORK_LAUNCH) {
        request->error = FlClashLaunchAtEpoch(request->home, request->secret, request->epoch);
    } else if (request->kind == WORK_PROXY_LAUNCH) {
        request->error = FlClashLaunchProxyAtEpoch(request->home, request->secret, request->epoch);
    } else {
        request->started = FlClashStartTunAtEpoch(request->fd, request->epoch);
        request->fd = -1;
    }
}

static void CompleteCoreWork(napi_env env, napi_status status, void* data) {
    CoreWork* request = static_cast<CoreWork*>(data);
    napi_value result = nullptr;
    if (request->kind == WORK_STOP) {
        napi_get_undefined(env, &result);
    } else if (request->kind != WORK_TUN) {
        napi_create_string_utf8(env, request->error ? request->error : "", NAPI_AUTO_LENGTH, &result);
    } else {
        napi_get_boolean(env, request->started == 1, &result);
    }
    if (status == napi_ok) {
        napi_resolve_deferred(env, request->deferred, result);
    } else {
        napi_value reason = nullptr;
        napi_create_string_utf8(env, "Native core worker failed", NAPI_AUTO_LENGTH, &reason);
        napi_reject_deferred(env, request->deferred, reason);
    }
    if (request->error != nullptr) {
        FlClashFree(request->error);
    }
    std::free(request->home);
    std::free(request->secret);
    if (request->kind == WORK_TUN && request->fd >= 0) {
        close(request->fd);
    }
    napi_delete_async_work(env, request->work);
    std::free(request);
}

static napi_value QueueCoreWork(napi_env env, CoreWork* request) {
    napi_value promise = nullptr;
    napi_value resource = nullptr;
    if (request->kind != WORK_STOP) {
        request->epoch = FlClashLifecycleEpoch();
    }
    napi_create_promise(env, &request->deferred, &promise);
    napi_create_string_utf8(env, "LexiClash core", NAPI_AUTO_LENGTH, &resource);
    if (napi_create_async_work(env, nullptr, resource, ExecuteCoreWork, CompleteCoreWork,
            request, &request->work) != napi_ok ||
        napi_queue_async_work(env, request->work) != napi_ok) {
        if (request->work != nullptr) {
            napi_delete_async_work(env, request->work);
        }
        std::free(request->home);
        std::free(request->secret);
        if (request->kind == WORK_TUN && request->fd >= 0) {
            close(request->fd);
        }
        std::free(request);
        napi_throw_error(env, nullptr, "Could not queue native core work");
        return nullptr;
    }
    return promise;
}

static napi_value QueueLaunch(napi_env env, napi_callback_info info, int kind) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "launchAsync(homeDir, secret) requires two arguments");
        return nullptr;
    }
    CoreWork* request = static_cast<CoreWork*>(std::calloc(1, sizeof(CoreWork)));
    if (request == nullptr) {
        napi_throw_error(env, nullptr, "Out of memory");
        return nullptr;
    }
    request->fd = -1;
    request->home = ReadCString(env, args[0]);
    if (request->home == nullptr) {
        std::free(request);
        return nullptr;
    }
    request->secret = ReadCString(env, args[1]);
    if (request->secret == nullptr) {
        std::free(request->home);
        std::free(request);
        return nullptr;
    }
    request->kind = kind;
    return QueueCoreWork(env, request);
}

static napi_value LaunchAsync(napi_env env, napi_callback_info info) {
    return QueueLaunch(env, info, WORK_LAUNCH);
}

static napi_value LaunchProxyAsync(napi_env env, napi_callback_info info) {
    return QueueLaunch(env, info, WORK_PROXY_LAUNCH);
}

static napi_value TestProfileDelay(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "testProfileDelay(content, name) requires two arguments");
        return nullptr;
    }
    CoreWork* request = static_cast<CoreWork*>(std::calloc(1, sizeof(CoreWork)));
    if (request == nullptr) {
        napi_throw_error(env, nullptr, "Out of memory");
        return nullptr;
    }
    request->fd = -1;
    request->home = ReadCString(env, args[0]);
    if (request->home == nullptr) {
        std::free(request);
        return nullptr;
    }
    request->secret = ReadCString(env, args[1]);
    if (request->secret == nullptr) {
        std::free(request->home);
        std::free(request);
        return nullptr;
    }
    request->kind = WORK_DELAY;
    return QueueCoreWork(env, request);
}

static napi_value StartTunAsync(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    int32_t fd = -1;
    if (argc != 1 || napi_get_value_int32(env, arg, &fd) != napi_ok || fd < 0) {
        napi_throw_type_error(env, nullptr, "startTunAsync requires a valid file descriptor");
        return nullptr;
    }
    CoreWork* request = static_cast<CoreWork*>(std::calloc(1, sizeof(CoreWork)));
    if (request == nullptr) {
        napi_throw_error(env, nullptr, "Out of memory");
        return nullptr;
    }
    request->fd = fd;
    request->kind = WORK_TUN;
    return QueueCoreWork(env, request);
}

static napi_value Stop(napi_env env, napi_callback_info info) {
    FlClashStop();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value StopAsync(napi_env env, napi_callback_info info) {
    CoreWork* request = static_cast<CoreWork*>(std::calloc(1, sizeof(CoreWork)));
    if (request == nullptr) {
        napi_throw_error(env, nullptr, "Out of memory");
        return nullptr;
    }
    request->fd = -1;
    request->kind = WORK_STOP;
    request->epoch = FlClashCancelLifecycle();
    return QueueCoreWork(env, request);
}

static napi_value Invoke(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1) {
        napi_throw_type_error(env, nullptr, "invoke requires one string");
        return nullptr;
    }
    char* input = ReadCString(env, arg);
    if (input == nullptr) {
        return nullptr;
    }
    char* output = FlClashInvoke(input);
    std::free(input);
    return ReturnCoreString(env, output);
}

static napi_value InspectProfile(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1) {
        napi_throw_type_error(env, nullptr, "inspectProfile requires content");
        return nullptr;
    }
    CoreWork* request = static_cast<CoreWork*>(std::calloc(1, sizeof(CoreWork)));
    if (request == nullptr) {
        napi_throw_error(env, nullptr, "Out of memory");
        return nullptr;
    }
    request->fd = -1;
    request->home = ReadCString(env, arg);
    if (request->home == nullptr) {
        std::free(request);
        return nullptr;
    }
    request->kind = WORK_INSPECT;
    return QueueCoreWork(env, request);
}

static napi_value BeginDelayJob(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "beginDelayJob requires content and names");
        return nullptr;
    }
    char* content = ReadCString(env, args[0]);
    if (content == nullptr) {
        return nullptr;
    }
    char* names = ReadCString(env, args[1]);
    if (names == nullptr) {
        std::free(content);
        return nullptr;
    }
    char* output = FlClashBeginDelayJob(content, names);
    std::free(content);
    std::free(names);
    return ReturnCoreString(env, output);
}

static napi_value PollDelayJob(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1) {
        napi_throw_type_error(env, nullptr, "pollDelayJob requires id");
        return nullptr;
    }
    char* id = ReadCString(env, arg);
    if (id == nullptr) {
        return nullptr;
    }
    char* output = FlClashPollDelayJob(id);
    std::free(id);
    return ReturnCoreString(env, output);
}

static napi_value CancelDelayJob(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc != 1) {
        napi_throw_type_error(env, nullptr, "cancelDelayJob requires id");
        return nullptr;
    }
    char* id = ReadCString(env, arg);
    if (id == nullptr) {
        return nullptr;
    }
    FlClashCancelDelayJob(id);
    std::free(id);
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"nativeInitCore", nullptr, NativeInitCore, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeInvokeMethod", nullptr, NativeInvokeMethod, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeIsGoCoreLoaded", nullptr, NativeIsGoCoreLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeGetCoreVersion", nullptr, NativeGetCoreVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"beginDelayJob", nullptr, BeginDelayJob, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pollDelayJob", nullptr, PollDelayJob, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelDelayJob", nullptr, CancelDelayJob, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"testProfileDelay", nullptr, TestProfileDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"inspectProfile", nullptr, InspectProfile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"launch", nullptr, Launch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTun", nullptr, StartTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getTunError", nullptr, GetTunError, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"launchAsync", nullptr, LaunchAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"launchProxyAsync", nullptr, LaunchProxyAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTunAsync", nullptr, StartTunAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopAsync", nullptr, StopAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"invoke", nullptr, Invoke, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "clash_bridge",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
