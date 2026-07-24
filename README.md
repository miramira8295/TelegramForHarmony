# TelegramForHarmony

一个开源的**非官方 HarmonyOS NEXT Telegram 客户端**。使用 ArkTS/ArkUI 编写，
通过原生 N-API 桥接 [TDLib](https://core.telegram.org/tdlib)（Telegram 官方客户端库）。

## 功能

- 登录与账号：
  - 手机号登录、国家/地区区号选择与搜索、验证码和两步验证密码
  - 根据 TDLib 返回结果区分应用内验证码、短信、电话等验证码送达方式
  - 多账号登录、切换与退出；记住最后使用的账号并在下次启动时恢复
- 会话列表：
  - 文件夹、归档、未读角标、实时更新与连接状态提示
  - 新建群组、打开“我的收藏”
  - 正在直播的聊天显示动态头像角标
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
- 联系人与群组：
  - 联系人列表按在线状态排序，可搜索本地联系人和服务器可发现的陌生用户
  - 支持通过姓名或 `@用户名` 打开陌生用户私聊
  - 新建群组支持搜索、选择本地联系人或陌生用户，已选成员跨搜索保留
- 通话记录页
- 群组语音与频道直播：
  - 实时展示直播状态、在线人数与进入确认；状态随直播创建/结束自动更新
  - 普通视频聊天支持多人语音、多路摄像头/屏幕共享、活跃说话人和麦克风状态
  - 本机开麦、前后摄像头切换、摄像头与系统录屏同时推流
  - 无视频时自动收起视频区域；多路视频按网格展示，支持横竖屏自适应与全屏
  - 支持应用内直播悬浮窗、大小窗切换及返回完整直播页
  - 支持频道单向直播观看和实时互动消息；频道消息可直接显示并从直播页发送
  - 音视频断流后自动重连并恢复订阅、麦克风和说话状态
- 资料页：
  - 用户/Bot 详情（简介、用户名、商务信息、故事、Stars 礼物赠送、共同群组）
  - 群组/频道详情（简介、邀请链接、成员列表）
  - 个人资料：设置头像（拍照 / 相册 / 表情）、编辑账号（姓名、简介、用户名、生日）、
    动态头像与 emoji 状态、二维码名片
- 设置：
  - 账号信息、多账号入口、聊天设置、隐私与安全、通知、数据与存储、聊天文件夹
  - 设备与会话管理：查看当前/活跃会话、接受通话与私密聊天、终止会话、
    终止其他会话和不活跃会话自动退出时间
  - 省电模式：按电量阈值自动生效，可独立控制动态贴纸、动态表情、聊天特效、
    通话动画、视频/GIF 自动播放、粒子效果和平滑转场
- 深色模式：跟随系统切换

> 陌生用户搜索遵循 Telegram/TDLib 的服务端可发现性规则，通常只能找到拥有公开
> 用户名或已进入服务端搜索范围的用户，不能通过该功能枚举任意手机号。

## 目录结构

```
AppScope/            应用级配置（包名、图标）
entry/src/main/ets/
  tdkit/             TDLib N-API 桥、客户端、鉴权服务
  store/             不可变 store + 订阅机制（会话、消息、资料等）
  pages/             ArkUI 页面（登录、会话列表、聊天、资料、搜索……）
  services/          媒体流式播放、直播后台任务、语音录制与播放
  util/              解析/格式化工具（富文本、相册、日期……）
entry/src/main/cpp/  原生桥（libentry.so → libtdjson.so / libtgcalls_ohos.so）
entry/src/test/      单元测试（通过 scripts/run-local-tests.sh 运行）
scripts/             TDLib/tgcalls 拉取与编译脚本、本地测试门禁
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

### 2. 获取 `libtgcalls_ohos.so`

聊天/频道直播使用移植到 HarmonyOS 的 `tgcalls` 生成真实的 ICE/DTLS join payload，
并提供 RTC 与频道广播的音视频收发。当前支持普通视频聊天的本机开麦、前后摄像头
切换、系统录屏推流和多路远端摄像头/屏幕共享，同时支持 TDLib 分片直播及 RTMP
unified 直播观看；画面直接渲染到 ArkUI XComponent，音频通过 OHAudio 播放/采集。
该原生库同样不提交到仓库，首次构建前运行：

```bash
bash scripts/build-tgcalls-ohos.sh
```

脚本会把产物安装到 `entry/libs/arm64-v8a/libtgcalls_ohos.so`。首次运行需下载并
编译 WebRTC，耗时较长；版本固定和当前媒体能力边界见
[`scripts/tgcalls/README.md`](scripts/tgcalls/README.md)。

### 3. Telegram API 凭据

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

### 4. 签名

`build-profile.json5` 中的 `signingConfigs` 为空。用 DevEco Studio 打开项目，通过
**File > Project Structure > Signing Configs > Support HarmonyOS Auto-Sign**
（需要华为开发者账号）在本地生成调试证书。任何签名材料都不需要提交或分享。

### 5. 构建与运行

用 DevEco Studio 打开并在 HarmonyOS NEXT 设备/模拟器上运行，或使用命令行：

```bash
hvigorw assembleHap --no-daemon
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
