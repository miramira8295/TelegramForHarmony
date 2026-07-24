#include "napi/native_api.h"
#include <hilog/log.h>
#include <atomic>
#include <cstdint>
#include <string>
#include <thread>

extern "C" {
int td_create_client_id();
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
void td_set_log_message_callback(int max_verbosity_level,
                                 void (*callback)(int verbosity_level, const char *message));

void *tgcalls_ohos_create(
    void (*callback)(void *, bool), void *context,
    void (*broadcastCallback)(void *, uint64_t, int, int64_t, int64_t, int32_t, int),
    void *broadcastContext,
    void (*audioActivityCallback)(void *, uint32_t, bool), void *audioActivityContext,
    void (*localVideoStateCallback)(void *, int, bool, int), void *localVideoStateContext,
    void (*videoGeometryCallback)(void *, const char *, int, int), void *videoGeometryContext,
    bool presentation);
void tgcalls_ohos_complete_broadcast_time(void *session, uint64_t requestId, int64_t timestampMilliseconds);
void tgcalls_ohos_complete_broadcast_part(
    void *session, uint64_t requestId, int64_t timestampMilliseconds,
    int status, double responseTimestamp, const uint8_t *data, size_t length);
void tgcalls_ohos_emit_join_payload(
    void *session, void (*callback)(void *, uint32_t, const char *), void *context);
void tgcalls_ohos_set_join_response(void *session, const char *payload);
void tgcalls_ohos_set_connection_mode(void *session, int mode, bool isUnifiedBroadcast);
void tgcalls_ohos_resume_media(void *session);
bool tgcalls_ohos_set_muted(void *session, bool muted);
bool tgcalls_ohos_set_local_video(
    void *session, int mode, uint32_t width, uint32_t height);
void tgcalls_ohos_set_local_video_surface(
    void *session, uint64_t surfaceId, uint32_t surfaceWidth, uint32_t surfaceHeight);
void tgcalls_ohos_set_video_surface(
    void *session, const char *endpointId, uint64_t surfaceId, uint32_t surfaceWidth, uint32_t surfaceHeight);
void tgcalls_ohos_set_video_channel(
    void *session, const char *endpointId, uint32_t audioSsrc, const char *ssrcGroups);
void tgcalls_ohos_remove_video_channel(void *session, const char *endpointId);
void tgcalls_ohos_clear_video(void *session);
void tgcalls_ohos_destroy(void *session);
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
void *g_tgcallsSession = nullptr;
void *g_tgcallsScreenSession = nullptr;
napi_threadsafe_function g_onTgcallsState = nullptr;
napi_threadsafe_function g_onTgcallsScreenState = nullptr;
napi_threadsafe_function g_onTgcallsBroadcastRequest = nullptr;
napi_threadsafe_function g_onTgcallsAudioActivity = nullptr;
napi_threadsafe_function g_onTgcallsLocalVideoState = nullptr;
napi_threadsafe_function g_onTgcallsVideoGeometry = nullptr;
napi_threadsafe_function g_onTgcallsScreenLocalVideoState = nullptr;
std::atomic<napi_threadsafe_function> g_onTgcallsJoin{nullptr};
std::atomic<napi_threadsafe_function> g_onTgcallsScreenJoin{nullptr};

struct JoinPayloadEvent {
    uint32_t audioSourceId;
    std::string payload;
};

struct BroadcastRequestEvent {
    uint64_t requestId;
    int kind;
    int64_t timestampMilliseconds;
    int64_t durationMilliseconds;
    int32_t channelId;
    int quality;
};

struct AudioActivityEvent {
    uint32_t audioSourceId;
    bool speaking;
};

struct LocalVideoStateEvent {
    int mode;
    bool active;
    int error;
};

struct VideoGeometryEvent {
    std::string endpointId;
    int width;
    int height;
};

napi_value Undefined(napi_env env) {
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

void CallJsTgcallsState(napi_env env, napi_value jsCallback, void *, void *data) {
    auto *connected = static_cast<bool *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value arg;
        napi_get_boolean(env, *connected, &arg);
        napi_call_function(env, Undefined(env), jsCallback, 1, &arg, nullptr);
    }
    delete connected;
}

void OnTgcallsState(void *context, bool connected) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    auto *copy = new bool(connected);
    if (napi_call_threadsafe_function(callback, copy, napi_tsfn_nonblocking) != napi_ok) {
        delete copy;
    }
}

