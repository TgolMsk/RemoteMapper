// RemoteMapper 的按需采集服务。只有 CoreAudio 输入正在使用时才捕获蓝牙音频。
// 原始蓝牙记录存放于仅 root 可读的目录；停用时删除，并恢复原来的 HCITraces 设置。
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include <dispatch/dispatch.h>
#include <spawn.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
static NSString *const support = @"/Library/Application Support/RemoteMapperMicrophone";
static NSString *const debugPath = @"/Library/Preferences/com.apple.MobileBluetooth.debug.plist";
static const char *loggerPath = "/Applications/PacketLogger.app/Contents/Resources/packetlogger";
static pid_t loggerPID = -1, routerPID = -1;
static BOOL tracing = NO;
static int idleTicks = 0, startTicks = 0, retryTicks = 0;

static NSString *capturePath(void) { return [support stringByAppendingPathComponent:@"Capture/current.pklg"]; }
static NSString *backupPath(void) { return [support stringByAppendingPathComponent:@"hci-before.plist"]; }

static BOOL writePlist(NSDictionary *dict, NSString *path)
{
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"无法写入 %@: %@", path, error); return NO;
    }
    chmod(path.fileSystemRepresentation, 0644);
    return YES;
}

// 保存一个键的原值，恢复时保留其他工具后来修改的键。
static BOOL saveTraces(void)
{
    NSDictionary *current = [NSDictionary dictionaryWithContentsOfFile:debugPath] ?: @{};
    NSMutableDictionary *backup = [@{@"domainExisted": @([[NSFileManager defaultManager] fileExistsAtPath:debugPath])} mutableCopy];
    if (current[@"HCITraces"]) backup[@"HCITraces"] = current[@"HCITraces"];
    return writePlist(backup, backupPath());
}

static pid_t spawn(const char *path, char *const argv[])
{
    pid_t pid = -1;
    int rc = posix_spawn(&pid, path, NULL, NULL, argv, environ);
    if (rc) { NSLog(@"启动失败 %s: %s", path, strerror(rc)); return -1; }
    return pid;
}

static void reloadBluetooth(void)
{
    char *args[] = {"killall", "-USR1", "bluetoothd", NULL};
    pid_t pid = spawn("/usr/bin/killall", args);
    if (pid > 0) waitpid(pid, NULL, 0);
}

static BOOL enableTraces(void)
{
    NSMutableDictionary *current = [[NSDictionary dictionaryWithContentsOfFile:debugPath] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *traces = [current[@"HCITraces"] isKindOfClass:NSDictionary.class] ? [current[@"HCITraces"] mutableCopy] : [NSMutableDictionary new];
    for (NSString *key in @[@"StackDebugEnabled", @"HCILiveTraces", @"RawAudioTrace", @"HIDTrace", @"HCISkipAuth"]) traces[key] = @YES;
    // 不启用后台磁盘记录。只有本服务的临时文件接收实时数据。
    traces[@"HCIFileTraces"] = @NO;
    current[@"HCITraces"] = traces;
    if (!writePlist(current, debugPath)) return NO;
    reloadBluetooth(); tracing = YES; return YES;
}

static BOOL restoreTraces(void)
{
    NSDictionary *backup = [NSDictionary dictionaryWithContentsOfFile:backupPath()];
    if (!backup) { NSLog(@"缺少蓝牙设置备份，拒绝覆盖"); return NO; }
    NSMutableDictionary *current = [[NSDictionary dictionaryWithContentsOfFile:debugPath] mutableCopy] ?: [NSMutableDictionary new];
    if (backup[@"HCITraces"]) current[@"HCITraces"] = backup[@"HCITraces"];
    else [current removeObjectForKey:@"HCITraces"];
    if (!current.count && ![backup[@"domainExisted"] boolValue]) {
        [[NSFileManager defaultManager] removeItemAtPath:debugPath error:NULL];
    } else if (!writePlist(current, debugPath)) return NO;
    reloadBluetooth(); tracing = NO; return YES;
}

static BOOL microphoneInUse(void)
{
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr || !size) return NO;
    AudioDeviceID *ids = malloc(size);
    if (!ids) return NO;
    BOOL active = NO;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids) == noErr) {
        for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); ++i) {
            AudioObjectPropertyAddress uidAddress = {kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            CFStringRef uid = NULL; UInt32 uidSize = sizeof(uid);
            if (AudioObjectGetPropertyData(ids[i], &uidAddress, 0, NULL, &uidSize, &uid) != noErr || !uid) continue;
            BOOL matches = CFEqual(uid, CFSTR("RemoteMapperMic_UID"));
            CFRelease(uid);
            if (!matches) continue;
            AudioObjectPropertyAddress running = {kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            UInt32 value = 0, valueSize = sizeof(value);
            active = AudioObjectGetPropertyData(ids[i], &running, 0, NULL, &valueSize, &value) == noErr && value != 0;
            break;
        }
    }
    free(ids); return active;
}

