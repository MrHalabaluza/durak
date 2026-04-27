#!/usr/bin/env python3
"""Generate PNG card assets for DTFool at 3x resolution (168x240)."""

from PIL import Image, ImageDraw, ImageFont
import os, math

SCALE = 3
W, H = 56 * SCALE, 80 * SCALE  # 168 x 240
CORNER_R = 6 * SCALE

RANKS = ['two', 'three', 'four', 'five', 'six', 'seven', 'eight',
         'nine', 'ten', 'jack', 'queen', 'king', 'ace']
SUITS = ['clubs', 'diamonds', 'hearts', 'spades']

RANK_LABEL = {
    'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
    'ten': '10', 'jack': 'J', 'queen': 'Q', 'king': 'K', 'ace': 'A',
}
SUIT_CHAR = {'clubs': '♣', 'diamonds': '♦', 'hearts': '♥', 'spades': '♠'}
SUIT_COLOR = {
    'clubs':   (30, 30, 30),
    'spades':  (30, 30, 30),
    'hearts':  (185, 20, 20),
    'diamonds':(185, 20, 20),
}

FONT_BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'
FONT_REG  = '/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'

CARDS_DIR = os.path.join(os.path.dirname(__file__), 'ui/assets/cards')
BACKS_DIR = os.path.join(os.path.dirname(__file__), 'ui/assets/backs')


def rounded_rect(draw, x0, y0, x1, y1, r, fill):
    draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)
    draw.ellipse([x0, y0, x0 + 2*r, y0 + 2*r], fill=fill)
    draw.ellipse([x1 - 2*r, y0, x1, y0 + 2*r], fill=fill)
    draw.ellipse([x0, y1 - 2*r, x0 + 2*r, y1], fill=fill)
    draw.ellipse([x1 - 2*r, y1 - 2*r, x1, y1], fill=fill)


def new_card(bg=(248, 248, 255)):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rounded_rect(draw, 0, 0, W, H, CORNER_R, bg)
    return img, draw


def draw_corner(draw, label, sym, color, font_rank, font_suit):
    """Draw rank + suit glyph in top-left corner."""
    x, y = 5 * SCALE, 2 * SCALE
    draw.text((x, y), label, font=font_rank, fill=color)
    rank_h = draw.textbbox((x, y), label, font=font_rank)[3] - y
    draw.text((x, y + rank_h), sym, font=font_suit, fill=color)


def generate_face(suit, rank):
    color  = SUIT_COLOR[suit]
    label  = RANK_LABEL[rank]
    sym    = SUIT_CHAR[suit]

    f_rank_sm = ImageFont.truetype(FONT_BOLD, 13 * SCALE)
    f_suit_sm = ImageFont.truetype(FONT_REG,  12 * SCALE)
    f_suit_lg = ImageFont.truetype(FONT_REG,  26 * SCALE)

    img, draw = new_card()

    # Top-left corner
    draw_corner(draw, label, sym, color, f_rank_sm, f_suit_sm)

    # Center large suit
    bb = draw.textbbox((0, 0), sym, font=f_suit_lg)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    cx = (W - tw) // 2 - bb[0]
    cy = (H - th) // 2 - bb[1]
    draw.text((cx, cy), sym, font=f_suit_lg, fill=color)

    # Bottom-right corner: paste a rotated copy of the top-left overlay
    overlay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    draw_corner(od, label, sym, color, f_rank_sm, f_suit_sm)
    img.alpha_composite(overlay.rotate(180))

    return img


def generate_back():
    img, draw = new_card(bg=(26, 35, 126))

    m1, r1 = 3 * SCALE, 4 * SCALE
    # Inner border (arc-based outline)
    lw = max(1, round(1.5 * SCALE))
    draw.rounded_rectangle([m1, m1, W - m1, H - m1], radius=r1,
                            outline=(57, 73, 171), width=lw)

    m2, r2 = 6 * SCALE, 3 * SCALE
    rounded_rect(draw, m2, m2, W - m2, H - m2, r2, (40, 53, 147))

    # Diagonal lines
    dlw = max(1, round(0.8 * SCALE))
    draw.line([(m2, m2), (W - m2, H - m2)], fill=(57, 73, 171, 128), width=dlw)
    draw.line([(W - m2, m2), (m2, H - m2)], fill=(57, 73, 171, 128), width=dlw)

    # Circle
    cx, cy = W // 2, H // 2
    ro, ri = 10 * SCALE, 5 * SCALE
    draw.ellipse([cx - ro, cy - ro, cx + ro, cy + ro],
                 outline=(92, 107, 192), width=lw)
    draw.ellipse([cx - ri, cy - ri, cx + ri, cy + ri],
                 fill=(57, 73, 171))

    return img


if __name__ == '__main__':
    for suit in SUITS:
        for rank in RANKS:
            img = generate_face(suit, rank)
            path = os.path.join(CARDS_DIR, f'{suit}_{rank}.png')
            img.save(path, 'PNG')
            print(f'  {suit}_{rank}.png')

    back = generate_back()
    back.save(os.path.join(BACKS_DIR, 'default.png'), 'PNG')
    print('  backs/default.png')
    print('Done.')
