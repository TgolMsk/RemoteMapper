# 音频组件来源

该独立音频组件包含 GPL-3.0 的 SiriRemoteForge / HyperVibe 音频驱动、协议解码与测试代码。
上游：https://github.com/HOLODATA-COM/SiriRemoteForge
固定提交：4c65969c71c5f3c81cfa55b5ec3b9efb5658be32

HAL 驱动基于 Existential Audio 的 BlackHole；原版权声明保留于源文件中，完整许可见
`COPYING` 与 `BlackHole-LICENSE.txt`。静态链接的 libopus 使用 BSD 许可，见 `Opus-LICENSE.txt`。
该目录的衍生组件按 GPL-3.0 提供；发布其二进制时须一并提供对应源码和构建脚本。

RemoteMapper 修改（2026-09-30）：独立产品标识与共享内存；仅遥控器音源；新增按
CoreAudio 需求采集、临时记录访问限制、蓝牙设置恢复、安装回滚及卸载流程。
应用通过标准 CoreAudio 设备接口使用这个单独安装的组件。

实机验证：PID 0x0315 的遥控器在本机发送 ATT 0x0036 语音帧；标准 CoreAudio 输入
录制了非静音音频，松键后返回静音。输入设备停止使用约三秒后，采集子进程退出，
原来不存在的 HCITraces 键恢复为不存在。这只是本机与当前固件的验证结果。
