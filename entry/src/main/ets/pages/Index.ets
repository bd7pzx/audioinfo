import { window } from '@kit.ArkUI';
import { audio } from '@kit.AudioKit';
import { a2dp, baseProfile, connection, constant } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';



const DOMAIN = 0x3200;
const TAG = 'AudioInfoMonitor';

interface OutputDeviceTabItem {
  id: number;
  title: string;
}

@Entry
@Component
struct Index {
  // 1. 定义一个变量来存高度
  @State statusBarHeight: number = 0;

  // 2. 在插件加载时计算高度

  private readonly audioManager: audio.AudioManager = audio.getAudioManager();
  private readonly streamManager: audio.AudioStreamManager = this.audioManager.getStreamManager();
  private readonly routingManager: audio.AudioRoutingManager = this.audioManager.getRoutingManager();
  private mediaOutputDevices: Array<Readonly<audio.AudioDeviceDescriptor>> = [];

  private a2dpProfile?: a2dp.A2dpSourceProfile;
  private refreshTimer: number = -1;

  private readonly onRendererChange = (_infos: audio.AudioRendererChangeInfoArray): void => {
    this.refreshAudioSnapshot();
  };

  private readonly onAvailableDeviceChange = (_action: audio.DeviceChangeAction): void => {
    this.refreshAudioSnapshot();
  };

  private readonly onA2dpConnectionStateChange = (_state: baseProfile.StateChangeParam): void => {
    this.refreshBluetoothSnapshot();
  };

  @State rendererCount: number = 0;
  @State rendererUsageText: string = '无活跃流';
  @State currentDeviceName: string = '--';
  @State currentDeviceType: string = '--';
  @State deviceSampleRateText: string = '--';
  @State deviceChannelText: string = '--';
  @State deviceEncodingText: string = '--';
  @State capabilityText: string = '--';
  @State wirelessProtocolText: string = '未检测到无线输出';
  @State wirelessBitrateText: string = '--';
  @State wirelessCodecText: string = 'N/A';
  @State btConnectionText: string = '未知';
  @State outputDeviceTabs: Array<OutputDeviceTabItem> = [];
  @State selectedOutputDeviceId: number = -1;
  @State selectedDeviceIsWireless: boolean = false;
  @State selectedDeviceIsBluetooth: boolean = false;
  @State lastUpdateTime: string = '--';
  @State errorText: string = '';
  @State isAboutSheetVisible: boolean = false;

  aboutToAppear(): void {
    this.registerAudioListeners();
    this.initBluetoothProfile();
    this.refreshAll();
    this.startPolling();
    const uiContext = this.getUIContext();
    window.getLastWindow(uiContext.getHostContext(), (err, data) => {
      if (!err) {
        let avoidArea = data.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        // 使用 uiContext 的 px2vp 替代全局 px2vp
        this.statusBarHeight = uiContext.px2vp(avoidArea.topRect.height);
      }
    });
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.unregisterAudioListeners();
    this.releaseBluetoothProfile();
  }

  private registerAudioListeners(): void {
    try {
      this.streamManager.on('audioRendererChange', this.onRendererChange);
      this.routingManager.on('availableDeviceChange', audio.DeviceUsage.MEDIA_OUTPUT_DEVICES, this.onAvailableDeviceChange);
    } catch (err) {
      this.recordError('注册音频监听失败', err);
    }
  }

  private unregisterAudioListeners(): void {
    try {
      this.streamManager.off('audioRendererChange', this.onRendererChange);
      this.routingManager.off('availableDeviceChange', this.onAvailableDeviceChange);
    } catch (err) {
      this.recordError('注销音频监听失败', err);
    }
  }

  private initBluetoothProfile(): void {
    try {
      this.a2dpProfile = a2dp.createA2dpSrcProfile();
      this.a2dpProfile.on('connectionStateChange', this.onA2dpConnectionStateChange);
    } catch (err) {
      this.recordError('初始化蓝牙A2DP失败', err);
    }
  }

  private releaseBluetoothProfile(): void {
    if (!this.a2dpProfile) {
      return;
    }
    try {
      this.a2dpProfile.off('connectionStateChange', this.onA2dpConnectionStateChange);
    } catch (err) {
      this.recordError('释放蓝牙A2DP监听失败', err);
    }
  }

