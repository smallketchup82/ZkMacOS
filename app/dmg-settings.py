"""Headless DMG layout, matching the interactive create-dmg installer."""
from pathlib import Path

root = Path(defines['root'])
application = root / 'dist/Zero-K.app'
format = 'UDZO'
files = [str(application)]
symlinks = {'Applications': '/Applications'}
icon = str(application / 'Contents/Resources/Zero-K.icns')
background = str(root / 'build/dmg-background.tiff')
window_rect = ((200, 160), (640, 382))
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
icon_locations = {'Zero-K.app': (160, 180), 'Applications': (480, 180)}
icon_size = 112
text_size = 14
