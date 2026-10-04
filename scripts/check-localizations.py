#!/usr/bin/env python3
"""检查界面/预设文案、各语言键集合和格式参数一致性。"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ['en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'fr', 'de', 'es', 'pt-BR', 'it', 'ru', 'ar']
STRING = r'"(?:\\.|[^"\\])*"'
PAIR = re.compile(r'('+STRING+r')\s*=\s*('+STRING+r')\s*;')

def decode(value):
    return json.loads(value)

def source_keys():
    keys = set()
    for base in [ROOT / 'App/Sources', ROOT / 'Packages/RemoteKit/Sources/RemoteKit']:
        for path in base.rglob('*.swift'):
            source = path.read_text()
            for match in re.finditer(r'L10n\.(?:text|format)\(\s*('+STRING+r')', source):
                keys.add(decode(match.group(1)))
            for match in re.finditer(r'Failure\(key:\s*('+STRING+r')', source):
                keys.add(decode(match.group(1)))
    source = (ROOT / 'Packages/RemoteKit/Sources/RemoteKit/Presets.swift').read_text()
    for match in re.finditer(r'(?:title|detail):\s*('+STRING+r')', source):
        keys.add(decode(match.group(1)))
    keys.update(['全局', '终端', '演示', '鼠标模式', '确认', '返回', '确定', '转文字后发送', '转为文字', '右⌘', '右⌥', '右⌃', '右⇧'])
    # Installer output is read by the app. Keep the shell's stable original keys.
    source = (ROOT / 'AudioBridge/install.sh').read_text()
    for match in re.finditer(r'echo "([^"\n]*[\u3400-\u9fff][^"\n]*)" >&2', source):
        keys.add(match.group(1))
    return sorted(keys)

def read_table(path):
    pairs = [(decode(m[1]), decode(m[2])) for m in PAIR.finditer(path.read_text())]
    if len(pairs) != len(dict(pairs)):
        raise ValueError(f'Duplicate keys: {path}')
    return dict(pairs)

def placeholders(value):
    # Ignore escaped % signs, allow positional arguments for translated ordering.
    return sorted(re.findall(r'%(?:\d+\$)?([-+0 #]*(?:\d+)?(?:\.\d+)?(?:hh|ll|[hlLjzt])?[@diufFeEgGxXosc])', value.replace('%%', '')))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--export', type=Path)
    args = parser.parse_args()
    expected = set(source_keys())
    if args.export:
        args.export.write_text(json.dumps(sorted(expected), ensure_ascii=False, indent=2)+'\n')
        print(f'Exported {len(expected)} keys to {args.export}')
        return
    failures = []
    privacy_keys = {'NSAppleEventsUsageDescription', 'NSBluetoothAlwaysUsageDescription', 'NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription'}
    for locale in LOCALES:
        path = ROOT / f'Packages/RemoteKit/Sources/RemoteKit/Resources/{locale}.lproj/Localizable.strings'
        if not path.exists():
            failures.append(f'{locale}: missing resource'); continue
        table = read_table(path)
        for key in expected - table.keys():
            failures.append(f'{locale}: missing {key}')
        for key in table.keys() - expected:
            failures.append(f'{locale}: unused {key}')
        for key, value in table.items():
            if not value.strip(): failures.append(f'{locale}: empty {key}')
            if placeholders(key) != placeholders(value): failures.append(f'{locale}: parameters differ for {key}')
            if key.count('%%') != value.count('%%'): failures.append(f'{locale}: escaped percent signs differ for {key}')
        privacy = ROOT / f'App/Resources/{locale}.lproj/InfoPlist.strings'
        if not privacy.exists() or read_table(privacy).keys() != privacy_keys:
            failures.append(f'{locale}: incomplete privacy descriptions')
    if failures:
        print('\n'.join(failures)); raise SystemExit(1)
    print(f'Validated {len(expected)} source keys and privacy descriptions across {len(LOCALES)} languages.')

if __name__ == '__main__': main()
