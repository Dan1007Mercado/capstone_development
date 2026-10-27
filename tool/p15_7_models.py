"""Offline geometry hypothesis comparisons; never supplies scanner offsets."""
import json
import math
from html import escape
from pathlib import Path

ROOT = Path('docs/development/evidence/p15_7')


def solve(a, b):
    n = len(b)
    m = [list(row) + [value] for row, value in zip(a, b)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(m[row][col]))
        m[col], m[pivot] = m[pivot], m[col]
        if abs(m[col][col]) < 1e-12:
            raise ValueError('rank deficient landmark model')
        scale = m[col][col]
        m[col] = [v / scale for v in m[col]]
        for row in range(n):
            if row != col:
                scale = m[row][col]
                m[row] = [v-scale*w for v, w in zip(m[row], m[col])]
    return [row[-1] for row in m]


def least_squares(a, b):
    n = len(a[0])
    return solve([[sum(row[i]*row[j] for row in a) for j in range(n)] for i in range(n)],
                 [sum(row[i]*v for row, v in zip(a, b)) for i in range(n)])


def features(point, model):
    x, y = point[0]/1000, point[1]/1000
    if model == 'translation':
        return [1]
    if model == 'affine':
        return [1, x, y]
    if model == 'quadratic':
        return [1, x, y, x*x, x*y, y*y]
    raise ValueError(model)


def fit(points, model):
    a = [features(p['expected'], model) for p in points]
    return [least_squares(a, [p['residual'][axis] for p in points]) for axis in range(2)]


def predict(point, coefficients, model):
    f = features(point, model)
    return [sum(x*y for x, y in zip(c, f)) for c in coefficients]


def stats(values):
    values = sorted(values)
    return {'count': len(values), 'mean': sum(values)/len(values),
            'p95': values[math.ceil(.95*len(values))-1], 'maximum': max(values)}


def project(h, point):
    x, y = point
    w = h[6]*x+h[7]*y+h[8]
    return [(h[0]*x+h[1]*y+h[2])/w, (h[3]*x+h[4]*y+h[5])/w]


def fit_projective(pairs):
    a, b = [], []
    for source, destination in pairs:
        x, y = [v/1000 for v in source]
        u, v = [n/1000 for n in destination]
        a.extend([[x,y,1,0,0,0,-u*x,-u*y], [0,0,0,x,y,1,-v*x,-v*y]])
        b.extend([u,v])
    h = least_squares(a,b) + [1]
    return [h[0], h[1], h[2]*1000, h[3], h[4], h[5]*1000, h[6]/1000, h[7]/1000,1]


