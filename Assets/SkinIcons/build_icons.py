from pathlib import Path
import math, subprocess
ROOT=Path(__file__).parent

def svg(defs,body):
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>{defs}</defs>{body}</svg>'
shadow='''<radialGradient id="groundShadow"><stop stop-color="#082f4d" stop-opacity=".27"/><stop offset=".65" stop-color="#082f4d" stop-opacity=".13"/><stop offset="1" stop-color="#082f4d" stop-opacity="0"/></radialGradient><filter id="shadow" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="15"/></filter>
<filter id="objectShadow" x="-40%" y="-40%" width="180%" height="190%"><feGaussianBlur stdDeviation="12"/></filter>
<clipPath id="tileClip"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'''
def tile(fill, stroke,small=False):
 return ''.join(f'<rect x="{100-i}" y="{115-i}" width="{824+2*i}" height="{824+2*i}" rx="{185+i}" fill="#08233e" opacity=".009"/>' for i in range(24,0,-2)) + f'''
<rect x="100" y="100" width="824" height="824" rx="185" fill="{fill}"/>
<rect x="104" y="104" width="816" height="816" rx="181" fill="none" stroke="{stroke}" stroke-width="8" opacity=".6"/>'''

def luna(small=False):
 defs=shadow+'''<linearGradient id="tile" x2=".15" y2="1"><stop stop-color="#c2f7ff"/><stop offset=".48" stop-color="#60c5f5"/><stop offset="1" stop-color="#57a78e"/></linearGradient>
<radialGradient id="globe" cx=".32" cy=".22" r=".85"><stop stop-color="#7ceaff"/><stop offset=".35" stop-color="#20a9ed"/><stop offset=".7" stop-color="#0069ca"/><stop offset="1" stop-color="#00367c"/></radialGradient>
<linearGradient id="gold" x1="0" y1="0" x2=".3" y2="1"><stop stop-color="#fff5ab"/><stop offset=".25" stop-color="#ffe45c"/><stop offset=".55" stop-color="#ffc62c"/><stop offset="1" stop-color="#e58b08"/></linearGradient>
<linearGradient id="shine" x2=".2" y2="1"><stop stop-color="white" stop-opacity=".87"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient>
<clipPath id="globeClip"><circle cx="512" cy="493" r="263"/></clipPath>'''
 body=tile('url(#tile)','#e0fcff')
 if not small:
  body+='''<g clip-path="url(#tileClip)"><path d="M100 770 Q340 650 558 766 T924 727 V924 H100Z" fill="#a9dc9a" opacity=".25"/><path d="M100 830 Q420 720 924 803 V924 H100Z" fill="#247e9b" opacity=".16"/></g>'''
 body+='''<ellipse cx="510" cy="790" rx="260" ry="34" fill="url(#groundShadow)"/>
<ellipse cx="512" cy="510" rx="351" ry="117" transform="rotate(-28 512 510)" fill="none" stroke="#c58a16" stroke-width="49"/>
<ellipse cx="512" cy="507" rx="351" ry="117" transform="rotate(-28 512 507)" fill="none" stroke="url(#gold)" stroke-width="40"/>
<circle cx="512" cy="499" r="267" fill="#075f9d"/>
<circle cx="512" cy="493" r="263" fill="url(#globe)"/>
<g clip-path="url(#globeClip)">'''
 if not small:
  body+='''<g fill="none" stroke="#8de6ff" stroke-width="5" opacity=".5"><ellipse cx="512" cy="493" rx="125" ry="263"/><ellipse cx="512" cy="493" rx="228" ry="263"/><path d="M248 493H776M275 390Q512 322 749 390M275 596Q512 664 749 596"/></g>'''
 body+='''<g fill="#8bdfed" opacity=".72"><path d="M307 329L373 289 434 307 455 346 418 379 429 420 385 440 349 407 317 406 286 369Z"/><path d="M423 457L475 475 493 525 469 575 470 618 432 680 409 626 401 570 375 536 391 481Z"/><path d="M555 265L626 280 688 324 701 367 660 386 621 370 604 408 564 396 542 350 565 320Z"/><path d="M622 446L685 423 739 460 757 514 714 540 675 511 647 537 624 499Z"/></g>'''
 if not small:
  body+='''<path d="M295 370C327 258 491 220 590 273C539 260 491 291 463 326C406 399 350 407 295 370Z" fill="url(#shine)"/>
<path d="M312 344Q351 294 413 282" fill="none" stroke="#fff" stroke-width="13" stroke-linecap="round" opacity=".85"/>'''
 body+='''</g><path d="M249 492A263 263 0 0 1 683 294" fill="none" stroke="#a4efff" stroke-width="5" opacity=".65"/>
<path d="M863 510A351 117 0 0 1 161 510" transform="rotate(-28 512 510)" fill="none" stroke="#bc7c0c" stroke-width="49"/>
<path d="M863 506A351 117 0 0 1 161 506" transform="rotate(-28 512 506)" fill="none" stroke="url(#gold)" stroke-width="40"/>'''
 if not small:
  body+='''<path d="M841 546C784 610 599 635 421 610" transform="rotate(-28 512 510)" fill="none" stroke="#fff6b6" stroke-width="7" stroke-linecap="round" opacity=".9"/>'''
 return svg(defs,body)