void CallJsBroadcastRequest(napi_env env, napi_value jsCallback, void *, void *data) {
    auto *event = static_cast<BroadcastRequestEvent *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value args[6];
        napi_create_int64(env, static_cast<int64_t>(event->requestId), &args[0]);
        napi_create_int32(env, event->kind, &args[1]);
        napi_create_int64(env, event->timestampMilliseconds, &args[2]);
        napi_create_int64(env, event->durationMilliseconds, &args[3]);
        napi_create_int32(env, event->channelId, &args[4]);
        napi_create_int32(env, event->quality, &args[5]);
        napi_call_function(env, Undefined(env), jsCallback, 6, args, nullptr);
    }
    delete event;
}

void OnTgcallsBroadcastRequest(
        void *context, uint64_t requestId, int kind, int64_t timestampMilliseconds,
        int64_t durationMilliseconds, int32_t channelId, int quality) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    auto *event = new BroadcastRequestEvent{
        requestId, kind, timestampMilliseconds, durationMilliseconds, channelId, quality
    };
    if (napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking) != napi_ok) {
        delete event;
    }
}

void CallJsAudioActivity(napi_env env, napi_value jsCallback, void *, void *data) {
    auto *event = static_cast<AudioActivityEvent *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value args[2];
        napi_create_int32(env, static_cast<int32_t>(event->audioSourceId), &args[0]);
        napi_get_boolean(env, event->speaking, &args[1]);
        napi_call_function(env, Undefined(env), jsCallback, 2, args, nullptr);
    }
    delete event;
}

void OnTgcallsAudioActivity(void *context, uint32_t audioSourceId, bool speaking) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    auto *event = new AudioActivityEvent{audioSourceId, speaking};
    if (napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking) != napi_ok) {
        delete event;
    }
}

void CallJsLocalVideoState(napi_env env, napi_value jsCallback, void *, void *data) {
    auto *event = static_cast<LocalVideoStateEvent *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value args[3];
        napi_create_int32(env, event->mode, &args[0]);
        napi_get_boolean(env, event->active, &args[1]);
        napi_create_int32(env, event->error, &args[2]);
        napi_call_function(env, Undefined(env), jsCallback, 3, args, nullptr);
    }
    delete event;
}

void OnTgcallsLocalVideoState(void *context, int mode, bool active, int error) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    auto *event = new LocalVideoStateEvent{mode, active, error};
    if (napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking) != napi_ok) {
        delete event;
    }
}

void CallJsVideoGeometry(napi_env env, napi_value jsCallback, void *, void *data) {
    auto *event = static_cast<VideoGeometryEvent *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value args[3];
        napi_create_string_utf8(
            env, event->endpointId.c_str(), event->endpointId.size(), &args[0]);
        napi_create_int32(env, event->width, &args[1]);
        napi_create_int32(env, event->height, &args[2]);
        napi_call_function(env, Undefined(env), jsCallback, 3, args, nullptr);
    }
    delete event;
}

void OnTgcallsVideoGeometry(
        void *context, const char *endpointId, int width, int height) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    if (callback == nullptr) { return; }
    auto *event = new VideoGeometryEvent{
        endpointId == nullptr ? "" : endpointId, width, height
    };
    if (napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking) != napi_ok) {
        delete event;
    }
}

void CallJsJoinPayload(napi_env env, napi_value jsCallback, void *, void *data) {
    auto *event = static_cast<JoinPayloadEvent *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value args[2];
        napi_create_int32(env, static_cast<int32_t>(event->audioSourceId), &args[0]);
        napi_create_string_utf8(env, event->payload.c_str(), event->payload.size(), &args[1]);
        napi_call_function(env, Undefined(env), jsCallback, 2, args, nullptr);
    }
    delete event;
}

void OnTgcallsJoinPayload(void *context, uint32_t audioSourceId, const char *payload) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    auto *event = new JoinPayloadEvent{
        audioSourceId,
        payload == nullptr ? "" : payload,
    };
    const napi_status status = napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking);
    if (status != napi_ok) {
        delete event;
    }
    napi_threadsafe_function expected = callback;
    if (g_onTgcallsJoin.compare_exchange_strong(expected, nullptr)) {
        // emitJoinPayload completes once. Release the native thread's
        // ownership after queueing; a concurrent destroy wins the exchange
        // and performs the single matching abort instead.
        napi_release_threadsafe_function(callback, napi_tsfn_release);
    }
}

