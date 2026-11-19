#!/usr/bin/env python3
"""Convert artwork to a four-colour C64 multicolour title bitmap.

Requires Pillow: python3 -m pip install Pillow
Example:
  python3 convert_bitmap.py my_title.png --out my_title \
    --update-source galaxian.asm --output-source my_game.asm

Input: 320x200 display pixels or 160x200 logical multicolour pixels.
Each logical pixel is twice as wide on the C64. The default palette is
black / yellow / red / white. This intentionally uses four fixed colours
throughout: valid C64 cell restrictions are therefore guaranteed.
"""
import argparse
from pathlib import Path
from PIL import Image
PALETTE=[(0,0,0),(255,255,255),(136,0,0),(170,255,238),(204,68,204),(0,204,85),(0,0,170),(238,238,119),(221,136,85),(102,68,0),(255,119,119),(51,51,51),(119,119,119),(170,255,102),(0,136,255),(187,187,187)]
BEGIN='; BEGIN TITLE BITMAP ASSET'
END='; END TITLE BITMAP ASSET'
def convert(image,colours=(0,7,2,1)):
    if image.size not in [(160,200),(320,200)]:
        raise ValueError('Use 320x200 display pixels or 160x200 logical pixels.')
    image=image.convert('RGB')
    if image.size==(320,200):image=image.resize((160,200),Image.Resampling.NEAREST)
    rgb=[PALETTE[i] for i in colours]
    # Cache repeated RGB values: exact palette artwork converts especially fast.
    cache={}
    def nearest(p):
        if p not in cache:cache[p]=min(range(4),key=lambda i:sum((p[j]-rgb[i][j])**2 for j in range(3)))
        return cache[p]
    data=image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    pixels=[nearest(p) for p in data]
    bitmap=bytearray(8000)
    for y in range(200):
        for cell in range(40):
            # Eight bytes per 4x8-logical-pixel cell, left-to-right then down.
            at=(y//8)*320+cell*8+(y&7)
            p=y*160+cell*4
            bitmap[at]=(pixels[p]<<6)|(pixels[p+1]<<4)|(pixels[p+2]<<2)|pixels[p+3]
    screen=bytes([(colours[1]<<4)|colours[2]])*1000
    colour=bytes([colours[3]])*1000
    preview=Image.new('RGB',(160,200));preview.putdata([rgb[p] for p in pixels])
    return bytes(bitmap),screen,colour,preview.resize((320,200),Image.Resampling.NEAREST)
def emit(data):
    return '\n'.join('    !byte '+','.join('$%02x'%x for x in data[i:i+32]) for i in range(0,len(data),32))
def asset_asm(bitmap,screen,colour,bg=0):
    return '\n'.join([BEGIN,f'TITLE_BACKGROUND = {bg}',
      '; Bitmap-mode screen matrix: high/low nibbles select pixel colours 01/10.',
      '* = $8c00','title_screen_data:',emit(screen),
      '; Third per-cell colour: copied into physical colour RAM when intro starts.',
      '* = $9000','title_colour_data:',emit(colour),
      '; 8000 bitmap bytes; VIC bank 2 reads RAM underneath BASIC ROM.',
      '* = $a000','title_bitmap_data:',emit(bitmap),
      '!if * != $bf40 { !error "Title bitmap must contain exactly 8000 bytes" }',END])
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('image',type=Path);p.add_argument('--out',type=Path,default=Path('title'))
    p.add_argument('--colours',nargs=4,type=int,default=[0,7,2,1],metavar=('BG','01','10','11'))
    p.add_argument('--update-source',type=Path);p.add_argument('--output-source',type=Path)
    a=p.parse_args()
    if any(not 0<=i<=15 for i in a.colours) or len(set(a.colours))!=4:p.error('Choose four distinct C64 colour numbers from 0 to 15.')
    if bool(a.update_source)!=bool(a.output_source):p.error('--update-source and --output-source must be supplied together.')
    bitmap,screen,colour,preview=convert(Image.open(a.image),a.colours)
    a.out.parent.mkdir(parents=True,exist_ok=True)
    for suffix,data in [('.bitmap',bitmap),('.screen',screen),('.colour',colour)]:Path(str(a.out)+suffix).write_bytes(data)
    preview.save(str(a.out)+'_preview.png')
    asset=asset_asm(bitmap,screen,colour,a.colours[0]);Path(str(a.out)+'_asset.asm').write_text(asset+'\n')
    if a.update_source:
        text=a.update_source.read_text()
        if text.count(BEGIN)!=1 or text.count(END)!=1:p.error('Source must contain exactly one complete title bitmap asset marker pair.')
        first=text.index(BEGIN);last=text.index(END)+len(END)
        a.output_source.write_text(text[:first]+asset+text[last:])
    print('Converted: 8000 bitmap bytes, 1000 screen bytes, 1000 colour bytes.')
    print('Preview:',str(a.out)+'_preview.png')
if __name__=='__main__':main()
