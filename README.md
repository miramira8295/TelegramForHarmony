# TelegramForHarmony

一个开源的**非官方 HarmonyOS NEXT Telegram 客户端**。使用 ArkTS/ArkUI 编写，
通过原生 N-API 桥接 [TDLib](https://core.telegram.org/tdlib)（Telegram 官方客户端库）。

## 功能

- 登录：手机号 + 验证码 + 两步验证密码
- 会话列表：文件夹、归档、未读角标、实时更新、连接状态提示
- 聊天页：
  - 富文本（链接、提及、代码、引用）、图片（低清 → 高清渐进加载）、
    图片/视频九宫格相册（瀑布流布局）
  - 视频流式播放（完整播放器控件）、贴纸（静态 WEBP、TGS 动画、WEBM 视频贴纸）、
    动态表情与自定义表情
  - 文件（下载 / 打开 / 另存）、链接预览、回复（可跳转原消息）、转发、
    表情回应、频道评论串、Bot 内联键盘、置顶消息、日期分隔与浮动日期条、
    未读分界定位
  - 消息多选：批量复制、删除（含“为所有人删除”）
- 发送：文字、自定义表情、`@` 提及与 `/` 命令自动补全、文件附件
- 全屏媒体查看器：打开/关闭的 Hero 转场、左右滑动切换、缩略图条、保存到相册
- 全局搜索：11 个标签页（聊天/频道/应用/帖子/公开贴文/媒体/下载/链接/文件/音频/语音），
  支持左右滑动切换与滚动自动翻页
- 通话记录页
- 资料页：
  - 用户/Bot 详情（简介、用户名、商务信息、故事、Stars 礼物赠送、共同群组）
  - 群组/频道详情（简介、邀请链接、成员列表）
  - 个人资料：设置头像（拍照 / 相册 / 表情）、编辑账号（姓名、简介、用户名、生日）、
    动态头像与 emoji 状态、二维码名片
- 深色模式：跟随系统切换

## 目录结构

```
AppScope/            应用级配置（包名、图标）
entry/src/main/ets/
  tdkit/             TDLib N-API 桥、客户端、鉴权服务
  store/             不可变 store + 订阅机制（会话、消息、资料等）
  pages/             ArkUI 页面（登录、会话列表、聊天、资料、搜索……）
  services/          基于 TDLib 分片下载的视频按字节范围流式播放
  util/              解析/格式化工具（富文本、相册、日期……）
entry/src/main/cpp/  原生桥（libentry.so → libtdjson.so）
entry/src/test/      单元测试（通过 scripts/run-local-tests.sh 运行）
scripts/             TDLib 拉取/编译脚本、本地测试门禁
```

## 构建

### 环境要求

- **DevEco Studio 6.0+**（项目 `compatibleSdkVersion 6.0.0(20)`、
  `targetSdkVersion 6.1.1(24)`），含自带的 OpenHarmony SDK/NDK
- `curl` 与 `file`（macOS/Linux 自带）

### 1. 获取 `libtdjson.so`

应用以预编译原生库的形式内置 TDLib，路径为
`entry/libs/arm64-v8a/libtdjson.so`（约 32 MB，未提交到仓库）。二选一：

**方式 A — 下载预编译产物（推荐）：**

```bash
bash scripts/fetch-tdlib.sh [tag]   # 从本仓库的 GitHub Releases 下载
```

在包含该产物的 Release 发布之前，脚本会有意地以 404 失败，并提示你改用方式 B。

**方式 B — 从源码编译（较新的 Mac 上约 10-15 分钟）：**

```bash
# 需要 C++ 工具链与依赖：clang（Xcode CLT）、cmake、ninja、gperf、patchelf
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
bash scripts/build-tdlib.sh
```

该脚本端到端封装了
[`ErBWs/tdlib-ohos-build`](https://github.com/ErBWs/tdlib-ohos-build)：用 DevEco
NDK 为 arm64-v8a 交叉编译 OpenSSL（静态，`1_1_1w`）与 TDLib（release **1.8.54**），
在宿主机预先生成 TDLib 的 TL-schema 源码（交叉编译时必需），用 `patchelf` 把
SONAME 规范化为 `libtdjson.so`（不做这一步，原生桥会**静默**加载失败），
最后把产物拷贝到 `entry/libs/arm64-v8a/`。脚本还修复了上游构建脚本的若干 macOS
兼容性问题，且是幂等的 —— 可以放心重复执行。

### 2. Telegram API 凭据

TDLib 需要你自己的 `api_id`/`api_hash` —— 本仓库不提供任何凭据。

1. 在 <https://my.telegram.org/apps> 注册一个应用。
2. 把 `entry/src/main/ets/tdkit/ApiCredentials.template.ets` 复制为同目录下的
   `ApiCredentials.ets`。
3. 用你自己的凭据生成打包后的常量，并把打印出来的三个常量粘贴进去：

   ```bash
   node scripts/gen-creds.mjs <api_id> <api_hash>
   ```

`ApiCredentials.ets` 已被 gitignore —— **切勿提交真实凭据**，一旦泄露请立即吊销重建。
这里的值只做混淆（并非加密），仅用于提高从安装包中随手提取的门槛。

### 3. 签名

`build-profile.json5` 中的 `signingConfigs` 为空。用 DevEco Studio 打开项目，通过
**File > Project Structure > Signing Configs > Support HarmonyOS Auto-Sign**
（需要华为开发者账号）在本地生成调试证书。任何签名材料都不需要提交或分享。

### 4. 构建与运行

用 DevEco Studio 打开并在 HarmonyOS NEXT 设备/模拟器上运行，或使用命令行：

```bash
hvigorw --mode module -p module=entry@default -p product=default assembleHap
```

运行单元测试门禁：

```bash
./scripts/run-local-tests.sh    # 必须输出 "LOCAL TESTS: PASS"
```

## 状态与声明

- 开发中；界面以尽量贴近官方 Android 客户端为目标。
- 这是一个**非官方**客户端。请使用你自己的 API 凭据，并遵守
  [Telegram API 服务条款](https://core.telegram.org/api/terms)。

## 许可证

[Apache License 2.0](LICENSE)