void OnTgcallsScreenJoinPayload(void *context, uint32_t audioSourceId, const char *payload) {
    auto callback = static_cast<napi_threadsafe_function>(context);
    auto *event = new JoinPayloadEvent{
        audioSourceId,
        payload == nullptr ? "" : payload,
    };
    const napi_status status = napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking);
    if (status != napi_ok) {
        delete event;
    }
    napi_threadsafe_function expected = callback;
    if (g_onTgcallsScreenJoin.compare_exchange_strong(expected, nullptr)) {
        napi_release_threadsafe_function(callback, napi_tsfn_release);
    }
}

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

napi_value TgcallsCreate(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_tgcallsSession != nullptr) {
        napi_throw_error(env, nullptr, "tgcalls session already exists");
        return nullptr;
    }
    napi_valuetype stateCallbackType = napi_undefined;
    napi_valuetype broadcastCallbackType = napi_undefined;
    napi_valuetype audioActivityCallbackType = napi_undefined;
    napi_valuetype localVideoCallbackType = napi_undefined;
    napi_valuetype videoGeometryCallbackType = napi_undefined;
    if (argc != 5 || napi_typeof(env, args[0], &stateCallbackType) != napi_ok ||
        stateCallbackType != napi_function || napi_typeof(env, args[1], &broadcastCallbackType) != napi_ok ||
        broadcastCallbackType != napi_function ||
        napi_typeof(env, args[2], &audioActivityCallbackType) != napi_ok ||
        audioActivityCallbackType != napi_function ||
        napi_typeof(env, args[3], &localVideoCallbackType) != napi_ok ||
        localVideoCallbackType != napi_function ||
        napi_typeof(env, args[4], &videoGeometryCallbackType) != napi_ok ||
        videoGeometryCallbackType != napi_function) {
        napi_throw_type_error(
            env, nullptr,
            "tgcallsCreate expects state, broadcast-request, audio-activity, local-video, and geometry callbacks");
        return nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "tgcallsState", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr,
                                        nullptr, CallJsTgcallsState, &g_onTgcallsState) != napi_ok) {
        napi_throw_error(env, nullptr, "failed to create tgcalls state callback");
        return nullptr;
    }
    napi_value broadcastResourceName;
    napi_create_string_utf8(env, "tgcallsBroadcastRequest", NAPI_AUTO_LENGTH, &broadcastResourceName);
    if (napi_create_threadsafe_function(env, args[1], nullptr, broadcastResourceName, 0, 1, nullptr, nullptr,
                                        nullptr, CallJsBroadcastRequest,
                                        &g_onTgcallsBroadcastRequest) != napi_ok) {
        napi_release_threadsafe_function(g_onTgcallsState, napi_tsfn_abort);
        g_onTgcallsState = nullptr;
        napi_throw_error(env, nullptr, "failed to create tgcalls broadcast callback");
        return nullptr;
    }
    napi_value audioActivityResourceName;
    napi_create_string_utf8(env, "tgcallsAudioActivity", NAPI_AUTO_LENGTH, &audioActivityResourceName);
    if (napi_create_threadsafe_function(
            env, args[2], nullptr, audioActivityResourceName, 0, 1, nullptr, nullptr,
            nullptr, CallJsAudioActivity, &g_onTgcallsAudioActivity) != napi_ok) {
        napi_release_threadsafe_function(g_onTgcallsState, napi_tsfn_abort);
        g_onTgcallsState = nullptr;
        napi_release_threadsafe_function(g_onTgcallsBroadcastRequest, napi_tsfn_abort);
        g_onTgcallsBroadcastRequest = nullptr;
        napi_throw_error(env, nullptr, "failed to create tgcalls audio-activity callback");
        return nullptr;
    }
    napi_value localVideoResourceName;
    napi_create_string_utf8(env, "tgcallsLocalVideoState", NAPI_AUTO_LENGTH, &localVideoResourceName);
    if (napi_create_threadsafe_function(
            env, args[3], nullptr, localVideoResourceName, 0, 1, nullptr, nullptr,
            nullptr, CallJsLocalVideoState, &g_onTgcallsLocalVideoState) != napi_ok) {
        napi_release_threadsafe_function(g_onTgcallsState, napi_tsfn_abort);
        g_onTgcallsState = nullptr;
        napi_release_threadsafe_function(g_onTgcallsBroadcastRequest, napi_tsfn_abort);
        g_onTgcallsBroadcastRequest = nullptr;
        napi_release_threadsafe_function(g_onTgcallsAudioActivity, napi_tsfn_abort);
        g_onTgcallsAudioActivity = nullptr;
        napi_throw_error(env, nullptr, "failed to create tgcalls local-video callback");
        return nullptr;
    }
    napi_value videoGeometryResourceName;
    napi_create_string_utf8(
        env, "tgcallsVideoGeometry", NAPI_AUTO_LENGTH, &videoGeometryResourceName);
    if (napi_create_threadsafe_function(
            env, args[4], nullptr, videoGeometryResourceName, 0, 1, nullptr, nullptr,
            nullptr, CallJsVideoGeometry, &g_onTgcallsVideoGeometry) != napi_ok) {
        napi_release_threadsafe_function(g_onTgcallsState, napi_tsfn_abort);
        g_onTgcallsState = nullptr;
        napi_release_threadsafe_function(g_onTgcallsBroadcastRequest, napi_tsfn_abort);
        g_onTgcallsBroadcastRequest = nullptr;
        napi_release_threadsafe_function(g_onTgcallsAudioActivity, napi_tsfn_abort);
        g_onTgcallsAudioActivity = nullptr;
        napi_release_threadsafe_function(g_onTgcallsLocalVideoState, napi_tsfn_abort);
        g_onTgcallsLocalVideoState = nullptr;
        napi_throw_error(env, nullptr, "failed to create tgcalls video-geometry callback");
        return nullptr;
    }
    g_tgcallsSession = tgcalls_ohos_create(
        OnTgcallsState, g_onTgcallsState,
        OnTgcallsBroadcastRequest, g_onTgcallsBroadcastRequest,
        OnTgcallsAudioActivity, g_onTgcallsAudioActivity,
        OnTgcallsLocalVideoState, g_onTgcallsLocalVideoState,
        OnTgcallsVideoGeometry, g_onTgcallsVideoGeometry,
        false);
    if (g_tgcallsSession == nullptr) {
        napi_release_threadsafe_function(g_onTgcallsState, napi_tsfn_abort);
        g_onTgcallsState = nullptr;
        napi_release_threadsafe_function(g_onTgcallsBroadcastRequest, napi_tsfn_abort);
        g_onTgcallsBroadcastRequest = nullptr;
        napi_release_threadsafe_function(g_onTgcallsAudioActivity, napi_tsfn_abort);
        g_onTgcallsAudioActivity = nullptr;
        napi_release_threadsafe_function(g_onTgcallsLocalVideoState, napi_tsfn_abort);
        g_onTgcallsLocalVideoState = nullptr;
        napi_release_threadsafe_function(g_onTgcallsVideoGeometry, napi_tsfn_abort);
        g_onTgcallsVideoGeometry = nullptr;
        napi_throw_error(env, nullptr, "failed to create tgcalls session");
        return nullptr;
    }
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value TgcallsEmitJoinPayload(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_tgcallsSession == nullptr) {
        napi_throw_error(env, nullptr, "tgcallsEmitJoinPayload before tgcallsCreate");
        return nullptr;
    }
    if (g_onTgcallsJoin.load() != nullptr) {
        napi_throw_error(env, nullptr, "a tgcalls join payload request is already pending");
        return nullptr;
    }
    napi_valuetype callbackType = napi_undefined;
    if (argc != 1 || napi_typeof(env, args[0], &callbackType) != napi_ok || callbackType != napi_function) {
        napi_throw_type_error(env, nullptr, "tgcallsEmitJoinPayload expects a callback");
        return nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "tgcallsJoinPayload", NAPI_AUTO_LENGTH, &resourceName);
    napi_threadsafe_function joinCallback = nullptr;
    if (napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr,
                                        nullptr, CallJsJoinPayload, &joinCallback) != napi_ok) {
        napi_throw_error(env, nullptr, "failed to create tgcalls join callback");
        return nullptr;
    }
    g_onTgcallsJoin.store(joinCallback);
    tgcalls_ohos_emit_join_payload(g_tgcallsSession, OnTgcallsJoinPayload, joinCallback);
    return Undefined(env);
}

