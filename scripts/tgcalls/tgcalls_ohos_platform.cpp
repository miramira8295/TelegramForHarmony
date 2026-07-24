#include "tgcalls/platform/fake/FakeInterface.h"

#include "api/video_codecs/builtin_video_decoder_factory.h"
#include "api/video_codecs/builtin_video_encoder_factory.h"
#include "api/video_codecs/video_decoder.h"

#include <hilog/log.h>

#include <atomic>
#include <memory>
#include <utility>

#define TGVDECLOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-decoder", fmt, ##__VA_ARGS__)

namespace tgcalls {
namespace {

class LoggingVideoDecoder final : public webrtc::VideoDecoder {
public:
    LoggingVideoDecoder(std::string codec, std::unique_ptr<webrtc::VideoDecoder> inner)
        : codec_(std::move(codec)), inner_(std::move(inner)), callbackProxy_(this) {
    }

    bool Configure(const Settings &settings) override {
        const bool ok = inner_ != nullptr && inner_->Configure(settings);
        TGVDECLOG("configure codec=%{public}s ok=%{public}d cores=%{public}d max=%{public}dx%{public}d impl=%{public}s",
                  codec_.c_str(), ok ? 1 : 0, settings.number_of_cores(),
                  settings.max_render_resolution().Width(), settings.max_render_resolution().Height(),
                  inner_ ? inner_->GetDecoderInfo().implementation_name.c_str() : "null");
        return ok;
    }

    int32_t Decode(const webrtc::EncodedImage &image, bool missingFrames, int64_t renderTimeMs) override {
        const uint32_t count = ++decodeCount_;
        const int32_t result = inner_ ? inner_->Decode(image, missingFrames, renderTimeMs) : -1;
        if (count == 1 || result != 0 || count % 300 == 0) {
            TGVDECLOG("input codec=%{public}s count=%{public}u bytes=%{public}zu size=%{public}ux%{public}u key=%{public}d missing=%{public}d result=%{public}d",
                      codec_.c_str(), count, image.size(), image._encodedWidth, image._encodedHeight,
                      image._frameType == webrtc::VideoFrameType::kVideoFrameKey ? 1 : 0,
                      missingFrames ? 1 : 0, result);
        }
        return result;
    }

    int32_t RegisterDecodeCompleteCallback(webrtc::DecodedImageCallback *callback) override {
        callback_ = callback;
        const int32_t result = inner_ ? inner_->RegisterDecodeCompleteCallback(&callbackProxy_) : -1;
        TGVDECLOG("callback codec=%{public}s result=%{public}d", codec_.c_str(), result);
        return result;
    }

    int32_t Release() override {
        return inner_ ? inner_->Release() : 0;
    }

    DecoderInfo GetDecoderInfo() const override {
        return inner_ ? inner_->GetDecoderInfo() : DecoderInfo{};
    }

private:
    class CallbackProxy final : public webrtc::DecodedImageCallback {
    public:
        explicit CallbackProxy(LoggingVideoDecoder *owner) : owner_(owner) {
        }

        int32_t Decoded(webrtc::VideoFrame &frame) override {
            owner_->LogOutput(frame);
            return owner_->callback_ ? owner_->callback_->Decoded(frame) : 0;
        }

        int32_t Decoded(webrtc::VideoFrame &frame, int64_t decodeTimeMs) override {
            owner_->LogOutput(frame);
            return owner_->callback_ ? owner_->callback_->Decoded(frame, decodeTimeMs) : 0;
        }

        void Decoded(webrtc::VideoFrame &frame, absl::optional<int32_t> decodeTimeMs,
                     absl::optional<uint8_t> qp) override {
            owner_->LogOutput(frame);
            if (owner_->callback_) {
                owner_->callback_->Decoded(frame, decodeTimeMs, qp);
            }
        }

    private:
        LoggingVideoDecoder *owner_;
    };

    void LogOutput(const webrtc::VideoFrame &frame) {
        const uint32_t count = ++outputCount_;
        if (count == 1 || count % 300 == 0) {
            TGVDECLOG("output codec=%{public}s count=%{public}u size=%{public}dx%{public}d",
                      codec_.c_str(), count, frame.width(), frame.height());
        }
    }

    std::string codec_;
    std::unique_ptr<webrtc::VideoDecoder> inner_;
    webrtc::DecodedImageCallback *callback_ = nullptr;
    CallbackProxy callbackProxy_;
    std::atomic<uint32_t> decodeCount_{0};
    std::atomic<uint32_t> outputCount_{0};
};

class LoggingVideoDecoderFactory final : public webrtc::VideoDecoderFactory {
public:
    LoggingVideoDecoderFactory() : inner_(webrtc::CreateBuiltinVideoDecoderFactory()) {
        for (const auto &format : inner_->GetSupportedFormats()) {
            TGVDECLOG("supported=%{public}s", format.ToString().c_str());
        }
    }

    std::vector<webrtc::SdpVideoFormat> GetSupportedFormats() const override {
        return inner_->GetSupportedFormats();
    }

    CodecSupport QueryCodecSupport(const webrtc::SdpVideoFormat &format,
                                   bool referenceScaling) const override {
        return inner_->QueryCodecSupport(format, referenceScaling);
    }

    std::unique_ptr<webrtc::VideoDecoder> CreateVideoDecoder(
            const webrtc::SdpVideoFormat &format) override {
        auto decoder = inner_->CreateVideoDecoder(format);
        TGVDECLOG("create format=%{public}s ok=%{public}d", format.ToString().c_str(), decoder ? 1 : 0);
        return decoder
            ? std::make_unique<LoggingVideoDecoder>(format.name, std::move(decoder))
            : nullptr;
    }

private:
    std::unique_ptr<webrtc::VideoDecoderFactory> inner_;
};

}  // namespace

std::unique_ptr<webrtc::VideoEncoderFactory> FakeInterface::makeVideoEncoderFactory(
        bool preferHardwareEncoding, bool isScreencast) {
    return webrtc::CreateBuiltinVideoEncoderFactory();
}

std::unique_ptr<webrtc::VideoDecoderFactory> FakeInterface::makeVideoDecoderFactory() {
    return std::make_unique<LoggingVideoDecoderFactory>();
}

rtc::scoped_refptr<webrtc::VideoTrackSourceInterface> FakeInterface::makeVideoSource(
        rtc::Thread *signalingThread, rtc::Thread *workerThread) {
    return nullptr;
}

bool FakeInterface::supportsEncoding(const std::string &codecName) {
    const auto factory = webrtc::CreateBuiltinVideoEncoderFactory();
    if (factory == nullptr) {
        return false;
    }
    for (const auto &format : factory->GetSupportedFormats()) {
        if (format.name == codecName) {
            return true;
        }
    }
    return false;
}

void FakeInterface::adaptVideoSource(
        rtc::scoped_refptr<webrtc::VideoTrackSourceInterface> videoSource,
        int width, int height, int fps) {
}

std::unique_ptr<VideoCapturerInterface> FakeInterface::makeVideoCapturer(
        rtc::scoped_refptr<webrtc::VideoTrackSourceInterface> source, std::string deviceId,
        std::function<void(VideoState)> stateUpdated,
        std::function<void(PlatformCaptureInfo)> captureInfoUpdated,
        std::shared_ptr<PlatformContext> platformContext, std::pair<int, int> &outResolution) {
    return nullptr;
}

std::unique_ptr<PlatformInterface> CreatePlatformInterface() {
    return std::make_unique<FakeInterface>();
}

}  // namespace tgcalls
