"""Render recovered PDFs with an existing PDFium DLL; no package installation.

Usage: python tool/p15_7_pdf_raster.py /path/to/x64/pdfium.dll
Writes opaque 2100x2970 BMPs and actual PDF dimensions/text/hash metadata.
"""
import ctypes as c
import hashlib
import json
from pathlib import Path
import struct
import sys


def main():
    dll = c.CDLL(sys.argv[1])

    def api(name, result, *args):
        function = getattr(dll, name)
        function.restype = result
        function.argtypes = list(args)
        return function

    ptr, integer = c.c_void_p, c.c_int
    init = api('FPDF_InitLibrary', None)
    destroy = api('FPDF_DestroyLibrary', None)
    load = api('FPDF_LoadDocument', ptr, c.c_char_p, c.c_char_p)
    close = api('FPDF_CloseDocument', None, ptr)
    count = api('FPDF_GetPageCount', integer, ptr)
    page_load = api('FPDF_LoadPage', ptr, ptr, integer)
    page_close = api('FPDF_ClosePage', None, ptr)
    width = api('FPDF_GetPageWidth', c.c_double, ptr)
    height = api('FPDF_GetPageHeight', c.c_double, ptr)
    bitmap_create = api('FPDFBitmap_Create', ptr, integer, integer, integer)
    bitmap_close = api('FPDFBitmap_Destroy', None, ptr)
    fill = api('FPDFBitmap_FillRect', None, ptr, integer, integer, integer, integer, c.c_ulong)
    render = api('FPDF_RenderPageBitmap', None, ptr, ptr, integer, integer, integer, integer, integer, integer)
    buffer = api('FPDFBitmap_GetBuffer', ptr, ptr)
    stride = api('FPDFBitmap_GetStride', integer, ptr)
    text_load = api('FPDFText_LoadPage', ptr, ptr)
    text_close = api('FPDFText_ClosePage', None, ptr)
    text_count = api('FPDFText_CountChars', integer, ptr)
    text_get = api('FPDFText_GetText', integer, ptr, integer, integer, ptr)
    output = Path('build/p157')
    output.mkdir(parents=True, exist_ok=True)
    records = []
    init()
    try:
        for source in ['published_template.pdf', 'packet_print_job.pdf']:
            path = Path('test/fixtures/p15_6' if source == 'published_template.pdf' else 'test/fixtures/p15_7') / source
            doc = load(str(path.resolve()).encode(), None)
            if not doc:
                raise RuntimeError(f'PDFium could not load {path}')
            try:
                for index in range(count(doc)):
                    page = page_load(doc, index)
                    bitmap = bitmap_create(2100, 2970, 0)
                    text = None
                    try:
                        fill(bitmap, 0, 0, 2100, 2970, 0xffffffff)
                        render(bitmap, page, 0, 0, 2100, 2970, 0, 0)
                        row_bytes = stride(bitmap)
                        pixels = c.string_at(buffer(bitmap), row_bytes * 2970)
                        # Negative height stores the PDFium top-down BGRA data.
                        header = struct.pack('<2sIHHI', b'BM', 54+len(pixels), 0, 0, 54)
                        header += struct.pack('<IiiHHIIiiII', 40, 2100, -2970, 1, 32, 0, len(pixels), 10000, 10000, 0, 0)
                        target = output / f'{source}_{index}.bmp'
                        target.write_bytes(header + pixels)
                        text = text_load(page)
                        length = text_count(text)
                        chars = (c.c_ushort * (length + 1))()
                        text_get(text, 0, length, chars)
                        records.append({
                            'file': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                            'page': index, 'widthPoints': width(page), 'heightPoints': height(page),
                            'raster': str(target), 'widthPixels': 2100, 'heightPixels': 2970,
                            'text': bytes(chars).decode('utf-16-le').rstrip('\0'),
                        })
                    finally:
                        if text:
                            text_close(text)
                        bitmap_close(bitmap)
                        page_close(page)
            finally:
                close(doc)
    finally:
        destroy()
    Path('docs/development/evidence/p15_7/pdf_provenance.json').write_text(json.dumps(records, indent=2))
    print([(r['file'], r['page'], r['widthPoints'], r['heightPoints']) for r in records])


if __name__ == '__main__':
    main()