napi_value TgcallsScreenShareCreate(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_tgcallsScreenSession != nullptr) {
        napi_throw_error(env, nullptr, "tgcalls screen-sharing session already exists");
        return nullptr;
    }
    napi_valuetype stateCallbackType = napi_undefined;
    napi_valuetype localVideoCallbackType = napi_undefined;
    uint32_t width = 0;
    uint32_t height = 0;
    if (argc != 4 || napi_typeof(env, args[0], &stateCallbackType) != napi_ok ||
        stateCallbackType != napi_function ||
        napi_typeof(env, args[1], &localVideoCallbackType) != napi_ok ||
        localVideoCallbackType != napi_function ||
        napi_get_value_uint32(env, args[2], &width) != napi_ok ||
        napi_get_value_uint32(env, args[3], &height) != napi_ok ||
        width == 0 || height == 0) {
        napi_throw_type_error(
            env, nullptr,
            "tgcallsScreenShareCreate expects state callback, video callback, width, and height");
        return nullptr;
    }

    napi_value stateResourceName;
    napi_create_string_utf8(
        env, "tgcallsScreenShareState", NAPI_AUTO_LENGTH, &stateResourceName);
    if (napi_create_threadsafe_function(
            env, args[0], nullptr, stateResourceName, 0, 1, nullptr, nullptr,
            nullptr, CallJsTgcallsState, &g_onTgcallsScreenState) != napi_ok) {
        napi_throw_error(env, nullptr, "failed to create screen-sharing state callback");
        return nullptr;
    }
    napi_value videoResourceName;
    napi_create_string_utf8(
        env, "tgcallsScreenShareVideoState", NAPI_AUTO_LENGTH, &videoResourceName);
    if (napi_create_threadsafe_function(
            env, args[1], nullptr, videoResourceName, 0, 1, nullptr, nullptr,
            nullptr, CallJsLocalVideoState,
            &g_onTgcallsScreenLocalVideoState) != napi_ok) {
        napi_release_threadsafe_function(g_onTgcallsScreenState, napi_tsfn_abort);
        g_onTgcallsScreenState = nullptr;
        napi_throw_error(env, nullptr, "failed to create screen-sharing video callback");
        return nullptr;
    }

    g_tgcallsScreenSession = tgcalls_ohos_create(
        OnTgcallsState, g_onTgcallsScreenState,
        nullptr, nullptr,
        nullptr, nullptr,
        OnTgcallsLocalVideoState, g_onTgcallsScreenLocalVideoState,
        nullptr, nullptr,
        true);
    if (g_tgcallsScreenSession == nullptr ||
        !tgcalls_ohos_set_local_video(g_tgcallsScreenSession, 3, width, height)) {
        if (g_tgcallsScreenSession != nullptr) {
            tgcalls_ohos_destroy(g_tgcallsScreenSession);
            g_tgcallsScreenSession = nullptr;
        }
        napi_release_threadsafe_function(g_onTgcallsScreenState, napi_tsfn_abort);
        g_onTgcallsScreenState = nullptr;
        napi_release_threadsafe_function(
            g_onTgcallsScreenLocalVideoState, napi_tsfn_abort);
        g_onTgcallsScreenLocalVideoState = nullptr;
        napi_throw_error(env, nullptr, "failed to create screen-sharing tgcalls session");
        return nullptr;
    }
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value TgcallsScreenShareEmitJoinPayload(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (g_tgcallsScreenSession == nullptr) {
        napi_throw_error(env, nullptr, "screen-sharing join before session creation");
        return nullptr;
    }
    if (g_onTgcallsScreenJoin.load() != nullptr) {
        napi_throw_error(env, nullptr, "a screen-sharing join payload request is already pending");
        return nullptr;
    }
    napi_valuetype callbackType = napi_undefined;
    if (argc != 1 || napi_typeof(env, args[0], &callbackType) != napi_ok ||
        callbackType != napi_function) {
        napi_throw_type_error(
            env, nullptr, "tgcallsScreenShareEmitJoinPayload expects a callback");
        return nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(
        env, "tgcallsScreenShareJoinPayload", NAPI_AUTO_LENGTH, &resourceName);
    napi_threadsafe_function joinCallback = nullptr;
    if (napi_create_threadsafe_function(
            env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr,
            nullptr, CallJsJoinPayload, &joinCallback) != napi_ok) {
        napi_throw_error(env, nullptr, "failed to create screen-sharing join callback");
        return nullptr;
    }
    g_onTgcallsScreenJoin.store(joinCallback);
    tgcalls_ohos_emit_join_payload(
        g_tgcallsScreenSession, OnTgcallsScreenJoinPayload, joinCallback);
    return Undefined(env);
}

bool ReadString(napi_env env, napi_value value, std::string &result) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    result.resize(length + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, &result[0], length + 1, &copied) != napi_ok) {
        return false;
    }
    result.resize(copied);
    return true;
}

