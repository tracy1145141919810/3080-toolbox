"""Offline OCR worker. All models are provisioned at build time, never downloaded.

PP-OCRv5 recognition includes Chinese, English and Japanese. Preserve every
detected quadrilateral, confidence and image dimensions for the layout viewer.
"""
import argparse
import json
import socket
import re
import sys
import time
from pathlib import Path


def deny_network(*args, **kwargs):
    raise RuntimeError('OCR is offline; network access is disabled')


# Fail closed even if a dependency tries to fetch a missing model.
socket.socket.connect = deny_network
socket.socket.connect_ex = deny_network
socket.create_connection = deny_network


def recognize(input_path, models, width=0, height=0, japanese=False):
    input_width, input_height = width, height
    import cv2
    import numpy as np
    from rapidocr import RapidOCR, OCRVersion, ModelType, LangRec

    det = models / 'ch_PP-OCRv5_det_mobile.onnx'
    rec = models / ('japan_PP-OCRv4_rec_mobile.onnx' if japanese else 'ch_PP-OCRv5_rec_mobile.onnx')
    cls = models / 'ch_ppocr_mobile_v2.0_cls_mobile.onnx'
    for file in (det, rec, cls):
        if not file.is_file():
            raise RuntimeError(f'Bundled OCR model missing: {file.name}')
    if width and height:
        pixels = np.fromfile(str(input_path), dtype=np.uint8)
        image = cv2.cvtColor(pixels.reshape(height, width, 4), cv2.COLOR_BGRA2BGR)
    else:
        image = cv2.imdecode(np.fromfile(str(input_path), dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError('Cannot decode image')
    height, width = image.shape[:2]
    engine = RapidOCR(params={
        'Det.model_path': str(det), 'Det.ocr_version': OCRVersion.PPOCRV5,
        'Det.model_type': ModelType.MOBILE, 'Det.limit_side_len': 1280,
        'Det.limit_type': 'max', 'Det.unclip_ratio': 1.4,
        'Rec.model_path': str(rec), 'Rec.ocr_version': OCRVersion.PPOCRV4 if japanese else OCRVersion.PPOCRV5,
        'Rec.lang_type': LangRec.JAPAN if japanese else LangRec.CH,
        'Rec.model_type': ModelType.MOBILE, 'Cls.model_path': str(cls),
        'Global.log_level': 'error', 'Global.text_score': 0.35,
        'EngineConfig.onnxruntime.intra_op_num_threads': 4,
        'EngineConfig.onnxruntime.inter_op_num_threads': 1,
    })
    result = engine(image)
    if not japanese and result.txts and re.search(r'[\u3040-\u30ff]', ''.join(result.txts)):
        return recognize(input_path, models, input_width, input_height, japanese=True)
    # Repeated horizontal credits/table rows can be mistaken for vertical text.
    # Detect a regular row rhythm, then re-detect bounded strips. No names,
    # coordinates or reference-image text are hardcoded.
    if result.boxes is not None and len(result.boxes) >= 12:
        boxes = result.boxes
        heights = [float(max(b[:, 1]) - min(b[:, 1])) for b in boxes]
        typical_height = float(np.median(heights))
        centers = sorted(float(np.mean(b[:, 1])) for b, h in zip(boxes, heights)
                         if h < typical_height * 1.6)
        groups = []
        for center in centers:
            if groups and abs(center - np.median(groups[-1])) < typical_height * .48:
                groups[-1].append(center)
            else:
                groups.append([center])
        rows = [float(np.median(g)) for g in groups]
        gaps = np.diff(rows)
        regular = len(rows) >= 10 and np.count_nonzero(
            abs(gaps - np.median(gaps)) < np.median(gaps) * .25) >= len(gaps) * .7
        coverage = np.zeros(width, dtype=np.int32)
        for box, h in zip(boxes, heights):
            if h < typical_height * 1.6:
                coverage[max(0,int(min(box[:,0]))):min(width,int(max(box[:,0])))] += 1
        # A persistent empty gutter separates columns; a heading may cross it.
        candidates = []
        start = None
        for x in range(int(width*.15), int(width*.85)):
            if coverage[x] <= 2:
                if start is None: start = x
            elif start is not None:
                if x-start > typical_height*.5 and max(coverage[:start],default=0)>6 and max(coverage[x:],default=0)>6:
                    candidates.append((start,x))
                start = None
        gutter = max(candidates,key=lambda pair:pair[1]-pair[0]) if candidates else None
        if regular and gutter:
            split = sum(gutter)//2
            columns = [(0,split),(split,width)]
            column_boxes = [[b for b in boxes if lo <= np.mean(b[:,0]) < hi
                             and not min(b[:,0]) < split < max(b[:,0])
                             and max(b[:,1])-min(b[:,1]) < typical_height*1.6]
                            for lo,hi in columns]
            crops, new_boxes = [], []
            for i, center in enumerate(rows):
                half_gap = float(np.median(gaps)) / 2
                top = max(0, int(max(center-half_gap, (rows[i-1]+center)/2 if i else 0)))
                bottom = min(height, int(min(center+half_gap, (rows[i+1]+center)/2 if i+1<len(rows) else height)))
                # Headings crossing the gutter stay as one source box.
                crossing = [b for b in boxes if min(b[:,0]) < split < max(b[:,0])
                            and abs(np.mean(b[:,1])-center)<typical_height*.5]
                regions = [crossing] if crossing else column_boxes
                for region in regions:
                    matches = [b for b in region if abs(np.mean(b[:,1])-center)<typical_height*.5]
                    if not matches and (i == 0 or i == len(rows)-1):
                        continue
                    # Missing cells are re-read from the same recurring column.
                    source = region if region is column_boxes[1] else (matches or region)
                    if not source: continue
                    left = max(0, int(min(min(b[:,0]) for b in source))-2)
                    right = min(width,int(max(max(b[:,0]) for b in source))+2)
                    crops.append(image[top:bottom,left:right])
                    new_boxes.append(np.array([[left,top],[right,top],[right,bottom],[left,bottom]],dtype=np.float32))
            if new_boxes:
                reread = engine.recognize_txt(crops)
                valid = [(b,t,s) for b,t,s in zip(new_boxes,reread.txts,reread.scores) if t.strip() and s>=.35]
                result.boxes = np.array([v[0] for v in valid])
                result.txts = [v[1] for v in valid]
                result.scores = [v[2] for v in valid]
    blocks = []
    if result.boxes is not None:
        for box, text, score in zip(result.boxes, result.txts, result.scores):
            points = [[float(x), float(y)] for x, y in box]
            blocks.append({'text': text, 'confidence': float(score),
                           'points': points,
                           'x': min(p[0] for p in points),
                           'y': min(p[1] for p in points),
                           'width': max(p[0] for p in points) - min(p[0] for p in points),
                           'height': max(p[1] for p in points) - min(p[1] for p in points)})
    return {'width': width, 'height': height, 'blocks': blocks,
            'text': '\n'.join(b['text'] for b in blocks),
            'language': '日语（本地）' if japanese else '中 / 日 / 英（本地多语种）',
            'engine': 'PP-OCRv5-det + Japanese-rec' if japanese else 'PP-OCRv5'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--width', type=int, default=0)
    parser.add_argument('--height', type=int, default=0)
    parser.add_argument('--models', type=Path)
    parser.add_argument('--japanese', action='store_true')
    args = parser.parse_args()
    base = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).parent
    started = time.perf_counter()
    status = 0
    try:
        result = recognize(args.input, args.models or base / 'models', args.width, args.height, args.japanese)
        result['elapsedMs'] = round((time.perf_counter() - started) * 1000)
    except Exception as error:
        result = {'error': str(error)}
        status = 1
    args.output.write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
    return status


if __name__ == '__main__':
    sys.exit(main())