def main():
    data = json.loads((ROOT/'source_landmarks.json').read_text())['results']
    results = []
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1260" viewBox="0 0 1000 1260">',
           '<rect width="1000" height="1260" fill="white"/>',
           '<g font-family="sans-serif" font-size="16" fill="#222">',
           '<text x="25" y="25">Source-ink landmarks projected with production four-point H</text>',
           '<text x="25" y="48">Blue: expected center. Red: residual vector magnified 8x. Canonical pixel axes.</text>']
    blank = next(r['landmarks'] for r in data if r['file'] == 'unmarked.jpg')
    blank_fit = fit(blank, 'affine')
    for capture_index, capture in enumerate(data):
        points = capture['landmarks']
        origin_x = 30 + (capture_index % 2)*500
        origin_y = 90 + (capture_index // 2)*590
        svg.append(f'<text x="{origin_x}" y="{origin_y}">{escape(capture["file"])}</text>')
        for p in points:
            x = origin_x+50+(p['expected'][0]-300)*.8
            y = origin_y+35+(p['expected'][1]-480)*.48
            dx,dy = p['residual']
            svg.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="3" fill="#1769aa"/>')
            svg.append(f'<path d="M{x:.2f},{y:.2f} l{dx*8*.8:.2f},{dy*8*.48:.2f}" stroke="#b52222" stroke-width="1.5" fill="none"/>')
        for label in [510,635,950,1185,1435]:
            y = origin_y+35+(label-480)*.48
            svg.append(f'<text x="{origin_x}" y="{y:.2f}" font-size="12">{label}</text>')
        report = json.loads((ROOT.parent/'p15_6'/f"{capture['file']}.json").read_text())
        multi = report['multiPointEstimate']['homography']
        record = {'file': capture['file'], 'fourPoint': stats([math.hypot(*p['residual']) for p in points]),
                  'multiPointDiagnostic': stats([math.dist(project(multi, p['source']), p['expected']) for p in points]),
                  'multiPointAccepted': report['multiPointEstimate']['accepted']}
        for model in ['translation', 'affine', 'quadratic']:
            errors = []
            for fold in [0, 1]:
                train = [p for p in points if int(p['question'].split('-')[1]) % 2 == fold]
                test = [p for p in points if p not in train]
                coefficients = fit(train, model)
                errors.extend(math.dist(p['residual'], predict(p['expected'], coefficients, model)) for p in test)
            record[model+'LeaveRowsOut'] = stats(errors)
        errors = []
        for fold in [0,1]:
            train = [p for p in points if int(p['question'].split('-')[1]) % 2 == fold]
            test = [p for p in points if p not in train]
            h = fit_projective([(p['source'],p['expected']) for p in train])
            errors.extend(math.dist(project(h,p['source']),p['expected']) for p in test)
        record['bubbleProjectiveLeaveRowsOut'] = stats(errors)
        record['blankAffineTransferred'] = stats([math.dist(p['residual'], predict(p['expected'], blank_fit, 'affine')) for p in points])
        results.append(record)
    pdf = []
    for path in ROOT.glob('*.measurements.json'):
        d = json.loads(path.read_text())
        assert len(d['measurements']) == 32
        assert all(len(p['inkComponents']) == 1 for p in d['measurements'])
        pdf.append({'file':path.name, 'centerDisplacement': stats([math.dist(p['expected'], p['observed']) for p in d['measurements']]),
                    'outerInkDiameters': sorted({tuple(p['inkComponents'][0][2:4]) for p in d['measurements']})})
    manual = json.loads((ROOT/'reviewed_source_landmarks.json').read_text())
    baseline = json.loads((ROOT.parent/'p15_6'/'unmarked.jpg.json').read_text())
    detected = next(d for d in json.loads((ROOT/'detections.json').read_text())
                    if d['file']=='unmarked.jpg' and d['mode']=='baseline')
    layout = json.loads(Path('test/fixtures/p15_6/published_manifest.json').read_text())['artifact']['layout']['pages'][0]
    marker_pairs = []
    for region in layout['markerRegions']:
        bounds = region['physicalMarkerBounds']
        x,y,w,h = [bounds[k]*10 for k in ['left','top','width','height']]
        corners = [[x,y],[x+w,y],[x+w,y+h],[x,y+h]]
        source = next(m['corners'] for m in detected['markers'] if m['id']==region['markerId'])
        marker_pairs.extend(zip(source,corners))
    joint_errors, bubble_fit_marker_errors = [], []
    for fold in [0,1]:
        train = [p for p in blank if int(p['question'].split('-')[1]) % 2 == fold]
        test = [p for p in blank if p not in train]
        joint = fit_projective(marker_pairs+[(p['source'],p['expected']) for p in train])
        joint_errors.extend(math.dist(project(joint,p['source']),p['expected']) for p in test)
        bubble_h = fit_projective([(p['source'],p['expected']) for p in train])
        bubble_fit_marker_errors.extend(math.dist(project(bubble_h,s),d) for s,d in marker_pairs)
    joint_comparison = {'unmarkedJointProjectiveLeaveRowsOut':stats(joint_errors),
                        'bubbleOnlyProjectiveExtrapolationToMarkers':stats(bubble_fit_marker_errors),
                        'limitation':'Unweighted linear least squares, not an optimal nonlinear fit. Marker measurements remain detector-derived. Bubble strip extrapolation is unstable.'}
    manual_results = []
    for p in manual['landmarks']:
        matched = next(b for b in blank if b['target'] == p['target'])
        four = project(baseline['fourPoint']['snapshot']['homography'], p['source'])
        multi = project(baseline['multiPointEstimate']['homography'], p['source'])
        manual_results.append(dict(p, expected=matched['expected'], fourPoint=four, multiPointDiagnostic=multi,
                                   fourDisplacement=math.dist(four, matched['expected']),
                                   multiDisplacement=math.dist(multi, matched['expected'])))
    (ROOT/'reviewed_projection.json').write_text(json.dumps({
        'provenance': manual['provenance'], 'points':manual_results,
        'fourPoint':stats([p['fourDisplacement'] for p in manual_results]),
        'multiPointDiagnostic':stats([p['multiDisplacement'] for p in manual_results]),
    },indent=2))
    (ROOT/'model_comparison.json').write_text(json.dumps({
        'provenance':'Thresholded source connected components. Alternating whole question rows held out. Narrow left content strip only; no production model or lens calibration.',
        'captures':results, 'pdf':pdf, 'blankAffineCoefficients':blank_fit, 'jointComparison':joint_comparison}, indent=2))
    svg.append('</g></svg>')
    (ROOT/'residual_map.svg').write_text('\n'.join(svg))
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
