"""Check required install metadata on real Xcode products before packaging."""
import pathlib
import plistlib
import sys


def validate(app):
    bundles = [app, *sorted((app / 'PlugIns').glob('*.appex'))]
    if len(bundles) < 2:
        raise ValueError('Widget extension is missing')
    for bundle in bundles:
        with (bundle / 'Info.plist').open('rb') as handle:
            info = plistlib.load(handle)
        for key in ('CFBundleName', 'CFBundleIdentifier', 'CFBundleExecutable',
                    'CFBundleVersion', 'CFBundleShortVersionString'):
            value = info.get(key)
            if not isinstance(value, str) or not value.strip() or '$(' in value:
                raise ValueError(f'{bundle.name}: invalid or missing {key}')
        if not (bundle / info['CFBundleExecutable']).is_file():
            raise ValueError(f'{bundle.name}: executable missing')
    print(f'Install metadata validated for {len(bundles)} bundles')


if __name__ == '__main__':
    validate(pathlib.Path(sys.argv[1]))
