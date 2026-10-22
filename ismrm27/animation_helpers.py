"""Consistent, unobtrusive frame counters for exported animations."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
import matplotlib


FRAME_COUNTER = {'format': 'Frame {number} / {count}', 'color': '#666666',
                 'position': 'bottom right', 'numbering': 'one-based'}


def number_frame(image, number, count, background='white'):
    """Add a small footer without covering or moving any figure content."""
    if not 1 <= number <= count:
        raise ValueError('Frame number must be in 1..count')
    image = image.convert('RGB')
    font_size = max(12, round(image.width / 100))
    font_path = Path(matplotlib.get_data_path()) / 'fonts/ttf/DejaVuSans.ttf'
    font = ImageFont.truetype(str(font_path), font_size)
    padding = max(8, round(font_size * .65))
    result = Image.new('RGB', (image.width, image.height + font_size + 2 * padding), background)
    result.paste(image, (0, 0))
    draw = ImageDraw.Draw(result)
    draw.text((result.width-padding, image.height+padding),
              FRAME_COUNTER['format'].format(number=number, count=count),
              anchor='rt', font=font, fill=FRAME_COUNTER['color'])
    return result
