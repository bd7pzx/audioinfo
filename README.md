# AudioInfo

鸿蒙 6 下的音频输出信息查看应用，基于 ArkTS + ArkUI 实时展示系统音频输出设备、流状态和无线链路推断信息。

## 功能与接口

| 功能 | 使用接口 |
| --- | --- |
| 实时音频流状态 | `audio.getAudioManager()`、`AudioManager.getStreamManager()`、`AudioStreamManager.on('audioRendererChange')`、`AudioStreamManager.getCurrentAudioRendererInfoArraySync()`、`AudioRendererChangeInfo.rendererInfo.usage`、`AudioRendererChangeInfo.deviceDescriptors` |
| 当前输出设备展示 | `AudioManager.getRoutingManager()`、`AudioRoutingManager.on('availableDeviceChange')`、`AudioRoutingManager.getAvailableDevices(audio.DeviceUsage.MEDIA_OUTPUT_DEVICES)`、`AudioDeviceDescriptor.id/name/displayName/address/deviceType/sampleRates/channelCounts/encodingTypes/capabilities` |
| 多设备切换 | `ForEach`、`Button`、`Text`、`onClick()`、`@State selectedOutputDeviceId` |
| 无线协议识别 | `audio.DeviceType.NEARLINK`、`audio.DeviceType.BLUETOOTH_A2DP`、`audio.DeviceType.BLUETOOTH_SCO` |
| 蓝牙连接状态 | `a2dp.createA2dpSrcProfile()`、`BaseProfile.getConnectedDevices()`、`A2dpSourceProfile.getPlayingState()`、`BaseProfile.on('connectionStateChange')`、`BaseProfile.off('connectionStateChange')`、`connection.getProfileConnectionState(constant.ProfileId.PROFILE_A2DP_SOURCE)`、`constant.ProfileConnectionState`、`a2dp.PlayingState` |
| 无线码率估算与编码器推断 | `AudioDeviceDescriptor.capabilities`、`AudioStreamInfo.samplingRate/channels/sampleFormat/encodingType`、`audio.AudioSampleFormat`、`audio.AudioEncodingType` |
| 沉浸式状态栏/导航栏 | `UIAbility`、`windowStage.getMainWindowSync()`、`Window.setWindowLayoutFullScreen(true)`、`Window.setWindowSystemBarEnable(['status', 'navigation'])`、`Window.setWindowSystemBarProperties()` |
| 深色模式适配 | 资源色表 `entry/src/main/resources/base/element/color.json`、`entry/src/main/resources/dark/element/color.json`、`$r('app.color.*')` |
| 关于底部弹层 | `bindSheet()`、`SheetType.BOTTOM`、`SheetSize.MEDIUM`、`showClose`、`onDisappear` |

## 说明

- 当前公开 ArkTS API 不提供“蓝牙当前活跃编解码器”的直接读取接口，因此应用使用输出设备能力与推算码率做编码器推断。
- 应用内标题与应用名称已统一为 `AudioInfo`。

