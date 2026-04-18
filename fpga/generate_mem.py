import sys
from PIL import Image

def generate_rgb_mem(image_path):
    try:
        print(f"Loading image from: {image_path}")
        img = Image.open(image_path).convert('RGB')
        
        if img.size != (64, 64):
            print(f"Resizing image from {img.size} to 64x64...")
            img = img.resize((64, 64), Image.Resampling.LANCZOS)
        
        output_mem_path = "image_64x64_rgb.mem"
        print(f"Generating {output_mem_path}...")
        
        with open(output_mem_path, "w") as f:
            for y in range(64):
                for x in range(64):
                    r, g, b = img.getpixel((x, y))
                    # Write as a 6-digit Hex (e.g., FF0000 for pure Red)
                    f.write(f"{r:02X}{g:02X}{b:02X}\n")
                    
        print("Generated image_64x64_rgb.mem successfully!")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_mem.py <image_path>")
    else:
        generate_rgb_mem(sys.argv[1])