def aqua(small=False):
 defs=shadow+'''<linearGradient id="tile" x2="0" y2="1"><stop stop-color="#fbfcfd"/><stop offset=".48" stop-color="#dedfe2"/><stop offset="1" stop-color="#b4bac2"/></linearGradient>
<pattern id="pin" width="8" height="8" patternUnits="userSpaceOnUse"><path d="M0 1H8" stroke="#fff" opacity=".32" stroke-width="2"/><path d="M0 5H8" stroke="#687687" opacity=".10"/></pattern>
<linearGradient id="chrome" x1=".1" y1="0" x2=".8" y2="1"><stop stop-color="#778a9c"/><stop offset=".12" stop-color="#fff"/><stop offset=".32" stop-color="#bbc7d1"/><stop offset=".48" stop-color="#f7fcff"/><stop offset=".6" stop-color="#71859b"/><stop offset=".8" stop-color="#dce6ef"/><stop offset="1" stop-color="#66798b"/></linearGradient>
<radialGradient id="gel" cx=".35" cy=".17" r=".85"><stop stop-color="#8feaff"/><stop offset=".35" stop-color="#19b8fa"/><stop offset=".65" stop-color="#007cda"/><stop offset="1" stop-color="#003e98"/></radialGradient>
<linearGradient id="gelLight" x2="0" y2="1"><stop stop-color="#fff" stop-opacity=".95"/><stop offset="1" stop-color="#e6fbff" stop-opacity=".04"/></linearGradient>
<linearGradient id="hole" x2="0" y2="1"><stop stop-color="#18364f"/><stop offset=".3" stop-color="#73899e"/><stop offset="1" stop-color="#e5eef4"/></linearGradient>
<radialGradient id="white" cx=".35" cy=".25"><stop stop-color="#fff"/><stop offset=".8" stop-color="#f3f8fc"/><stop offset="1" stop-color="#b5c8da"/></radialGradient>'''
 body=tile('url(#tile)','#ffffff')
 if not small: body+='<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#pin)"/>'
 body+='''<ellipse cx="512" cy="802" rx="283" ry="38" fill="url(#groundShadow)"/>
<circle cx="512" cy="515" r="316" fill="#6e7c89"/>
<circle cx="512" cy="502" r="316" fill="url(#chrome)" stroke="#718698" stroke-width="3"/>
<circle cx="512" cy="502" r="300" fill="none" stroke="#faffff" stroke-width="4" opacity=".9"/>
<circle cx="512" cy="502" r="286" fill="#0a4777"/>
<circle cx="512" cy="497" r="278" fill="url(#gel)"/>
<path d="M267 410C310 206 686 201 756 401C675 363 636 373 512 379C393 385 342 435 267 410Z" fill="url(#gelLight)"/>
<path d="M301 638C401 802 648 779 723 636C644 710 401 729 301 638Z" fill="#36c9ff" opacity=".45"/>'''
 for i in range(10):
  a=math.radians(70+i*32); x=512+210*math.cos(a); y=497+210*math.sin(a)
  r=42 if not small else 40
  body+=f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r+5}" fill="#003e82" opacity=".8"/><circle cx="{x:.2f}" cy="{y-2:.2f}" r="{r}" fill="url(#hole)" stroke="#85dfff" stroke-width="3"/>'
  if not small: body+=f'<path d="M{x-28:.2f} {y+23:.2f}Q{x:.2f} {y+43:.2f} {x+28:.2f} {y+23:.2f}" fill="none" stroke="#fff" stroke-width="3" opacity=".72"/>'
 body+='''<circle cx="512" cy="497" r="126" fill="#004c99" opacity=".8"/>
<circle cx="512" cy="491" r="114" fill="url(#chrome)"/>
<circle cx="512" cy="491" r="101" fill="url(#white)" stroke="#fff" stroke-width="3"/>
<path d="M719 592L756 571Q769 567 774 582L782 626Q784 642 769 648L742 654Q731 656 728 644Z" fill="#234d6b" opacity=".45"/>
<path d="M717 579L751 562Q763 558 768 571L776 612Q778 624 764 630L738 637Q727 639 724 627Z" fill="url(#chrome)" stroke="#627b8d" stroke-width="4"/>
<path d="M728 581L752 573L759 611L737 619Z" fill="#f8fdff" opacity=".8"/>'''
 if not small: body+='''<path d="M350 276Q460 211 582 241" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round" opacity=".9"/><path d="M462 446Q499 425 542 439" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round"/>'''
 return svg(defs,body)

