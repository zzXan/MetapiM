"""Render the upstream Metapi SVG into the generated iOS app icon set."""
import io
import json
from pathlib import Path
import cairosvg
from PIL import Image

root = Path(__file__).resolve().parent.parent
folder = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
manifest = json.loads((folder / 'Contents.json').read_text())
source = cairosvg.svg2png(url=str(root / 'assets/branding/metapi-logo.svg'),
                         output_width=1024, output_height=1024,
                         background_color='#101828')
image = Image.open(io.BytesIO(source)).convert('RGB')
for entry in manifest['images']:
    if 'size' not in entry:
        raise ValueError('Unexpected icon manifest without size')
    width, height = map(float, entry['size'].split('x'))
    scale = float(entry.get('scale', '1x').removesuffix('x'))
    dimensions = (round(width * scale), round(height * scale))
    name = f'metapi-{dimensions[0]}x{dimensions[1]}.png'
    image.resize(dimensions, Image.Resampling.LANCZOS).save(folder / name)
    entry['filename'] = name
(folder / 'Contents.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Configured Metapi logo for all iOS icon slots')
