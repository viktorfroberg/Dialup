from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).parent
sheet=Image.new('RGB',(960,444),'#edf0f4')
d=ImageDraw.Draw(sheet)
font='/System/Library/Fonts/Supplemental/Arial.ttf'
label=ImageFont.truetype(font,20)
small=ImageFont.truetype(font,12)
for i,name in enumerate(['luna','aqua','classic']):
 x=32+i*312
 d.text((x+128,24),name.title(),fill='#263449',font=label,anchor='mt')
 sheet.paste(Image.open(root/f'{name}_256.png'),(x,51),Image.open(root/f'{name}_256.png'))
 d.text((x+128,313),'256 px',fill='#687384',font=small,anchor='mt')
 for size,cx in [(32,x+84),(16,x+174)]:
  im=Image.open(root/f'{name}_{size}.png')
  sheet.paste(im,(cx-size//2,358-size//2),im)
  d.text((cx,386),f'{size} px',fill='#687384',font=small,anchor='mt')
sheet.save(root/'sheet.png')
