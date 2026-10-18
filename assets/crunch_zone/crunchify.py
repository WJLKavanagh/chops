import os
import re
import argparse
from collections import defaultdict
from PIL import Image

def process_images(input_folder):
    # Create the 'processed' folder inside the target directory
    processed_folder = os.path.join(input_folder, "processed")
    os.makedirs(processed_folder, exist_ok=True)

    # Supported image extensions
    valid_extensions = ('.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.webp')
    
    # Get all images and sort them to maintain sequence order
    files = [f for f in os.listdir(input_folder) if f.lower().endswith(valid_extensions)]
    files.sort()

    if not files:
        print("No images found in the specified directory.")
        return

    # Group files into distinct sequences based on their text prefix
    sequences = defaultdict(list)
    for filename in files:
        name, _ = os.path.splitext(filename)
        # Search for trailing digits at the end of the filename
        match = re.search(r'(\d+)$', name)
        
        if match:
            # Extract everything before the trailing numbers (e.g., "Run_" from "Run_005")
            prefix = name[:match.start()]
        else:
            # If there are no numbers at all, use the whole name and add an underscore
            prefix = name + "_" if not name.endswith("_") else name
            
        sequences[prefix].append(filename)

    # Process each identified sequence separately
    for prefix, file_list in sequences.items():
        print(f"\nProcessing sequence: '{prefix}' ({len(file_list)} original frames)")
        
        # Convert 60fps to 15fps by keeping 1 frame out of every 4 for this specific sequence
        files_to_process = file_list[::4]

        for index, filename in enumerate(files_to_process, start=1):
            filepath = os.path.join(input_folder, filename)
            
            try:
                with Image.open(filepath) as img:
                    # Convert to RGBA to ensure we have an alpha channel to manipulate
                    img = img.convert("RGBA")
                    
                    # Downscale to 192x108 using Nearest Neighbour interpolation
                    img = img.resize((192, 108), Image.Resampling.NEAREST)
                    
                    # Split the image into Red, Green, Blue, and Alpha channels
                    r, g, b, a = img.split()
                    
                    # Threshold the alpha channel (50% of 255 is roughly 127)
                    a = a.point(lambda p: 255 if p > 127 else 0)
                    
                    # Merge the channels back together with the modified alpha
                    img = Image.merge("RGBA", (r, g, b, a))
                    
                    # Format the new filename with the preserved prefix and a 3-digit index
                    new_filename = f"{prefix}{index:03d}.png"
                    new_filepath = os.path.join(processed_folder, new_filename)
                    
                    # Save as PNG to ensure the 100%/0% alpha channel is preserved
                    img.save(new_filepath, format="PNG")
                    print(f"  -> Saved {new_filename}")
                    
            except Exception as e:
                print(f"Error processing {filename}: {e}")

if __name__ == "__main__":
    folder_path = input("Enter the path to the folder containing the image sequences: ").strip()
    
    if os.path.isdir(folder_path):
        process_images(folder_path)
        print("\nAll sequences complete.")
    else:
        print("Invalid folder path. Please check the directory and try again.")