napi_value TgcallsSetJoinResponse(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string payload;
    if (g_tgcallsSession == nullptr || argc != 1 || !ReadString(env, args[0], payload)) {
        napi_throw_type_error(env, nullptr, "tgcallsSetJoinResponse expects an active session and a string");
        return nullptr;
    }
    tgcalls_ohos_set_join_response(g_tgcallsSession, payload.c_str());
    return Undefined(env);
}

napi_value TgcallsScreenShareSetJoinResponse(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string payload;
    if (g_tgcallsScreenSession == nullptr || argc != 1 ||
        !ReadString(env, args[0], payload)) {
        napi_throw_type_error(
            env, nullptr,
            "tgcallsScreenShareSetJoinResponse expects an active session and a string");
        return nullptr;
    }
    tgcalls_ohos_set_join_response(g_tgcallsScreenSession, payload.c_str());
    return Undefined(env);
}

napi_value TgcallsSetConnectionMode(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t mode = 0;
    bool isUnifiedBroadcast = false;
    if (g_tgcallsSession == nullptr || argc != 2 || napi_get_value_int32(env, args[0], &mode) != napi_ok ||
        mode < 0 || mode > 2 || napi_get_value_bool(env, args[1], &isUnifiedBroadcast) != napi_ok) {
        napi_throw_type_error(env, nullptr,
                              "tgcallsSetConnectionMode expects mode 0..2 and unified-broadcast boolean");
        return nullptr;
    }
    tgcalls_ohos_set_connection_mode(g_tgcallsSession, mode, isUnifiedBroadcast);
    return Undefined(env);
}

