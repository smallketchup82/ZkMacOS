"""Copy and relocate a Mach-O dependency closure, keeping ARM and Intel separate."""
from pathlib import Path
import os
import re
import shutil
import subprocess


def command(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def macho(path):
    return path.is_file() and path.read_bytes()[:4] in (
        b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
    )


def dependencies(path):
    return re.findall(r'^\s+(.+?) \(compatibility version', command('otool', '-L', path), re.M)


def rpaths(path):
    return re.findall(r'cmd LC_RPATH\n.*?path (.+?) \(offset', command('otool', '-l', path), re.S)


def bundle(roots, destination, architecture):
    """roots contains (source, destination) pairs; discovered libraries share destination."""
    destination.mkdir(parents=True, exist_ok=True)
    locations = {Path(source).resolve(): Path(target) for source, target in roots}
    pending = list(roots)
    copied = {}

    def expand(value, source):
        return value.replace('@loader_path', str(source.parent))

    def resolve(name, source):
        choices = [Path(expand(name, source))]
        if name.startswith('@rpath/'):
            choices = [Path(expand(base, source)) / name[7:] for base in rpaths(source)]
        choices += [source.parent / Path(name).name, Path('/opt/homebrew/lib') / Path(name).name]
        for choice in choices:
            if choice.is_file():
                return choice.resolve()
        raise RuntimeError(f'Unresolved dependency {name} of {source}')

    while pending:
        original, target = map(Path, pending.pop(0))
        original = original.resolve()
        if target in copied:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        target.chmod(0o755)
        arches = command('lipo', '-archs', target).split()
        if architecture not in arches:
            raise RuntimeError(f'{original} has {arches}, needs {architecture}')
        if len(arches) > 1:
            temporary = target.with_suffix(target.suffix + '.thin')
            subprocess.run(['lipo', str(target), '-thin', architecture, '-output', str(temporary)], check=True)
            temporary.replace(target)
        own_id = command('otool', '-D', original).splitlines()[1:]
        for dependency in dependencies(original):
            if dependency in own_id or dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            source = resolve(dependency, original)
            if source not in locations:
                next_target = destination / source.name
                if next_target in locations.values():
                    raise RuntimeError(f'Library name collision: {source}')
                locations[source] = next_target
                pending.append((source, next_target))
            relative = os.path.relpath(locations[source], target.parent)
            subprocess.run(['install_name_tool', '-change', dependency, '@loader_path/' + relative, str(target)], check=True)
        if own_id:
            subprocess.run(['install_name_tool', '-id', '@rpath/' + target.name, str(target)], check=True)
        for path in set(rpaths(target)):
            subprocess.run(['install_name_tool', '-delete_rpath', path, str(target)], check=True)
        for path in dict.fromkeys(('@loader_path', '@loader_path/' + os.path.relpath(destination, target.parent))):
            subprocess.run(['install_name_tool', '-add_rpath', path, str(target)], check=True)
        subprocess.run(['strip', '-S', str(target)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(target)], check=True, capture_output=True)
        copied[target] = original
    return copied
