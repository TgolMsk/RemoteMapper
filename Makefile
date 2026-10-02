APP := build/DerivedData/Build/Products/Debug/RemoteMapper.app
RELEASE_APP := build/DerivedData/Build/Products/Release/RemoteMapper.app
XCODEBUILD := xcodebuild -project RemoteMapper.xcodeproj -scheme RemoteMapper -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData

.PHONY: project build run test snapshot icon probe dotcall release install dist clean

project:            ## 由 project.yml 生成 Xcode 工程
	xcodegen generate

build: mic-build project      ## 编译 Debug 版
	$(XCODEBUILD) -configuration Debug build -quiet

run: build          ## 编译并启动（会先退出正在运行的实例）
	@pkill -x RemoteMapper || true
	open $(APP)

test:               ## 运行核心库单元测试
	cd Packages/RemoteKit && swift test

snapshot: build     ## 渲染所有界面截图到 build/snapshots（深色/浅色）
	rm -rf build/snapshots
	$(APP)/Contents/MacOS/RemoteMapper --snapshot $(CURDIR)/build/snapshots
	@echo "截图已输出到 build/snapshots"

icon:               ## 重新绘制 App 图标
	swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

probe:              ## 运行原始 HID 探针，打印遥控器的原始报告
	swift Tools/RemoteProbe.swift

dotcall:            ## 编译 ChatGPT dot 通话命令行工具到 build/dotcall（排查按钮标签：build/dotcall dump）
	@mkdir -p build
	swiftc -O Tools/dotcall.swift -o build/dotcall

release: mic-build project    ## 编译 Release 版
	$(XCODEBUILD) -configuration Release build -quiet

install: release    ## 安装到 /Applications（开机启动需要从这里运行）
	@pkill -x RemoteMapper || true
	rm -rf /Applications/RemoteMapper.app
	cp -R $(RELEASE_APP) /Applications/
	open /Applications/RemoteMapper.app

dist:               ## 正式发布：Developer ID 签名、公证并打包 DMG
	scripts/release-direct.sh

clean:
	rm -rf build

.PHONY: mic-build mic-install mic-uninstall
mic-build:          ## 构建并验证独立遥控器音频组件（需要 Opus）
	scripts/build-microphone.sh

mic-install: mic-build ## 安装系统音频输入与按需采集服务（需要管理员权限）
	sudo /bin/bash build/Microphone/install.sh

mic-uninstall:      ## 移除系统音频组件并恢复蓝牙调试设置
	sudo /bin/bash "/Library/Application Support/RemoteMapperMicrophone/uninstall.sh"