napi_value TgcallsScreenShareSetConnectionMode(napi_env env, napi_callback_info info) {
    if (g_tgcallsScreenSession == nullptr) {
        napi_throw_error(env, nullptr, "screen-sharing connection before session creation");
        return nullptr;
    }
    tgcalls_ohos_set_connection_mode(g_tgcallsScreenSession, 1, false);
    return Undefined(env);
}

napi_value TgcallsCompleteBroadcastTime(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t requestId = 0;
    int64_t timestampMilliseconds = 0;
    if (g_tgcallsSession == nullptr || argc != 2 ||
        napi_get_value_int64(env, args[0], &requestId) != napi_ok ||
        napi_get_value_int64(env, args[1], &timestampMilliseconds) != napi_ok || requestId <= 0) {
        napi_throw_type_error(env, nullptr,
                              "tgcallsCompleteBroadcastTime expects (requestId, timestampMs)");
        return nullptr;
    }
    tgcalls_ohos_complete_broadcast_time(
        g_tgcallsSession, static_cast<uint64_t>(requestId), timestampMilliseconds);
    return Undefined(env);
}

napi_value TgcallsCompleteBroadcastPart(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t requestId = 0;
    int64_t timestampMilliseconds = 0;
    int32_t status = 1;
    double responseTimestamp = 0.0;
    napi_typedarray_type arrayType = napi_uint8_array;
    size_t length = 0;
    void *data = nullptr;
    napi_value arrayBuffer = nullptr;
    size_t byteOffset = 0;
    if (g_tgcallsSession == nullptr || argc != 5 ||
        napi_get_value_int64(env, args[0], &requestId) != napi_ok || requestId <= 0 ||
        napi_get_value_int64(env, args[1], &timestampMilliseconds) != napi_ok ||
        napi_get_value_int32(env, args[2], &status) != napi_ok || status < 0 || status > 2 ||
        napi_get_value_double(env, args[3], &responseTimestamp) != napi_ok ||
        napi_get_typedarray_info(
            env, args[4], &arrayType, &length, &data, &arrayBuffer, &byteOffset) != napi_ok ||
        arrayType != napi_uint8_array) {
        napi_throw_type_error(env, nullptr,
                              "tgcallsCompleteBroadcastPart expects request, timestamp, status, response time, Uint8Array");
        return nullptr;
    }
    tgcalls_ohos_complete_broadcast_part(
        g_tgcallsSession, static_cast<uint64_t>(requestId), timestampMilliseconds,
        status, responseTimestamp, static_cast<const uint8_t *>(data), length);
    return Undefined(env);
}

napi_value TgcallsSetMuted(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool muted = true;
    if (g_tgcallsSession == nullptr || argc != 1 || napi_get_value_bool(env, args[0], &muted) != napi_ok) {
        napi_throw_type_error(env, nullptr, "tgcallsSetMuted expects an active session and a boolean");
        return nullptr;
    }
    napi_value result;
    napi_get_boolean(env, tgcalls_ohos_set_muted(g_tgcallsSession, muted), &result);
    return result;
}

