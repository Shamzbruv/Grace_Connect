from collections import Counter
import sys

# Simplified logic since we might not have PIL installed or cannot easily install it.
# Wait, I can try to use standard library or just guess if I can't run it.
# But I should try to do it right.
# Let's check if python3 and PIL is available.
try:
    from PIL import Image
except ImportError:
    print("PIL not installed")
    sys.exit(1)

def get_dominant_colors(image_path, num_colors=4):
    image = Image.open(image_path)
    image = image.convert('RGB')
    image = image.resize((150, 150))      # Resize to speed up
    pixels = list(image.getdata())
    
    # Filter out white/near-white background
    pixels = [p for p in pixels if p[0] < 250 or p[1] < 250 or p[2] < 250]
    
    counts = Counter(pixels)
    most_common = counts.most_common(num_colors)
    
    return [f'#{r:02x}{g:02x}{b:02x}' for (r, g, b), count in most_common]

if __name__ == "__main__":
    if len(sys.argv) > 1:
        path = sys.argv[1]
        colors = get_dominant_colors(path)
        print("Colors:", colors)