  private startPolling(): void {
    this.stopPolling();
    this.refreshTimer = setInterval(() => {
      this.refreshAll();
    }, 2000);
  }

  private stopPolling(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private refreshAll(): void {
    this.refreshAudioSnapshot();
    this.refreshBluetoothSnapshot();
    this.lastUpdateTime = this.getNowTime();
  }

  private refreshAudioSnapshot(): void {
    try {
      const rendererInfos: audio.AudioRendererChangeInfoArray = this.streamManager.getCurrentAudioRendererInfoArraySync();
      this.rendererCount = rendererInfos.length;
      this.rendererUsageText = this.buildRendererUsageText(rendererInfos);

      const availableDevices: audio.AudioDeviceDescriptors =
        this.routingManager.getAvailableDevices(audio.DeviceUsage.MEDIA_OUTPUT_DEVICES);
      this.mediaOutputDevices = availableDevices.slice();
      this.outputDeviceTabs = this.buildOutputDeviceTabs(this.mediaOutputDevices);

      if (this.mediaOutputDevices.length === 0) {
        this.resetSelectedDeviceDetails();
        return;
      }

      if (!this.hasDeviceId(this.selectedOutputDeviceId, this.mediaOutputDevices)) {
        this.selectedOutputDeviceId = this.pickDefaultDeviceId(rendererInfos, this.mediaOutputDevices);
      }
      this.applySelectedDeviceDetails();
    } catch (err) {
      this.recordError('读取音频路由信息失败', err);
    }
  }

  private refreshBluetoothSnapshot(): void {
    try {
      const profileState: constant.ProfileConnectionState =
        connection.getProfileConnectionState(constant.ProfileId.PROFILE_A2DP_SOURCE);
      this.btConnectionText = this.profileConnectionStateText(profileState);
    } catch (err) {
      this.recordError('读取蓝牙连接状态失败', err);
      return;
    }

    if (!this.a2dpProfile) {
      return;
    }

    try {
      const connectedDeviceIds: Array<string> = this.a2dpProfile.getConnectedDevices();
      if (connectedDeviceIds.length === 0) {
        this.btConnectionText = `${this.btConnectionText}，已连接设备: 0`;
        return;
      }

      const firstDeviceState: a2dp.PlayingState = this.a2dpProfile.getPlayingState(connectedDeviceIds[0]);
      const playingStateText: string =
        firstDeviceState === a2dp.PlayingState.STATE_PLAYING ? '播放中' : '未播放';
      this.btConnectionText = `${this.btConnectionText}，已连接设备: ${connectedDeviceIds.length}，首设备状态: ${playingStateText}`;
    } catch (err) {
      this.recordError('读取蓝牙设备列表失败', err);
    }
  }

  private buildRendererUsageText(rendererInfos: audio.AudioRendererChangeInfoArray): string {
    if (rendererInfos.length === 0) {
      return '无活跃流';
    }
    let usageText: string = '';
    for (let index = 0; index < rendererInfos.length; index++) {
      const usage: audio.StreamUsage = rendererInfos[index].rendererInfo.usage;
      const usageName: string = this.streamUsageText(usage);
      if (index > 0) {
        usageText += ' / ';
      }
      usageText += usageName;
    }
    return usageText;
  }

  private buildOutputDeviceTabs(devices: Array<Readonly<audio.AudioDeviceDescriptor>>): Array<OutputDeviceTabItem> {
    const tabs: Array<OutputDeviceTabItem> = [];
    for (let index = 0; index < devices.length; index++) {
      const item: Readonly<audio.AudioDeviceDescriptor> = devices[index];
      tabs.push({
        id: item.id,
        title: `${this.deviceTypeText(item.deviceType)} · ${this.deviceDisplayName(item)}`
      });
    }
    return tabs;
  }

  private hasDeviceId(deviceId: number, devices: Array<Readonly<audio.AudioDeviceDescriptor>>): boolean {
    if (deviceId < 0) {
      return false;
    }
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].id === deviceId) {
        return true;
      }
    }
    return false;
  }

  private pickDefaultDeviceId(
    rendererInfos: audio.AudioRendererChangeInfoArray,
    devices: Array<Readonly<audio.AudioDeviceDescriptor>>
  ): number {
    if (rendererInfos.length > 0 && rendererInfos[0].deviceDescriptors.length > 0) {
      const rendererPreferredId: number = rendererInfos[0].deviceDescriptors[0].id;
      if (this.hasDeviceId(rendererPreferredId, devices)) {
        return rendererPreferredId;
      }
    }
    return devices[0].id;
  }

  private selectOutputDevice(deviceId: number): void {
    this.selectedOutputDeviceId = deviceId;
    this.applySelectedDeviceDetails();
  }

  private applySelectedDeviceDetails(): void {
    let selectedDevice: Readonly<audio.AudioDeviceDescriptor> | undefined = undefined;
    for (let index = 0; index < this.mediaOutputDevices.length; index++) {
      if (this.mediaOutputDevices[index].id === this.selectedOutputDeviceId) {
        selectedDevice = this.mediaOutputDevices[index];
        break;
      }
    }

    if (!selectedDevice) {
      this.resetSelectedDeviceDetails();
      return;
    }

    this.currentDeviceName = this.deviceDisplayName(selectedDevice);
    this.currentDeviceType = this.deviceTypeText(selectedDevice.deviceType);
    this.deviceSampleRateText = this.formatNumberArray(selectedDevice.sampleRates, 'Hz');
    this.deviceChannelText = this.formatNumberArray(selectedDevice.channelCounts, '声道');
    this.deviceEncodingText = this.formatEncodingTypes(selectedDevice.encodingTypes);
    this.capabilityText = this.formatCapabilities(selectedDevice.capabilities);

    this.selectedDeviceIsWireless = this.isWirelessDevice(selectedDevice.deviceType);
    this.selectedDeviceIsBluetooth = selectedDevice.deviceType === audio.DeviceType.BLUETOOTH_A2DP
      || selectedDevice.deviceType === audio.DeviceType.BLUETOOTH_SCO;
    if (this.selectedDeviceIsWireless) {
      this.wirelessProtocolText = this.protocolTextByDeviceType(selectedDevice.deviceType);
      this.updateWirelessCodecInference(selectedDevice);
      return;
    }

    this.wirelessProtocolText = '非无线输出';
    this.wirelessBitrateText = '--';
    this.wirelessCodecText = 'N/A';
  }

  private resetSelectedDeviceDetails(): void {
    this.mediaOutputDevices = [];
    this.selectedOutputDeviceId = -1;
    this.outputDeviceTabs = [];
    this.currentDeviceName = '--';
    this.currentDeviceType = '--';
    this.deviceSampleRateText = '--';
    this.deviceChannelText = '--';
    this.deviceEncodingText = '--';
    this.capabilityText = '--';
    this.wirelessProtocolText = '未检测到无线输出';
    this.wirelessBitrateText = '--';
    this.wirelessCodecText = 'N/A';
    this.selectedDeviceIsWireless = false;
    this.selectedDeviceIsBluetooth = false;
  }

  private streamUsageText(usage: audio.StreamUsage): string {
    switch (usage) {
      case audio.StreamUsage.STREAM_USAGE_MUSIC:
        return '音乐';
      case audio.StreamUsage.STREAM_USAGE_MOVIE:
        return '视频';
      case audio.StreamUsage.STREAM_USAGE_GAME:
        return '游戏';
      case audio.StreamUsage.STREAM_USAGE_NOTIFICATION:
        return '通知';
      case audio.StreamUsage.STREAM_USAGE_RINGTONE:
        return '铃声';
      case audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION:
        return '语音通话';
      case audio.StreamUsage.STREAM_USAGE_VOICE_ASSISTANT:
        return '语音助手';
      case audio.StreamUsage.STREAM_USAGE_AUDIOBOOK:
        return '有声书';
      case audio.StreamUsage.STREAM_USAGE_NAVIGATION:
        return '导航';
      case audio.StreamUsage.STREAM_USAGE_VIDEO_COMMUNICATION:
        return '视频通话';
      default:
        return `未知(${usage})`;
    }
  }

  private deviceDisplayName(device: Readonly<audio.AudioDeviceDescriptor>): string {
    if (device.displayName.length > 0) {
      return device.displayName;
    }
    if (device.name.length > 0) {
      return device.name;
    }
    return device.address.length > 0 ? device.address : '未命名设备';
  }

  private deviceTypeText(deviceType: audio.DeviceType): string {
    switch (deviceType) {
      case audio.DeviceType.SPEAKER:
        return '扬声器';
      case audio.DeviceType.EARPIECE:
        return '听筒';
      case audio.DeviceType.WIRED_HEADSET:
        return '有线耳机(含麦)';
      case audio.DeviceType.WIRED_HEADPHONES:
        return '有线耳机';
      case audio.DeviceType.USB_HEADSET:
        return 'USB耳机';
      case audio.DeviceType.USB_DEVICE:
        return 'USB音频设备';
      case audio.DeviceType.BLUETOOTH_A2DP:
        return '蓝牙A2DP';
      case audio.DeviceType.BLUETOOTH_SCO:
        return '蓝牙SCO';
      case audio.DeviceType.NEARLINK:
        return '星闪';
      default:
        return `其他(${deviceType})`;
    }
  }

  private protocolTextByDeviceType(deviceType: audio.DeviceType): string {
    switch (deviceType) {
      case audio.DeviceType.NEARLINK:
        return '星闪 (NearLink)';
      case audio.DeviceType.BLUETOOTH_A2DP:
      case audio.DeviceType.BLUETOOTH_SCO:
        return '蓝牙';
      default:
        return '非无线输出';
    }
  }

  private updateWirelessCodecInference(device: Readonly<audio.AudioDeviceDescriptor>): void {
    const bitrateKbps: number | undefined = this.estimateWirelessBitrateKbps(device);
    if (bitrateKbps === undefined) {
      this.wirelessBitrateText = '--';
    } else {
      this.wirelessBitrateText = `${bitrateKbps} kbps (估算)`;
    }
    this.wirelessCodecText = this.inferCodecByDeviceAndBitrate(device.deviceType, bitrateKbps);
  }

  private isWirelessDevice(deviceType: audio.DeviceType): boolean {
    return deviceType === audio.DeviceType.NEARLINK
      || deviceType === audio.DeviceType.BLUETOOTH_A2DP
      || deviceType === audio.DeviceType.BLUETOOTH_SCO;
  }

  private estimateWirelessBitrateKbps(device: Readonly<audio.AudioDeviceDescriptor>): number | undefined {
    if (!this.isWirelessDevice(device.deviceType)) {
      return undefined;
    }

    const candidates: Array<number> = [];
    if (device.capabilities && device.capabilities.length > 0) {
      for (let index = 0; index < device.capabilities.length; index++) {
        const cap: audio.AudioStreamInfo = device.capabilities[index];
        const sampleRate: number = Number(cap.samplingRate);
        const channelCount: number = Number(cap.channels);
        const bitDepth: number = this.sampleFormatBitDepthValue(cap.sampleFormat);
        if (sampleRate > 0 && channelCount > 0 && bitDepth > 0) {
          candidates.push(Math.round(sampleRate * channelCount * bitDepth / 1000));
        }
      }
    }

    if (candidates.length === 0) {
      const sampleRate: number = this.pickSampleRate(device.sampleRates);
      const channelCount: number = this.pickChannelCount(device.channelCounts);
      if (sampleRate <= 0 || channelCount <= 0) {
        return undefined;
      }
      candidates.push(Math.round(sampleRate * channelCount * 16 / 1000));
    }
    return this.pickMedian(candidates);
  }

  private pickSampleRate(sampleRates: Array<number>): number {
    if (sampleRates.length === 0) {
      return 0;
    }
    if (sampleRates.includes(48000)) {
      return 48000;
    }
    if (sampleRates.includes(44100)) {
      return 44100;
    }
    return sampleRates[0];
  }

  private pickChannelCount(channelCounts: Array<number>): number {
    if (channelCounts.length === 0) {
      return 0;
    }
    if (channelCounts.includes(2)) {
      return 2;
    }
    if (channelCounts.includes(1)) {
      return 1;
    }
    return channelCounts[0];
  }

  private pickMedian(values: Array<number>): number {
    if (values.length === 0) {
      return 0;
    }
    const sorted: Array<number> = values.slice().sort((a: number, b: number) => a - b);
    const middle: number = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 1) {
      return sorted[middle];
    }
    return Math.round((sorted[middle - 1] + sorted[middle]) / 2);
  }

  private inferCodecByDeviceAndBitrate(deviceType: audio.DeviceType, bitrateKbps?: number): string {
    if (deviceType === audio.DeviceType.NEARLINK) {
      return '星闪链路（非蓝牙编解码）';
    }
    if (deviceType !== audio.DeviceType.BLUETOOTH_A2DP && deviceType !== audio.DeviceType.BLUETOOTH_SCO) {
      return 'N/A';
    }
    if (bitrateKbps === undefined || bitrateKbps <= 0) {
      return '码率不可用，无法推断';
    }
    if (bitrateKbps >= 900) {
      return '推断：LDAC 或 L2HC（高码率）';
    }
    if (bitrateKbps >= 450) {
      return '推断：AAC 或 L2HC（中码率）';
    }
    if (bitrateKbps >= 220) {
      return '推断：SBC 或 AAC（基础码率）';
    }
    return '推断：SBC（低码率）';
  }

  private formatNumberArray(values: Array<number>, suffix: string): string {
    if (values.length === 0) {
      return '--';
    }
    let text: string = '';
    for (let index = 0; index < values.length; index++) {
      if (index > 0) {
        text += ', ';
      }
      text += `${values[index]}${suffix}`;
    }
    return text;
  }

  private formatEncodingTypes(types?: Array<audio.AudioEncodingType>): string {
    if (!types || types.length === 0) {
      return '--';
    }
    let text: string = '';
    for (let index = 0; index < types.length; index++) {
      if (index > 0) {
        text += ', ';
      }
      text += this.audioEncodingTypeText(types[index]);
    }
    return text;
  }

  private formatCapabilities(capabilities?: Array<audio.AudioStreamInfo>): string {
    if (!capabilities || capabilities.length === 0) {
      return '--';
    }
    const displayCount: number = capabilities.length > 3 ? 3 : capabilities.length;
    let text: string = '';
    for (let index = 0; index < displayCount; index++) {
      const item: audio.AudioStreamInfo = capabilities[index];
      if (index > 0) {
        text += ' | ';
      }
      text += `${item.samplingRate}Hz/${item.channels}ch/${this.sampleFormatToBitDepth(item.sampleFormat)}/${this.audioEncodingTypeText(item.encodingType)}`;
    }
    return text;
  }

  private sampleFormatToBitDepth(sampleFormat: audio.AudioSampleFormat): string {
    const bits: number = this.sampleFormatBitDepthValue(sampleFormat);
    if (bits > 0) {
      return `${bits}bit`;
    }
    return `未知(${sampleFormat})`;
  }

  private sampleFormatBitDepthValue(sampleFormat: audio.AudioSampleFormat): number {
    switch (sampleFormat) {
      case audio.AudioSampleFormat.SAMPLE_FORMAT_U8:
        return 8;
      case audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE:
        return 16;
      case audio.AudioSampleFormat.SAMPLE_FORMAT_S24LE:
        return 24;
      case audio.AudioSampleFormat.SAMPLE_FORMAT_S32LE:
      case audio.AudioSampleFormat.SAMPLE_FORMAT_F32LE:
        return 32;
      default:
        return 0;
    }
  }

  private audioEncodingTypeText(encodingType: audio.AudioEncodingType): string {
    switch (encodingType) {
      case audio.AudioEncodingType.ENCODING_TYPE_RAW:
        return 'PCM';
      default:
        return `编码(${encodingType})`;
    }
  }

  private profileConnectionStateText(state: constant.ProfileConnectionState): string {
    switch (state) {
      case constant.ProfileConnectionState.STATE_CONNECTED:
        return 'A2DP已连接';
      case constant.ProfileConnectionState.STATE_CONNECTING:
        return 'A2DP连接中';
      case constant.ProfileConnectionState.STATE_DISCONNECTING:
        return 'A2DP断开中';
      case constant.ProfileConnectionState.STATE_DISCONNECTED:
      default:
        return 'A2DP未连接';
    }
  }

  private getNowTime(): string {
    const now: Date = new Date();
    const h: string = now.getHours().toString().padStart(2, '0');
    const m: string = now.getMinutes().toString().padStart(2, '0');
    const s: string = now.getSeconds().toString().padStart(2, '0');
    return `${h}:${m}:${s}`;
  }

  private recordError(prefix: string, err: Object): void {
    const detail: string = `${prefix}: ${JSON.stringify(err)}`;
    this.errorText = detail;
    hilog.error(DOMAIN, TAG, '%{public}s', detail);
  }

  @Builder
  private sectionTitle(title: string): void {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .margin({ bottom: 8 });
  }

  @Builder
  private infoLine(label: string, value: string): void {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'));
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'));
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  @Builder
  private outputDeviceSwitcher(): void {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.outputDeviceTabs, (item: OutputDeviceTabItem) => {
          Text(item.title)
            .fontSize(12)
            .fontColor(item.id === this.selectedOutputDeviceId
              ? $r('app.color.chip_selected_text')
              : $r('app.color.chip_text'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(item.id === this.selectedOutputDeviceId
              ? $r('app.color.chip_selected_background')
              : $r('app.color.chip_background'))
            .borderRadius(16)
            .onClick(() => {
              this.selectOutputDevice(item.id);
            });
        }, (item: OutputDeviceTabItem): string => item.id.toString())
      }
      .alignItems(VerticalAlign.Center)
      .padding({ bottom: 4 });
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%');
  }

  @Builder
  private aboutSheetContent(): void {
    Column({ space: 12 }) {
      Text('AudioInfo - 关于')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start);

      Column({ space: 8 }) {
        this.infoLine('应用简介', 'AudioInfo是一个能在Harmony OS NEXT上读取音频流信息的小工具，支持多种设备信息的读取');
        this.infoLine('版本信息', 'v1.0.0');
        this.infoLine('开源仓库', 'https://github.com/bd7pzx/audioinfo');
        this.infoLine('开源许可', 'GPL V3');
      }
      .padding(12)
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12);
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
    .width('100%');
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row().width('100%').height(this.statusBarHeight)
        Text('AudioInfo')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start);

        Text(`更新时间：${this.lastUpdateTime}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start);

        Column({ space: 10 }) {
          this.sectionTitle('实时音频流状态');
          this.infoLine('活跃渲染流数量', `${this.rendererCount}`);
          this.infoLine('流用途', this.rendererUsageText);
          this.infoLine('说明',
            '系统级实时流采样率/位宽在公开ArkTS API中无直接读取接口，已展示当前输出设备能力作为实时参考。');
        }
        .padding(12)
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12);

        Column({ space: 10 }) {
          this.sectionTitle('当前音频输出设备');
          if (this.outputDeviceTabs.length > 1) {
            this.outputDeviceSwitcher();
          }
          this.infoLine('设备数量', `${this.outputDeviceTabs.length}`);
          this.infoLine('设备名', this.currentDeviceName);
          this.infoLine('设备类型', this.currentDeviceType);
          this.infoLine('支持采样率', this.deviceSampleRateText);
          this.infoLine('支持声道', this.deviceChannelText);
          this.infoLine('编码类型', this.deviceEncodingText);
          this.infoLine('能力样例(采样率/声道/位宽/编码)', this.capabilityText);
          if (this.selectedDeviceIsWireless) {
            this.infoLine('无线协议', this.wirelessProtocolText);
            this.infoLine('无线传输码率(估算)', this.wirelessBitrateText);
            this.infoLine('编码器推断', this.wirelessCodecText);
            if (this.selectedDeviceIsBluetooth) {
              this.infoLine('蓝牙A2DP状态', this.btConnectionText);
            }
          }
        }
        .padding(12)
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12);

        Button('关于')
          .fontSize(14)
          .width('100%')
          .onClick(() => {
            this.isAboutSheetVisible = true;
          });
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 24, bottom: 24 })
      .width('100%');
    }
    .backgroundColor($r('app.color.page_background'))
    .height('100%')
    .width('100%')
    .expandSafeArea([0], [0])
    .bindSheet(this.isAboutSheetVisible, this.aboutSheetContent(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      onDisappear: () => {
        this.isAboutSheetVisible = false;
      }
    });
  }
}
