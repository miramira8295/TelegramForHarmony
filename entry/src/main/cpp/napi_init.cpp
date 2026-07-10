#include "napi/native_api.h"
#include <hilog/log.h>
#include <atomic>
#include <string>
#include <thread>

extern "C" {
int td_create_client_id();
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
void td_set_log_message_callback(int max_verbosity_level,
                                 void (*callback)(int verbosity_level, const char *message));
}

namespace {
// TDLib's own internal log, surfaced to hilog with a [TDLib] prefix so its
// diagnostics (flood waits, delivery decisions, network state) are visible.
void TdLogCallback(int verbosity_level, const char *message) {
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "TDLib", "[TDLib][v%{public}d] %{public}s",
                 verbosity_level, message == nullptr ? "" : message);
}

int g_clientId = 0;
bool g_created = false;
std::thread g_receiveThread;
std::atomic<bool> g_running{false};
napi_threadsafe_function g_onReceive = nullptr;

void CallJsOnReceive(napi_env env, napi_value jsCallback, void * /*context*/, void *data) {
    auto *json = static_cast<std::string *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value arg;
        napi_create_string_utf8(env, json->c_str(), json->size(), &arg);
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        napi_call_function(env, undefined, jsCallback, 1, &arg, nullptr);
    }
    delete json;
}

// td_receive is global across all client ids; a single receive loop serves the process.
void ReceiveLoop() {
    while (g_running.load()) {
        const char *result = td_receive(0.5);
        if (result != nullptr && g_onReceive != nullptr) {
            auto *copy = new std::string(result);
            napi_status status = napi_call_threadsafe_function(g_onReceive, copy, napi_tsfn_blocking);
            if (status != napi_ok) {
                delete copy;
            }
        }
    }
}

napi_value TdInit(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_created) {
        napi_throw_error(env, nullptr, "tdInit called twice");
        return nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "tdReceive", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr,
                                    nullptr, CallJsOnReceive, &g_onReceive);
    // Route TDLib's internal log (verbosity <= 2: fatal/error/warning) to hilog.
    td_set_log_message_callback(2, TdLogCallback);
    g_clientId = td_create_client_id();
    g_created = true;
    g_running.store(true);
    g_receiveThread = std::thread(ReceiveLoop);
    // A newly created client id is inert until the first request activates it and
    // starts the authorization flow; kick it with a cheap getOption.
    td_send(g_clientId, "{\"@type\":\"getOption\",\"name\":\"version\"}");
    return nullptr;
}

napi_value TdSend(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char *request = new char[len + 1];
    napi_get_value_string_utf8(env, args[0], request, len + 1, &len);
    if (!g_created) {
        napi_throw_error(env, nullptr, "tdSend before tdInit");
        delete[] request;
        return nullptr;
    }
    td_send(g_clientId, request);
    delete[] request;
    return nullptr;
}

napi_value TdExecute(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char *request = new char[len + 1];
    napi_get_value_string_utf8(env, args[0], request, len + 1, &len);
    const char *result = td_execute(request);
    napi_value out;
    napi_create_string_utf8(env, result == nullptr ? "" : result, NAPI_AUTO_LENGTH, &out);
    delete[] request;
    return out;
}

napi_value TdDestroy(napi_env env, napi_callback_info info) {
    if (!g_created) {
        return nullptr;
    }
    g_running.store(false);
    // td_receive returns after its timeout, letting the loop observe g_running.
    if (g_receiveThread.joinable()) {
        g_receiveThread.join();
    }
    g_created = false;
    if (g_onReceive != nullptr) {
        napi_release_threadsafe_function(g_onReceive, napi_tsfn_release);
        g_onReceive = nullptr;
    }
    return nullptr;
}
} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"tdInit", nullptr, TdInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tdSend", nullptr, TdSend, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tdExecute", nullptr, TdExecute, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tdDestroy", nullptr, TdDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
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
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