def classic(small=False):
 defs=shadow+'''<linearGradient id="night" x2="0" y2="1"><stop stop-color="#1b2855"/><stop offset=".52" stop-color="#101c40"/><stop offset="1" stop-color="#063b61"/></linearGradient>
<linearGradient id="earth" x2="0" y2="1"><stop stop-color="#187ea2"/><stop offset=".45" stop-color="#125174"/><stop offset="1" stop-color="#142b4c"/></linearGradient>
<linearGradient id="tail" x1="0" y1="1" x2="1" y2="0"><stop stop-color="#3594b3"/><stop offset=".5" stop-color="#85e5e5"/><stop offset="1" stop-color="#fff5b5"/></linearGradient>'''
 body=tile('url(#night)','#526b91')+'<g clip-path="url(#tileClip)">'
 if not small:
  body+='''<path d="M126 620Q512 446 898 620" fill="none" stroke="#22496c" stroke-width="2"/><path d="M140 663Q512 476 884 663" fill="none" stroke="#22496c" stroke-width="2"/>'''
 stars=[(260,280,6),(444,235,5),(753,235,7),(802,480,5),(257,464,4),(570,313,4)] if not small else [(270,290,12),(458,245,10),(782,479,10)]
 for x,y,r in stars:
  body+=f'<path d="M{x-r} {y}L{x} {y-r}L{x+r} {y}L{x} {y+r}Z" fill="#d4e8e9"/>'
 body+='''<path d="M100 771Q512 482 924 771V924H100Z" fill="#154a74"/>
<path d="M100 790Q512 501 924 790V924H100Z" fill="#4ab5c7"/>
<path d="M100 802Q512 513 924 802V924H100Z" fill="#94e1d4"/>
<path d="M100 818Q512 529 924 818V924H100Z" fill="url(#earth)"/>
<path d="M172 780L263 717 336 698 373 714 350 739 411 758 449 790 416 820 323 811 290 837 221 820Z" fill="#3e9e98"/>
<path d="M559 666L631 679 651 702 717 727 739 761 696 778 646 745 612 748 578 721 536 706Z" fill="#3e9e98"/>'''
 if not small:
  body+='''<g fill="none" stroke="#6fc1c6" opacity=".24" stroke-width="3"><path d="M178 862Q512 638 846 862M274 924Q512 664 750 924M512 631V924"/></g>'''
 # One wavy, tapered tail: deliberately asymmetric, with no circular orbit or letter.
 body+='''<path d="M269 566C317 527 388 555 398 502C406 459 455 480 478 456C501 431 486 412 529 414C587 420 586 370 646 362L716 344L680 383C614 395 628 454 553 450C532 449 531 455 518 478C485 529 445 495 437 534C423 594 334 565 269 566Z" fill="#22577c"/>
<path d="M269 557C317 518 388 546 398 493C406 450 455 471 478 447C501 422 486 403 529 405C587 411 586 361 646 353L716 335L680 374C614 386 628 445 553 441C532 440 531 446 518 469C485 520 445 486 437 525C423 585 334 556 269 557Z" fill="url(#tail)"/>
<path d="M351 543C415 535 395 488 441 485C510 484 487 421 539 426C592 433 600 378 653 368L708 344" fill="none" stroke="#d4f3da" stroke-width="10" stroke-linecap="round"/>
<circle cx="710" cy="347" r="44" fill="#5bb5c1" opacity=".16"/>
<circle cx="710" cy="347" r="32" fill="#ffe4a1"/>
<circle cx="715" cy="342" r="23" fill="#fffad6"/>
<path d="M708 323L723 326L732 340L715 352L699 346Z" fill="#fff"/>
</g>'''
 if small:
  body=body.replace('fill="url(#tail)"/>','fill="url(#tail)" stroke="#99e5d8" stroke-width="16" stroke-linejoin="round"/>').replace('stroke-width="10"','stroke-width="20"').replace('r="32" fill="#ffe4a1"','r="43" fill="#ffe4a1"').replace('r="23" fill="#fffad6"','r="30" fill="#fffad6"')
 return svg(defs,body)

if __name__ == '__main__':
 if not (ROOT/'.svg-render').exists():
  subprocess.run(['swiftc','-module-cache-path',str(ROOT/'.module-cache'),str(ROOT/'render.swift'),'-o',str(ROOT/'.svg-render')],check=True)
 for name, fn in [('luna',luna),('aqua',aqua),('classic',classic)]:
  for small in (False,True):
   (ROOT/f'{name}{"-small" if small else ""}.svg').write_text(fn(small))
  for size in (16,32,64,128,256,512,1024):
   src=ROOT/f'{name}{"-small" if size<=64 else ""}.svg'
   subprocess.run([str(ROOT/'.svg-render'),str(src),str(ROOT/f'{name}_{size}.png'),str(size)],check=True)
 print('Created six SVGs and 21 PNGs.')