napi_value TgcallsSetLocalVideo(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t mode = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    if (g_tgcallsSession == nullptr || argc != 3 ||
        napi_get_value_int32(env, args[0], &mode) != napi_ok ||
        napi_get_value_uint32(env, args[1], &width) != napi_ok ||
        napi_get_value_uint32(env, args[2], &height) != napi_ok ||
        mode < 0 || mode > 3) {
        napi_throw_type_error(
            env, nullptr,
            "tgcallsSetLocalVideo expects (mode 0..3, width, height)");
        return nullptr;
    }
    napi_value result;
    napi_get_boolean(
        env,
        tgcalls_ohos_set_local_video(g_tgcallsSession, mode, width, height),
        &result);
    return result;
}

napi_value TgcallsResumeMedia(napi_env env, napi_callback_info info) {
    if (g_tgcallsSession != nullptr) {
        tgcalls_ohos_resume_media(g_tgcallsSession);
    }
    return Undefined(env);
}

napi_value TgcallsSetLocalVideoSurface(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string surfaceIdStr;
    uint32_t surfaceWidth = 0;
    uint32_t surfaceHeight = 0;
    if (g_tgcallsSession == nullptr || argc != 3 ||
        !ReadString(env, args[0], surfaceIdStr) ||
        napi_get_value_uint32(env, args[1], &surfaceWidth) != napi_ok ||
        napi_get_value_uint32(env, args[2], &surfaceHeight) != napi_ok) {
        napi_throw_type_error(
            env, nullptr,
            "tgcallsSetLocalVideoSurface expects (surfaceId, width, height)");
        return nullptr;
    }
    const uint64_t surfaceId = strtoull(surfaceIdStr.c_str(), nullptr, 10);
    tgcalls_ohos_set_local_video_surface(
        g_tgcallsSession, surfaceId, surfaceWidth, surfaceHeight);
    return Undefined(env);
}

napi_value TgcallsSetVideoSurface(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string endpointId;
    std::string surfaceIdStr;
    uint32_t surfaceWidth = 0;
    uint32_t surfaceHeight = 0;
    if (g_tgcallsSession == nullptr || argc != 4 || !ReadString(env, args[0], endpointId) ||
        !ReadString(env, args[1], surfaceIdStr) ||
        napi_get_value_uint32(env, args[2], &surfaceWidth) != napi_ok ||
        napi_get_value_uint32(env, args[3], &surfaceHeight) != napi_ok) {
        napi_throw_type_error(env, nullptr,
                              "tgcallsSetVideoSurface expects (endpointId, surfaceId, width, height)");
        return nullptr;
    }
    const uint64_t surfaceId = strtoull(surfaceIdStr.c_str(), nullptr, 10);
    tgcalls_ohos_set_video_surface(
        g_tgcallsSession, endpointId.c_str(), surfaceId, surfaceWidth, surfaceHeight);
    return Undefined(env);
}

napi_value TgcallsSetVideoChannel(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string endpointId;
    std::string ssrcGroups;
    uint32_t audioSsrc = 0;
    if (g_tgcallsSession == nullptr || argc != 3 || !ReadString(env, args[0], endpointId) ||
        napi_get_value_uint32(env, args[1], &audioSsrc) != napi_ok || !ReadString(env, args[2], ssrcGroups)) {
        napi_throw_type_error(env, nullptr,
                              "tgcallsSetVideoChannel expects (endpointId, audioSsrc, ssrcGroups)");
        return nullptr;
    }
    tgcalls_ohos_set_video_channel(g_tgcallsSession, endpointId.c_str(), audioSsrc, ssrcGroups.c_str());
    return Undefined(env);
}

napi_value TgcallsRemoveVideoChannel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string endpointId;
    if (g_tgcallsSession == nullptr || argc != 1 || !ReadString(env, args[0], endpointId)) {
        napi_throw_type_error(env, nullptr, "tgcallsRemoveVideoChannel expects an endpointId string");
        return nullptr;
    }
    tgcalls_ohos_remove_video_channel(g_tgcallsSession, endpointId.c_str());
    return Undefined(env);
}

napi_value TgcallsClearVideo(napi_env env, napi_callback_info info) {
    if (g_tgcallsSession != nullptr) {
        tgcalls_ohos_clear_video(g_tgcallsSession);
    }
    return Undefined(env);
}

