APP := build/DerivedData/Build/Products/Debug/RemoteMapper.app
LITE_APP := "build/DerivedData/Build/Products/Debug/RemoteMapper Lite.app"
RELEASE_APP := build/DerivedData/Build/Products/Release/RemoteMapper.app
XCODEBUILD := xcodebuild -project RemoteMapper.xcodeproj -scheme RemoteMapper -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData

.PHONY: project build build-lite run run-lite test snapshot snapshot-lite icon probe release install dist appstore clean

project:            ## 由 project.yml 生成 Xcode 工程
	xcodegen generate

build: project      ## 编译 Debug 版
	$(XCODEBUILD) -configuration Debug build -quiet

build-lite: project ## 编译 App Store 版（沙盒）
	$(subst -scheme RemoteMapper,-scheme RemoteMapperLite,$(XCODEBUILD)) -configuration Debug build -quiet

run: build          ## 编译并启动官网版（会先退出 App Store 版，避免两个版本同时响应遥控器）
	@pkill -x RemoteMapper || true
	@pkill -x "RemoteMapper Lite" || true
	open $(APP)

run-lite: build-lite ## 编译并启动 App Store 版
	@pkill -x RemoteMapper || true
	@pkill -x "RemoteMapper Lite" || true
	open $(LITE_APP)

test:               ## 运行核心库单元测试
	cd Packages/RemoteKit && swift test

snapshot: build     ## 渲染所有界面截图到 build/snapshots（深色/浅色）
	rm -rf build/snapshots
	$(APP)/Contents/MacOS/RemoteMapper --snapshot $(CURDIR)/build/snapshots
	@echo "截图已输出到 build/snapshots"

snapshot-lite: build-lite ## 渲染 App Store 版界面截图到 build/snapshots-lite（沙盒内渲染后复制出来）
	rm -rf build/snapshots-lite
	@dir=$$($(LITE_APP)/Contents/MacOS/"RemoteMapper Lite" --snapshot - | sed -n 's/^SNAPSHOT_DIR=//p'); \
		ditto "$$dir" build/snapshots-lite && echo "截图已输出到 build/snapshots-lite"

icon:               ## 重新绘制 App 图标
	swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

probe:              ## 运行原始 HID 探针，打印遥控器的原始报告
	swift Tools/RemoteProbe.swift

release: project    ## 编译 Release 版
	$(XCODEBUILD) -configuration Release build -quiet

install: release    ## 安装到 /Applications（开机启动需要从这里运行）
	@pkill -x RemoteMapper || true
	rm -rf /Applications/RemoteMapper.app
	cp -R $(RELEASE_APP) /Applications/
	open /Applications/RemoteMapper.app

dist:               ## 官网版：Developer ID 签名、公证并打包 DMG
	scripts/release-direct.sh

appstore:           ## App Store 版：归档并导出上传用安装包
	scripts/release-appstore.sh

clean:
	rm -rf build