static void stopPipeline(void)
{
    if (routerPID > 0) kill(routerPID, SIGKILL);
    if (loggerPID > 0) kill(loggerPID, SIGKILL);
    routerPID = loggerPID = -1; startTicks = 0;
    [[NSFileManager defaultManager] removeItemAtPath:capturePath() error:NULL];
    if (tracing) restoreTraces();
    NSLog(@"采集已停止");
}

static void startPipeline(void)
{
    if (access(loggerPath, X_OK) != 0) { NSLog(@"缺少 PacketLogger"); retryTicks = 40; return; }
    // 每次采集前记录原值；即使其它蓝牙调试工具改过设置，也能恢复。
    if (!saveTraces() || !enableTraces()) { retryTicks = 40; return; }
    [[NSFileManager defaultManager] removeItemAtPath:capturePath() error:NULL];
    char *args[] = {"packetlogger", "convert", "-o", (char *)capturePath().fileSystemRepresentation, NULL};
    loggerPID = spawn(loggerPath, args);
    if (loggerPID <= 0) { stopPipeline(); retryTicks = 40; }
    else NSLog(@"输入设备正在使用，开始采集");
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        if (geteuid() != 0) { fprintf(stderr, "此服务需要管理员权限\n"); return 1; }
        if (argc == 2 && strcmp(argv[1], "--save-traces") == 0) return saveTraces() ? 0 : 1;
        if (argc == 2 && strcmp(argv[1], "--restore-traces") == 0) return restoreTraces() ? 0 : 1;
        if (argc != 1) return 2;
        umask(0077);
        // 崩溃后的恢复：先恢复未完成会话的设置，随后只在需求出现时重新启用。
        if ([[NSFileManager defaultManager] fileExistsAtPath:backupPath()]) restoreTraces();
        [[NSFileManager defaultManager] createDirectoryAtPath:[support stringByAppendingPathComponent:@"Capture"] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:NULL];
        signal(SIGPIPE, SIG_IGN);
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN);
        dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(term, ^{ stopPipeline(); exit(0); }); dispatch_resume(term);
        dispatch_source_t interrupt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(interrupt, ^{ stopPipeline(); exit(0); }); dispatch_resume(interrupt);
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC, 25 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            @autoreleasepool {
                int status = 0;
                if ((loggerPID > 0 && waitpid(loggerPID, &status, WNOHANG) == loggerPID) ||
                    (routerPID > 0 && waitpid(routerPID, &status, WNOHANG) == routerPID)) {
                    stopPipeline(); retryTicks = 8;
                }
                while (waitpid(-1, NULL, WNOHANG) > 0) {}
                if (!microphoneInUse()) {
                    if (++idleTicks >= 12 && loggerPID > 0) stopPipeline();
                    return;
                }
                idleTicks = 0;
                if (retryTicks > 0) { retryTicks--; return; }
                if (loggerPID <= 0) startPipeline();
                if (loggerPID > 0 && routerPID <= 0) {
                    struct stat info;
                    if (stat(capturePath().fileSystemRepresentation, &info) == 0 && info.st_size > 0) {
                        NSString *router = [support stringByAppendingPathComponent:@"srm_router"];
                        char *args[] = {"srm_router", "--pklg", (char *)capturePath().fileSystemRepresentation, NULL};
                        routerPID = spawn(router.fileSystemRepresentation, args);
                        if (routerPID <= 0) { stopPipeline(); retryTicks = 8; }
                    } else if (++startTicks > 80) { NSLog(@"蓝牙采集超时"); stopPipeline(); retryTicks = 40; }
                }
                struct stat info;
                if (loggerPID > 0 && stat(capturePath().fileSystemRepresentation, &info) == 0 && info.st_size > 32 * 1024 * 1024) {
                    // 限制临时蓝牙记录的大小，下一轮需求检测自动重建采集。
                    stopPipeline();
                }
            }
        });
        dispatch_resume(timer);
        NSLog(@"遥控器麦克风服务已就绪");
        dispatch_main();
    }
}
