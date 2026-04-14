# import sys
# from PIL import Image

# def generate_mem_file(input_image_path, output_mem_path="image_64x64.mem"):
#     try:
#         # 1. Open the image
#         print(f"Loading image from: {input_image_path}")
#         img = Image.open(input_image_path)
        
#         # 2. Resize to 64x64 if it isn't already
#         if img.size != (64, 64):
#             print(f"Resizing image from {img.size} to 64x64...")
#             # Use LANCZOS for high-quality downsampling
#             img = img.resize((64, 64), Image.Resampling.LANCZOS)
        
#         # 3. Convert to Grayscale ('L' mode: 0 is black, 255 is white)
#         img_gray = img.convert('L')
        
#         # 4. Extract pixels and write to .mem file
#         print(f"Generating {output_mem_path}...")
        
#         with open(output_mem_path, 'w') as f:
#             pixel_count = 0
#             # Iterate row by row (Y), then column by column (X)
#             # This matches how a CRT/VGA naturally scans
#             for y in range(64):
#                 for x in range(64):
#                     intensity = img_gray.getpixel((x, y))
                    
#                     # Thresholding: 
#                     # If intensity > 128, consider it White (1)
#                     # If intensity <= 128, consider it Black (0)
#                     bit_val = '1' if intensity > 128 else '0'
                    
#                     # Write the bit to the file
#                     f.write(bit_val + '\n')
#                     pixel_count += 1
                    
#         print(f"Success! Wrote {pixel_count} lines of 1-bit pixel data to {output_mem_path}.")

#     except FileNotFoundError:
#         print(f"Error: The file '{input_image_path}' was not found.")
#     except Exception as e:
#         print(f"An unexpected error occurred: {e}")

# if __name__ == "__main__":
#     # Check if the user provided an image path as a command-line argument
#     if len(sys.argv) < 2:
#         print("Usage: python generate_mem.py <path_to_input_image>")
#         print("Example: python generate_mem.py my_logo.png")
#     else:
#         input_image = sys.argv[1]
#         generate_mem_file(input_image)

import sys
from PIL import Image

def generate_rgb_mem(image_path):
    try:
        print(f"Loading image from: {image_path}")
        # Use 'RGB' instead of 'L' to keep full color
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