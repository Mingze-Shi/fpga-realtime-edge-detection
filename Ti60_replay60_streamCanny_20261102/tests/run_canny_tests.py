"""Generate independent integer/BFS references, then run RTL simulations."""
from collections import deque
from pathlib import Path
import os
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'test_output'


def frontend(image, high):
    h, w = len(image), len(image[0])
    gaussian = [[0] * w for _ in range(h)]
    gradient = [[(0, 0)] * w for _ in range(h)]
    result = [[0] * w for _ in range(h)]
    kernel = ((1, 2, 1), (2, 4, 2), (1, 2, 1))
    for y in range(2, h):
        for x in range(2, w):
            gaussian[y][x] = (8 + sum(image[y-2+j][x-2+i] * kernel[j][i]
                                                  for j in range(3) for i in range(3))) // 16
    for y in range(4, h):
        for x in range(4, w):
            a, b, c = (gaussian[y-2+j][x-2:x+1] for j in range(3))
            dx = a[2] + 2*b[2] + c[2] - a[0] - 2*b[0] - c[0]
            dy = c[0] + 2*c[1] + c[2] - a[0] - 2*a[1] - a[2]
            ax, ay = abs(dx), abs(dy)
            direction = 0 if ay*256 <= ax*106 else 2 if ax*256 <= ay*106 else 1 if dx*dy >= 0 else 3
            gradient[y][x] = (dx*dx + dy*dy, direction)
    offsets = ((-1, 0), (-1, -1), (0, -1), (1, -1))
    for y in range(6, h):
        for x in range(6, w):
            cx, cy = x-1, y-1
            mag, direction = gradient[cy][cx]
            ox, oy = offsets[direction]
            before = gradient[cy+oy][cx+ox][0]
            after = gradient[cy-oy][cx-ox][0]
            if mag > 0 and mag > before and mag >= after:
                result[y][x] = 2 if mag >= high*high else 1 if mag >= (high//2)**2 else 0
    return result


def connected(classes):
    h, w = len(classes), len(classes[0])
    seen = [[0]*w for _ in range(h)]
    queue = deque()
    for y in range(h):
        for x in range(w):
            if classes[y][x] == 2:
                seen[y][x] = 1
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nx, ny = x+dx, y+dy
                if 0 <= nx < w and 0 <= ny < h and classes[ny][nx] and not seen[ny][nx]:
                    seen[ny][nx] = 1
                    queue.append((nx, ny))
    return seen


def write_hex(name, values):
    (OUT / name).write_text(''.join(f'{v:x}\n' for v in values), encoding='ascii')


def fixtures():
    OUT.mkdir(exist_ok=True)
    rng = random.Random(431)
    w, h = 24, 18
    images = [
        [[90]*w for _ in range(h)],
        [[0 if x < 12 else 255 for x in range(w)] for y in range(h)],
        [[0 if y < 9 else 255 for x in range(w)] for y in range(h)],
        [[0 if x < y else 255 for x in range(w)] for y in range(h)],
        [[0 if x+y < 22 else 255 for x in range(w)] for y in range(h)],
        [[rng.randrange(256) for x in range(w)] for y in range(h)],
        [[min(255, x*7+y*2) for x in range(w)] for y in range(h)],
        [[0 if x < 12 else 255 for x in range(w)] for y in range(h)],
    ]
    thresholds = [32, 144, 144, 144, 144, 200, 32, 2032]
    write_hex('canny_pixels.hex', (v for image in images for row in image for v in row))
    results = [frontend(image, t) for image, t in zip(images, thresholds)]
    write_hex('canny_classes.hex', (v for image in results for row in image for v in row))
    write_hex('canny_thresholds.hex', thresholds)
    assert any(v == 2 for image in results for row in image for v in row)
    assert any(v == 1 for image in results for row in image for v in row)
    integration_classes = frontend([[0 if x < 15 else 255 for x in range(24)] for y in range(18)], 32)
    canonical = [[0]*24 for _ in range(18)]
    for y in range(18):
        for x in range(24):
            canonical[(y-3) % 18][(x-3) % 24] = integration_classes[y][x]
    write_hex('canny_video_expected.hex', (v for row in connected(canonical) for v in row))
    full = [[0 if x < 30 else 255 for x in range(48)] for _ in range(36)]
    median = [row[:] for row in full]
    for y in range(2, 36):
        for x in range(2, 48):
            median[y][x] = sorted(full[y-2+j][x-2+i] for j in range(3) for i in range(3))[4]
    reduced = [[median[2*y][2*x] for x in range(24)] for y in range(18)]
    integration_classes = frontend(reduced, 32)
    for y in range(18):
        for x in range(24):
            canonical[(y-3) % 18][(x-3) % 24] = integration_classes[y][x]
    write_hex('canny_video_median_expected.hex', (v for row in connected(canonical) for v in row))
    overlay_maps = []
    for tag in range(2):
        image = []
        for y in range(18):
            row = []
            for x in range(24):
                inside = (30 if tag else 20) <= 2*x < 44 and 8 <= 2*y < 28
                r, g, b = (180+tag, 170+2*tag, 160+3*tag) if inside else (20+tag, 30+2*tag, 40+3*tag)
                row.append((77*r+150*g+29*b+128)//256)
            image.append(row)
        raw = frontend(image, 32)
        canonical = [[0]*24 for _ in range(18)]
        for y in range(18):
            for x in range(24):
                canonical[(y-3) % 18][(x-3) % 24] = raw[y][x]
        overlay_maps.append(connected(canonical))
    write_hex('canny_overlay_expected.hex', (v for image in overlay_maps for row in image for v in row))
    w, h = 16, 12
    maps = [[[0]*w for _ in range(h)], [[1]*w for _ in range(h)]]
    snake = [[0]*w for _ in range(h)]
    for y in range(1, 10, 2):
        for x in range(1, 12):
            snake[y][x] = 1
        if y < 9:
            snake[y+1][11 if y % 4 == 1 else 1] = 1
    snake[9][11] = 2
    snake[1][14] = 1  # isolated weak island
    maps.append(snake)
    diagonal = [[int(x == y) for x in range(w)] for y in range(h)]
    diagonal[10][10] = 2
    maps.append(diagonal)
    maps += [[[rng.choices((0, 1, 2), (6, 8, 1))[0] for x in range(w)] for y in range(h)] for _ in range(2)]
    maps.append([[0]*w for _ in range(h)])  # no previous-frame leakage
    write_hex('hysteresis_source.hex', (v for image in maps for row in image for v in row))
    write_hex('hysteresis_expected.hex', (v for image in maps for row in connected(image) for v in row))
    return images, thresholds


def simulator():
    configured = os.environ.get('IVERILOG_BIN')
    if configured:
        base = Path(configured)
    elif shutil.which('iverilog'):
        base = Path(shutil.which('iverilog')).parent
    else:
        base = ROOT / 'tools/iverilog-portable/Library/bin'
    compiler = base / 'iverilog.exe'
    runtime = base / 'vvp.exe'
    if not compiler.exists() or not runtime.exists():
        raise SystemExit('Set IVERILOG_BIN to the directory containing iverilog.exe and vvp.exe')
    return compiler, runtime


def main():
    os.chdir(ROOT)
    fixtures()
    full_image = [[200 if 481 <= 3*x < 1441 and 181 <= (9*y+3)//4 < 901 else 20
                   for x in range(640)] for y in range(480)]
    raw_classes = frontend(full_image, 144)
    canonical = [[0]*640 for _ in range(480)]
    for y in range(480):
        for x in range(640):
            canonical[(y-3) % 480][(x-3) % 640] = raw_classes[y][x]
    write_hex('canny_640x480_expected.hex', (v for row in connected(canonical) for v in row))
    temporary = OUT / 'tmp'
    temporary.mkdir(exist_ok=True)
    os.environ['TMPDIR'] = os.environ['TMP'] = os.environ['TEMP'] = str(temporary)
    compiler, runtime = simulator()
    local_library = compiler.parent.parent
    os.environ['PATH'] = os.pathsep.join((str(compiler.parent), str(local_library/'mingw-w64/bin'), os.environ['PATH']))
    sources = [str(p.relative_to(ROOT)) for p in sorted((ROOT/'rtl').glob('canny_*.v'))]
    sources += ['rtl/frame_write_commit.v', 'rtl/frame_buffer_V4/bank_switch.v']
    tests = [('canny_frontend_tb', []), ('canny_hysteresis_tb', []), ('canny_video_tb', []),
             ('canny_video_tb', ['-Pcanny_video_tb.MEDIAN=1']), ('canny_resolution_tb', []),
             ('frame_write_commit_tb', []), ('bank_replay_tb', []), ('canny_overlay_tb', [])]
    for name, options in tests:
        label = name + ('_median' if options else '')
        target = OUT / (label + '.vvp')
        extra = ['rtl/median3x3.v', 'rtl/sobel_stream.v', 'rtl/threshold_keys.v',
                 'rtl/mode_key.v', 'rtl/sc431_sobel_video.v'] if name in ('canny_video_tb', 'canny_overlay_tb') else []
        subprocess.run([str(compiler), '-g2012', '-Wall', *options, '-s', name, '-o', str(target),
                        *sources, *extra, f'tests/{name}.v'], check=True)
        result = subprocess.run([str(runtime), str(target)], text=True, capture_output=True)
        (OUT / (label + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        print(result.stdout, end='')
        if result.returncode:
            print(result.stderr)
            raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
