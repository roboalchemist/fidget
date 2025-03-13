from setuptools import setup
import PyQt6

APP = ['fidget.py']
DATA_FILES = [
    ('', ['fidget.png']),
]

OPTIONS = {
    'argv_emulation': False,
    'iconfile': '/Users/joseph.schlesinger/ptools/fidget/fidget.icns',
    'plist': {
        'LSUIElement': True,  # This makes it a menu bar app without a dock icon
        'CFBundleName': 'Fidget',
        'CFBundleDisplayName': 'Fidget',
        'CFBundleIdentifier': 'com.yourname.fidget',
        'CFBundleVersion': '1.0.0',
        'CFBundleShortVersionString': '1.0.0',
        'NSHumanReadableCopyright': '© 2025',
    },
    'packages': ['PyQt6'],
    'includes': [
        'PyQt6',
        'PyQt6.QtCore',
        'PyQt6.QtGui',
        'PyQt6.QtWidgets',
    ],
    'frameworks': [],
    'excludes': ['matplotlib', 'numpy', 'pandas', 'scipy', 'tkinter', 'PIL'],
    'qt_plugins': ['platforms'],
    'resources': [],
}

setup(
    app=APP,
    name='Fidget',
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