void DestroyTgcallsScreenShare() {
    if (g_tgcallsScreenSession != nullptr) {
        tgcalls_ohos_destroy(g_tgcallsScreenSession);
        g_tgcallsScreenSession = nullptr;
    }
    const napi_threadsafe_function joinCallback =
        g_onTgcallsScreenJoin.exchange(nullptr);
    if (joinCallback != nullptr) {
        napi_release_threadsafe_function(joinCallback, napi_tsfn_abort);
    }
    if (g_onTgcallsScreenState != nullptr) {
        napi_release_threadsafe_function(g_onTgcallsScreenState, napi_tsfn_release);
        g_onTgcallsScreenState = nullptr;
    }
    if (g_onTgcallsScreenLocalVideoState != nullptr) {
        napi_release_threadsafe_function(
            g_onTgcallsScreenLocalVideoState, napi_tsfn_release);
        g_onTgcallsScreenLocalVideoState = nullptr;
    }
}

napi_value TgcallsScreenShareDestroy(napi_env env, napi_callback_info info) {
    DestroyTgcallsScreenShare();
    return Undefined(env);
}

napi_value TgcallsDestroy(napi_env env, napi_callback_info info) {
    DestroyTgcallsScreenShare();
    if (g_tgcallsSession != nullptr) {
        tgcalls_ohos_destroy(g_tgcallsSession);
        g_tgcallsSession = nullptr;
    }
    const napi_threadsafe_function joinCallback = g_onTgcallsJoin.exchange(nullptr);
    if (joinCallback != nullptr) {
        napi_release_threadsafe_function(joinCallback, napi_tsfn_abort);
    }
    if (g_onTgcallsState != nullptr) {
        napi_release_threadsafe_function(g_onTgcallsState, napi_tsfn_release);
        g_onTgcallsState = nullptr;
    }
    if (g_onTgcallsBroadcastRequest != nullptr) {
        napi_release_threadsafe_function(g_onTgcallsBroadcastRequest, napi_tsfn_release);
        g_onTgcallsBroadcastRequest = nullptr;
    }
    if (g_onTgcallsAudioActivity != nullptr) {
        napi_release_threadsafe_function(g_onTgcallsAudioActivity, napi_tsfn_release);
        g_onTgcallsAudioActivity = nullptr;
    }
    if (g_onTgcallsLocalVideoState != nullptr) {
        napi_release_threadsafe_function(g_onTgcallsLocalVideoState, napi_tsfn_release);
        g_onTgcallsLocalVideoState = nullptr;
    }
    if (g_onTgcallsVideoGeometry != nullptr) {
        napi_release_threadsafe_function(g_onTgcallsVideoGeometry, napi_tsfn_release);
        g_onTgcallsVideoGeometry = nullptr;
    }
    return Undefined(env);
}
} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"tdInit", nullptr, TdInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tdSend", nullptr, TdSend, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tdExecute", nullptr, TdExecute, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tdDestroy", nullptr, TdDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsCreate", nullptr, TgcallsCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsEmitJoinPayload", nullptr, TgcallsEmitJoinPayload, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetJoinResponse", nullptr, TgcallsSetJoinResponse, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetConnectionMode", nullptr, TgcallsSetConnectionMode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsScreenShareCreate", nullptr, TgcallsScreenShareCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsScreenShareEmitJoinPayload", nullptr, TgcallsScreenShareEmitJoinPayload, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsScreenShareSetJoinResponse", nullptr, TgcallsScreenShareSetJoinResponse, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsScreenShareSetConnectionMode", nullptr, TgcallsScreenShareSetConnectionMode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsScreenShareDestroy", nullptr, TgcallsScreenShareDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsCompleteBroadcastTime", nullptr, TgcallsCompleteBroadcastTime, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsCompleteBroadcastPart", nullptr, TgcallsCompleteBroadcastPart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetMuted", nullptr, TgcallsSetMuted, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetLocalVideo", nullptr, TgcallsSetLocalVideo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetLocalVideoSurface", nullptr, TgcallsSetLocalVideoSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsResumeMedia", nullptr, TgcallsResumeMedia, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetVideoSurface", nullptr, TgcallsSetVideoSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsSetVideoChannel", nullptr, TgcallsSetVideoChannel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsRemoveVideoChannel", nullptr, TgcallsRemoveVideoChannel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsClearVideo", nullptr, TgcallsClearVideo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgcallsDestroy", nullptr, TgcallsDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
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
